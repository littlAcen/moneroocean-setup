#!/bin/bash

# ========================================================================
# STEP-BY-STEP DEBUG MODE
# Pausiert bei JEDEM ausgeführten Befehl und wartet auf Bestätigung
# ========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counter
COMMAND_COUNT=0
AUTO_MODE=false

# Debug trap function - wird VOR jedem Command ausgeführt
debug_trap() {
    local cmd="$BASH_COMMAND"
    
    # Ignoriere interne Bash-Kommandos
    [[ "$cmd" == "debug_trap" ]] && return
    [[ "$cmd" == *"COMMAND_COUNT"* ]] && return
    
    COMMAND_COUNT=$((COMMAND_COUNT + 1))
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}[Command #$COMMAND_COUNT] Zeile $LINENO in ${BASH_SOURCE[1]}${NC}"
    echo -e "${BLUE}>>> $cmd${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    
    if [ "$AUTO_MODE" = false ]; then
        echo -n "Ausführen? [ENTER=ja / s=skip / c=continue / q=quit]: "
        read -r response
        
        case "$response" in
            s|S)
                echo -e "${YELLOW}[SKIP]${NC} Befehl übersprungen"
                return 1
                ;;
            c|C)
                AUTO_MODE=true
                echo -e "${GREEN}[AUTO MODE]${NC} Führe Rest automatisch aus..."
                ;;
            q|Q)
                echo -e "${RED}[QUIT]${NC} Abbruch durch Benutzer"
                exit 0
                ;;
            *)
                echo -e "${GREEN}[EXEC]${NC} Führe aus..."
                ;;
        esac
    else
        echo -e "${GREEN}[AUTO]${NC}"
        sleep 0.05  # Kurze Pause, damit man noch folgen kann
    fi
}

# Aktiviere den DEBUG trap
trap debug_trap DEBUG

# Source das Original-Skript
ORIGINAL_SCRIPT="./setup_mo_4_r00t_FIXED.sh"

clear
echo "========================================================================"
echo -e "${CYAN}STEP-BY-STEP DEBUG MODE${NC}"
echo "========================================================================"
echo ""
echo "Dieses Skript pausiert bei JEDEM Befehl und wartet auf Bestätigung."
echo ""
echo -e "${YELLOW}Steuerung:${NC}"
echo "  [ENTER]     = Befehl ausführen"
echo "  s [ENTER]   = Befehl überspringen"
echo "  c [ENTER]   = Rest automatisch ausführen"
echo "  q [ENTER]   = Skript beenden"
echo "  CTRL+C      = Sofort abbrechen"
echo ""
echo -e "${RED}WARNUNG: Dies wird SEHR viele Pausen erzeugen!${NC}"
echo -e "${YELLOW}Tipp: Nutze 'c' nach ein paar Schritten für Auto-Mode${NC}"
echo ""
echo "========================================================================"
echo ""
read -p "Drücke ENTER zum Starten..."

if [ ! -f "$ORIGINAL_SCRIPT" ]; then
    echo -e "${RED}[ERROR] Original-Skript nicht gefunden: $ORIGINAL_SCRIPT${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}[*] Starte Skript mit Step-by-Step Debug...${NC}"
echo ""

# Führe das Skript aus
source "$ORIGINAL_SCRIPT"

echo ""
echo "========================================================================"
echo -e "${GREEN}[✓] SKRIPT BEENDET${NC}"
echo "========================================================================"
echo ""
echo "Statistik:"
echo "  Befehle ausgeführt: $COMMAND_COUNT"
echo ""
