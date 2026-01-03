#!/bin/bash

# ========================================================================
# INTELLIGENT CHECKPOINT DEBUG
# Pausiert nur bei wichtigen Schritten (Downloads, Service-Aktionen, etc.)
# Dies ist wahrscheinlich die praktischste Debug-Variante
# ========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKPOINT_COUNT=0

# Funktion für Checkpoints
checkpoint() {
    local title="$1"
    local description="$2"
    
    CHECKPOINT_COUNT=$((CHECKPOINT_COUNT + 1))
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${YELLOW}CHECKPOINT #$CHECKPOINT_COUNT${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} ${GREEN}$title${NC}"
    if [ -n "$description" ]; then
        echo -e "${CYAN}║${NC} ${BLUE}$description${NC}"
    fi
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -n "Weiter? [ENTER=ja / q=quit]: "
    read -r response
    
    if [[ "$response" =~ ^[qQ]$ ]]; then
        echo -e "${RED}[QUIT] Abbruch durch Benutzer${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}[→] Fahre fort...${NC}"
    echo ""
}

# Wrapper-Funktionen für wichtige Befehle
monitored_wget() {
    echo -e "${BLUE}[wget]${NC} $@"
    wget "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[✗] wget fehlgeschlagen (Exit: $exit_code)${NC}"
    else
        echo -e "${GREEN}[✓] wget erfolgreich${NC}"
    fi
    return $exit_code
}

monitored_curl() {
    echo -e "${BLUE}[curl]${NC} $@"
    curl "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[✗] curl fehlgeschlagen (Exit: $exit_code)${NC}"
    else
        echo -e "${GREEN}[✓] curl erfolgreich${NC}"
    fi
    return $exit_code
}

monitored_systemctl() {
    echo -e "${BLUE}[systemctl]${NC} $@"
    systemctl "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[✗] systemctl fehlgeschlagen (Exit: $exit_code)${NC}"
    else
        echo -e "${GREEN}[✓] systemctl erfolgreich${NC}"
    fi
    return $exit_code
}

monitored_git() {
    echo -e "${BLUE}[git]${NC} $@"
    git "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[✗] git fehlgeschlagen (Exit: $exit_code)${NC}"
    else
        echo -e "${GREEN}[✓] git erfolgreich${NC}"
    fi
    return $exit_code
}

# Export Funktionen für Subshells
export -f checkpoint
export -f monitored_wget
export -f monitored_curl
export -f monitored_systemctl
export -f monitored_git

clear
echo "========================================================================"
echo -e "${CYAN}INTELLIGENT CHECKPOINT DEBUG MODE${NC}"
echo "========================================================================"
echo ""
echo "Dieses Skript pausiert nur bei wichtigen Schritten:"
echo "  • Vor Downloads"
echo "  • Vor systemd-Operationen"
echo "  • Vor Service-Starts"
echo "  • Vor kritischen Installationen"
echo ""
echo "Alle Befehle werden mit Status-Ausgabe ausgeführt."
echo ""
echo "========================================================================"
echo ""
read -p "Drücke ENTER zum Starten..."

# Modifiziertes Skript mit Checkpoints einlesen
TEMP_SCRIPT=$(mktemp)

cat > "$TEMP_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash

# Lade die Checkpoint-Funktionen
source /dev/stdin << 'EOFFUNCS'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKPOINT_COUNT=0

checkpoint() {
    local title="$1"
    local description="$2"
    CHECKPOINT_COUNT=$((CHECKPOINT_COUNT + 1))
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${YELLOW}CHECKPOINT #$CHECKPOINT_COUNT${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} ${GREEN}$title${NC}"
    [ -n "$description" ] && echo -e "${CYAN}║${NC} ${BLUE}$description${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -n "Weiter? [ENTER=ja / q=quit]: "
    read -r response
    [[ "$response" =~ ^[qQ]$ ]] && { echo -e "${RED}[QUIT]${NC}"; exit 0; }
    echo -e "${GREEN}[→] Fahre fort...${NC}"
    echo ""
}
EOFFUNCS

# Original-Skript mit eingefügten Checkpoints
EOFSCRIPT

# Füge Checkpoints vor wichtigen Operationen ein
echo "" >> "$TEMP_SCRIPT"
echo "checkpoint 'Skript-Start' 'Setup für MoneroOcean Miner'" >> "$TEMP_SCRIPT"
echo "" >> "$TEMP_SCRIPT"

# Füge das Original-Skript ein mit Checkpoints
awk '
BEGIN { in_download = 0; in_systemd = 0; }

# Vor Download-Operationen
/wget|curl.*http/ && !/^[[:space:]]*#/ {
    if (!in_download) {
        print "checkpoint \"Download-Operation\" \"Lade Dateien herunter...\"";
        in_download = 1;
    }
}

# Vor systemd-Operationen  
/systemctl|systemd/ && !/^[[:space:]]*#/ {
    if (!in_systemd) {
        print "checkpoint \"systemd-Operation\" \"Konfiguriere/Starte Services...\"";
        in_systemd = 1;
    }
}

# Reset flags bei neuen Sektionen
/^# ==/ {
    in_download = 0;
    in_systemd = 0;
}

# Spezielle Checkpoints
/# STEP 1:/ { print "checkpoint \"STEP 1\" \"Init System Detection\""; }
/# STEP 2:/ { print "checkpoint \"STEP 2\" \"SSL/TLS Check\""; }
/install.*kernel.*headers/ { print "checkpoint \"Kernel Headers\" \"Installiere Kernel Headers...\""; }
/git clone.*Diamorphine/ { print "checkpoint \"Diamorphine\" \"Installiere Diamorphine Rootkit...\""; }
/git clone.*Reptile/ { print "checkpoint \"Reptile\" \"Installiere Reptile Rootkit...\""; }
/insmod/ { print "checkpoint \"Kernel Module\" \"Lade Kernel-Modul...\""; }

# Alle anderen Zeilen normal ausgeben
{ print }
' ./setup_mo_4_r00t_FIXED.sh >> "$TEMP_SCRIPT"

chmod +x "$TEMP_SCRIPT"

echo ""
echo -e "${GREEN}[*] Starte Skript mit Checkpoint-Monitoring...${NC}"
echo ""

# Führe aus
bash "$TEMP_SCRIPT"
EXIT_CODE=$?

# Cleanup
rm -f "$TEMP_SCRIPT"

echo ""
echo "========================================================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}[✓] Skript erfolgreich beendet${NC}"
else
    echo -e "${RED}[✗] Skript mit Fehler beendet (Exit: $EXIT_CODE)${NC}"
fi
echo "  Checkpoints durchlaufen: $CHECKPOINT_COUNT"
echo "========================================================================"
echo ""

exit $EXIT_CODE
