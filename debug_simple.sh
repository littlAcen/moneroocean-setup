#!/bin/bash

# ========================================================================
# SIMPLIFIED DEBUG VERSION - Mit bash -x trace
# Einfachere Alternative: Zeigt jeden Befehl an vor Ausführung
# ========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "========================================================================"
echo -e "${CYAN}BASH DEBUG MODE (mit -x trace)${NC}"
echo "========================================================================"
echo ""
echo "Dieses Skript führt das Setup mit bash -x (debug trace) aus."
echo "Du siehst jeden ausgeführten Befehl in Echtzeit."
echo ""
echo "Drücke CTRL+C zum Abbrechen"
echo ""
read -p "Drücke ENTER zum Starten..." 

# Export alle Variablen für das Child-Script
export PS4='${CYAN}+[Zeile $LINENO]${NC} '

echo ""
echo -e "${GREEN}[*] Starte Setup-Skript im Debug-Modus...${NC}"
echo ""

# Ausführen mit bash -x für trace output
bash -x ./setup_mo_4_r00t_FIXED.sh 2>&1 | tee setup_debug.log

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "========================================================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}[✓] Skript erfolgreich beendet (Exit: $EXIT_CODE)${NC}"
else
    echo -e "${RED}[✗] Skript mit Fehler beendet (Exit: $EXIT_CODE)${NC}"
fi
echo "========================================================================"
echo ""
echo "Debug-Log gespeichert in: setup_debug.log"
echo ""

exit $EXIT_CODE
