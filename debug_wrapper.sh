#!/bin/bash

# ========================================================================
# INTERACTIVE DEBUG WRAPPER
# Führt das Setup-Skript Zeile für Zeile aus mit Bestätigung
# ========================================================================

VERSION=1.0
ORIGINAL_SCRIPT="./setup_mo_4_r00t_FIXED.sh"

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "========================================================================"
echo -e "${CYAN}INTERACTIVE DEBUG WRAPPER v$VERSION${NC}"
echo "========================================================================"
echo ""
echo "Dieses Skript führt das Setup-Skript Zeile für Zeile aus."
echo ""
echo -e "${YELLOW}Steuerung:${NC}"
echo "  [ENTER]     = Zeile ausführen und weiter"
echo "  s [ENTER]   = Zeile überspringen (skip)"
echo "  q [ENTER]   = Skript beenden (quit)"
echo "  c [ENTER]   = Restliche Zeilen automatisch ausführen (continue)"
echo "  b [ENTER]   = Bei Fehler anhalten (break on error mode)"
echo ""
echo "========================================================================"
echo ""

if [ ! -f "$ORIGINAL_SCRIPT" ]; then
    echo -e "${RED}[ERROR] Original-Skript nicht gefunden: $ORIGINAL_SCRIPT${NC}"
    echo "Bitte das Skript im gleichen Verzeichnis ablegen."
    exit 1
fi

# Variablen
LINE_NUM=0
SKIP_COUNT=0
ERROR_COUNT=0
AUTO_MODE=false
BREAK_ON_ERROR=false
IN_HEREDOC=false
HEREDOC_DELIMITER=""
HEREDOC_CONTENT=""

# Funktion zum Ausführen einer Zeile
execute_line() {
    local line="$1"
    local line_num="$2"
    
    # Zeile ausführen
    eval "$line"
    local exit_code=$?
    
    # Exit-Code anzeigen
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}[✓] Exit-Code: $exit_code${NC}"
    else
        echo -e "${RED}[✗] Exit-Code: $exit_code (FEHLER!)${NC}"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        
        if [ "$BREAK_ON_ERROR" = true ]; then
            echo -e "${RED}[!] BREAK ON ERROR aktiviert - Angehalten!${NC}"
            AUTO_MODE=false
            return $exit_code
        fi
    fi
    
    return $exit_code
}

# Funktion zum Anzeigen und Bestätigen einer Zeile
show_and_confirm() {
    local line="$1"
    local line_num="$2"
    
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Zeile $line_num:${NC}"
    echo -e "${BLUE}$line${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    if [ "$AUTO_MODE" = false ]; then
        echo -n "Ausführen? [ENTER/s/q/c/b]: "
        read -r response
        
        case "$response" in
            s|S)
                echo -e "${YELLOW}[SKIP] Zeile übersprungen${NC}"
                SKIP_COUNT=$((SKIP_COUNT + 1))
                return 1
                ;;
            q|Q)
                echo -e "${RED}[QUIT] Skript abgebrochen${NC}"
                echo ""
                echo "Statistik:"
                echo "  Zeilen verarbeitet: $LINE_NUM"
                echo "  Zeilen übersprungen: $SKIP_COUNT"
                echo "  Fehler: $ERROR_COUNT"
                exit 0
                ;;
            c|C)
                echo -e "${GREEN}[CONTINUE] Automatischer Modus aktiviert${NC}"
                AUTO_MODE=true
                ;;
            b|B)
                BREAK_ON_ERROR=true
                echo -e "${YELLOW}[BREAK ON ERROR] Aktiviert - stoppt bei Fehlern${NC}"
                ;;
        esac
    else
        echo -e "${GREEN}[AUTO] Automatisches Ausführen...${NC}"
        sleep 0.1
    fi
    
    return 0
}

echo -e "${CYAN}[*] Starte Zeile-für-Zeile Ausführung...${NC}"
echo ""

# Skript einlesen und Zeile für Zeile verarbeiten
while IFS= read -r line || [ -n "$line" ]; do
    LINE_NUM=$((LINE_NUM + 1))
    
    # Leere Zeilen überspringen
    if [ -z "$line" ]; then
        continue
    fi
    
    # Nur Leerzeichen/Tabs - überspringen
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        continue
    fi
    
    # Kommentarzeilen überspringen (außer Shebang)
    if [[ "$line" =~ ^[[:space:]]*# ]] && [ $LINE_NUM -ne 1 ]; then
        if [ "$AUTO_MODE" = false ]; then
            echo -e "${CYAN}Zeile $LINE_NUM: ${YELLOW}# Kommentar übersprungen${NC}"
        fi
        continue
    fi
    
    # Heredoc Detection
    if [[ "$line" =~ \<\<[[:space:]]*['\"]?([A-Z_]+)['\"]? ]]; then
        HEREDOC_DELIMITER="${BASH_REMATCH[1]}"
        IN_HEREDOC=true
        HEREDOC_CONTENT="$line"$'\n'
        
        if [ "$AUTO_MODE" = false ]; then
            echo -e "${YELLOW}Zeile $LINE_NUM: [HEREDOC START: $HEREDOC_DELIMITER]${NC}"
        fi
        continue
    fi
    
    # Wenn wir in einem Heredoc sind
    if [ "$IN_HEREDOC" = true ]; then
        HEREDOC_CONTENT+="$line"$'\n'
        
        if [[ "$line" =~ ^[[:space:]]*${HEREDOC_DELIMITER}[[:space:]]*$ ]]; then
            # Heredoc Ende
            IN_HEREDOC=false
            
            if [ "$AUTO_MODE" = false ]; then
                echo -e "${YELLOW}Zeile $LINE_NUM: [HEREDOC END: $HEREDOC_DELIMITER]${NC}"
            fi
            
            # Ganzes Heredoc ausführen
            show_and_confirm "$HEREDOC_CONTENT" "$LINE_NUM (heredoc)" || continue
            execute_line "$HEREDOC_CONTENT" "$LINE_NUM (heredoc)"
            
            HEREDOC_CONTENT=""
            HEREDOC_DELIMITER=""
        else
            if [ "$AUTO_MODE" = false ]; then
                echo -e "${YELLOW}Zeile $LINE_NUM: [HEREDOC: $line]${NC}"
            fi
        fi
        continue
    fi
    
    # Normale Zeile anzeigen und bestätigen
    show_and_confirm "$line" "$LINE_NUM || continue
    
    # Zeile ausführen
    execute_line "$line" "$LINE_NUM"
    
done < "$ORIGINAL_SCRIPT"

echo ""
echo "========================================================================"
echo -e "${GREEN}[✓] SKRIPT KOMPLETT DURCHLAUFEN${NC}"
echo "========================================================================"
echo ""
echo "Statistik:"
echo "  Zeilen verarbeitet: $LINE_NUM"
echo "  Zeilen übersprungen: $SKIP_COUNT"
echo "  Fehler aufgetreten: $ERROR_COUNT"
echo ""
echo "========================================================================"
