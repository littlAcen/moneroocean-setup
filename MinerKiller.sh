#!/bin/sh

##########################################################################################\
### A script for killing cryptocurrecncy miners in a Linux enviornment
### Provided with zero liability (!)
###
### Some of the malware used as sources for this tool:
### https://pastebin.com/pxc1sXYZ
### https://pastebin.com/jRerGP1u
### SHA256: 2e3e8f980fde5757248e1c72ab8857eb2aea9ef4a37517261a1b013e3dc9e3c4
##########################################################################################\

# Killing processes by name, path, arguments and CPU utilization
processes(){
	killme() {
	  killall -9 chron-34e2fg;ps wx|awk '/34e|r\/v3|moy5|defunct/' | awk '{print $1}' & > /dev/null &
	}

	killa() {
	what=$1;ps auxw|awk "/$what/" |awk '!/awk/' | awk '{print $2}'|xargs kill -9&>/dev/null&
	}

	killa 34e2fg
	killme
	
	# Killing big CPU
	VAR=$(ps uwx|awk '{print $2":"$3}'| grep -v CPU)
	for word in $VAR
	do
	  CPUUSAGE=$(echo $word|awk -F":" '{print $2}'|awk -F"." '{ print $1}')
	  if [ $CPUUSAGE -gt 60 ]; then echo BIG $word; PID=$(echo $word | awk -F":" '{print $1'});LINE=$(ps uwx | grep $PID);COUNT=$(echo $LINE| grep -P "er/v5|34e2|Xtmp|wf32N4|moy5Me|ssh"|wc -l);if [ $COUNT -eq 0 ]; then echo KILLING $line; fi;kill $PID;fi;
	done

	killall \.Historys
	killall \.sshd
	killall neptune
	killall xm64
	killall xm32
	killall xmrig
	killall \.xmrig
	killall suppoieup

	pkill -f sourplum
	pkill wnTKYg && pkill ddg* && rm -rf /tmp/ddg* && rm -rf /tmp/wnTKYg
	
	kill -9 $(pgrep -f -u root mine.moneropool.com)
	kill -9 $(pgrep -f -u root xmr.crypto-pool.fr:8080)
	kill -9 $(pgrep -f -u root xmr.crypto-pool.fr:3333)
	kill -9 $(pgrep -f -u root monerohash.com)
	kill -9 $(pgrep -f -u root /tmp/a7b104c270)
	kill -9 $(pgrep -f -u root xmr.crypto-pool.fr:6666)
	kill -9 $(pgrep -f -u root xmr.crypto-pool.fr:7777)
	kill -9 $(pgrep -f -u root xmr.crypto-pool.fr:443)
	kill -9 $(pgrep -f -u root stratum.f2pool.com:8888)
	kill -9 $(pgrep -f -u root xmrpool.eu)
	kill -9 $(pgrep -f -u root xmrig)
	kill -9 $(pgrep -f -u root xmrigDaemon)
	kill -9 $(pgrep -f -u root xmrigMiner)
	kill -9 $(pgrep -f -u root /var/tmp/java)
	kill -9 $(pgrep -f -u root ddgs)
	kill -9 $(pgrep -f -u root qW3xT)
	kill -9 $(pgrep -f -u root t00ls.ru)
	kill -9 $(pgrep -f -u root /var/tmp/sustes)
	kill -9 $(pgrep -f -u root config.json)
 	kill -9 $(pgrep -f -u root kswapd0)

	kill -9 $(pgrep -f -u root xiaoyao)
	kill -9 $(pgrep -f -u root named)
	kill -9 $(pgrep -f -u root kernelcfg)
	kill -9 $(pgrep -f -u root xiaoxue)
	kill -9 $(pgrep -f -u root kernelupgrade)
	kill -9 $(pgrep -f -u root kernelorg)
	kill -9 $(pgrep -f -u root kernelupdates)

	ps ax|grep var|grep lib|grep jenkins|grep -v httpPort|grep -v headless|grep "\-c"|xargs kill -9
	ps ax|grep -o './[0-9]* -c'| xargs pkill -f

	pkill -f /usr/bin/.sshd
	pkill -f acpid
	pkill -f AnXqV.yam
	pkill -f apaceha
	pkill -f askdljlqw
	pkill -f bashe
	pkill -f bashf
	pkill -f bashg
	pkill -f bashh
	pkill -f bashx
	pkill -f BI5zj
	pkill -f biosetjenkins
	pkill -f bonn.sh
	pkill -f bonns
	pkill -f conn.sh
	pkill -f conns
	pkill -f cryptonight
	pkill -f crypto-pool
	pkill -f ddg.2011
	pkill -f deamon
	pkill -f disk_genius
	pkill -f donns
	pkill -f Duck.sh
	pkill -f gddr
	pkill -f Guard.sh
	pkill -f i586
	pkill -f icb5o
	pkill -f ir29xc1
	pkill -f irqba2anc1
	pkill -f irqba5xnc1
	pkill -f irqbalanc1
	pkill -f irqbalance
	pkill -f irqbnc1
	pkill -f JnKihGjn
	pkill -f jweri
	pkill -f kw.sh
	pkill -f kworker34
	pkill -f kxjd
	pkill -f libapache
	pkill -f Loopback
	pkill -f lx26
	pkill -f mgwsl
	pkill -f minerd
	pkill -f minergate
	pkill -f minexmr
	pkill -f mixnerdx
	pkill -f mstxmr
	pkill -f nanoWatch
	pkill -f nopxi
	pkill -f NXLAi
	pkill -f performedl
	pkill -f polkitd
	pkill -f pro.sh
	pkill -f pythno
	pkill -f qW3xT.2
	pkill -f sourplum
	pkill -f stratum
	pkill -f sustes
	pkill -f wnTKYg
	pkill -f XbashY
	pkill -f XJnRj
	pkill -f xmrig
	pkill -f xmrigDaemon
	pkill -f xmrigMiner
	pkill -f ysaydh
	pkill -f zigw
	
	# crond
	ps ax | grep crond | grep -v grep | awk '{print $1}' > /tmp/crondpid
	while read crondpid
	do
		if [ $(echo  $(ps -p $crondpid -o %cpu | grep -v \%CPU) | sed -e 's/\.[0-9]*//g')  -ge 60 ]
		then
			kill $crondpid
			rm -rf /var/tmp/v3
		fi
	done < /tmp/crondpid
	rm /tmp/crondpid -f
	 
	# sshd
 	# (ALT!) ps ax | grep sshd | grep -v grep | awk '{print $1}' > /tmp/ssdpid
  
 	$(pgrep -f -u root sshd) > /tmp/sshdpid	
	while read sshdpid
	do
		if [ $(echo  $(ps -p $sshdpid -o %cpu | grep -v \%CPU) | sed -e 's/\.[0-9]*//g')  -ge 60 ]
		then
			kill $sshdpid
		fi
	done < /tmp/sshdpid
	rm -f /tmp/sshdpid

	# syslog
	$(pgrep -f -u root syslog) >  /tmp/syslogpid
	while read syslogpid
	do
		if [ $(echo  $(ps -p $syslogpid -o %cpu | grep -v \%CPU) | sed -e 's/\.[0-9]*//g')  -ge 60 ]
		then
			kill  $syslogpid
		fi
	done < /tmp/syslogpid
	rm /tmp/syslogpid -f
}



# Removing miners by known path IOC
files(){
	rm /tmp/.cron
	rm /tmp/.main
	rm /tmp/.yam* -rf
	rm -f /tmp/irq
	rm -f /tmp/irq.sh
	rm -f /tmp/irqbalanc1
	rm -rf /boot/grub/deamon && rm -rf /boot/grub/disk_genius
	rm -rf /tmp/*httpd.conf
	rm -rf /tmp/*httpd.conf*
	rm -rf /tmp/*index_bak*
	rm -rf /tmp/.systemd-private-*
	rm -rf /tmp/.xm*
	rm -rf /tmp/a7b104c270
	rm -rf /tmp/conn
	rm -rf /tmp/conns
	rm -rf /tmp/httpd.conf
	rm -rf /tmp/java*
	rm -rf /tmp/kworkerds /bin/kworkerds /bin/config.json /var/tmp/kworkerds /var/tmp/config.json /usr/local/lib/libjdk.so
	rm -rf /tmp/qW3xT.2 /tmp/ddgs.3013 /tmp/ddgs.3012 /tmp/wnTKYg /tmp/2t3ik
	rm -rf /tmp/root.sh /tmp/pools.txt /tmp/libapache /tmp/config.json /tmp/bashf /tmp/bashg /tmp/libapache
	rm -rf /tmp/xm*
	rm -rf /var/tmp/java*
}

# Vaccination for Redis, will make unusable - uncomment the call to the function if you wish to use it
block_redis_port() {
	iptables -I INPUT -p TCP --dport 6379 -j REJECT
	iptables -I INPUT -s 127.0.0.1 -p tcp --dport 6379 -j ACCEPT
	iptables-save
	touch /tmp/.tables
}

# Killing and blocking miners by network related IOC
network(){
	# Kill by known ports/IPs
 	kill -9 $(netstat -anp | grep 91.214.65.238:58091 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep 69.28.55.86:443 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep 185.71.65.238 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep 140.82.52.87 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :3333 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :4444 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :5555 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :6666 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :7777 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :3347 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :14444 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :14433 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	kill -9 $(netstat -anp | grep :13531 |awk '{print $7}'| awk -F'[/]' '{print $1}')
	
	# Block known miner ports
	iptables -F
	iptables -X
	
	iptables -A OUTPUT -p tcp --dport 3333 -j DROP
	iptables -A OUTPUT -p tcp --dport 5555 -j DROP
	iptables -A OUTPUT -p tcp --dport 7777 -j DROP
	iptables -A OUTPUT -p tcp --dport 9999 -j DROP
	service iptables reload

	# uncomment the line below this one for Redis exploit vaccination , will make unusable - uncomment the call to the function if you wish to use it
	# block_redis_port
}

files
processes
network
echo "DONE"
