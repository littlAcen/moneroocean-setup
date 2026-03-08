#!/bin/bash

hosts=(
  "ash-speed.hetzner.com"
  "testfile.org"
  "alexanderboehme.de"
  "ipv4.download.thinkbroadband.com"
  "proof.ovh.net"
  "speedtest.tele2.net"
  "f.koningnet.nl"
  "testfiles.hostnetworks.com.au"
  "speedtest.init7.net"
  "212.183.159.230"
  "fsn1-speed.hetzner.com"
  "speedtest.bitel.io"
)

urllist=(
  "https://ash-speed.hetzner.com/1GB.bin"
  "https://testfile.org/file-1GB"
  "https://alexanderboehme.de/speed/1GB.bin"
  "http://ipv4.download.thinkbroadband.com/1GB.zip"
  "https://proof.ovh.net/files/1Gb.dat"
  "http://speedtest.tele2.net/1GB.zip"
  "https://f.koningnet.nl/1GB.bin"
  "http://testfiles.hostnetworks.com.au/1000MB.iso"
  "http://speedtest.init7.net/1GB.dd"
  "http://212.183.159.230/1GB.zip"
  "https://fsn1-speed.hetzner.com/1GB.bin"
  "https://speedtest.bitel.io/Testdateien/1000MB"
)

echo -e "\e[1;36m=== Speedtest (10s pro Server) ===\e[0m\n"
echo -e "\e[1;33m[1/2] Ping-Test aller Server...\e[0m\n"

ping_list=""
for i in "${!hosts[@]}"; do
  host="${hosts[$i]}"
  p=$(ping -c 2 -W 2 "$host" 2>/dev/null | awk -F"/" '/avg/{print $5}')
  if [ -n "$p" ]; then
    ping_list+="$p $i\n"
    printf "\e[1;32m✔ %-45s %s ms\e[0m\n" "$host" "$p"
  else
    ping_list+="9999 $i\n"
    printf "\e[1;31m✘ %-45s nicht erreichbar\e[0m\n" "$host"
  fi
done

echo -e "\n\e[1;33m[2/2] Top 5 werden je 10s getestet...\e[0m\n"

top5_idx=$(echo -e "$ping_list" | sort -n | head -5 | awk '{print $2}')
speeds=()
n=0
total=5

for idx in $top5_idx; do
  n=$((n+1))
  host="${hosts[$idx]}"
  url="${urllist[$idx]}"
  p=$(echo -e "$ping_list" | awk -v i="$idx" '$2==i{print $1}')

  echo -e "\e[1;36m[$n/$total]\e[0m \e[1;33m${host}\e[0m \e[2m(ping: ${p}ms)\e[0m"

  s=$(curl -L --http1.1 --max-time 10 --connect-timeout 3 -o /dev/null \
    -w "%{speed_download}" "$url" 2>/dev/tty)

  mb=$(echo "$s" | awk '{printf "%.2f", $1/1048576}')

  if (( $(echo "$mb > 0" | bc -l) )); then
    echo -e "\e[1;32m✔ ${mb} MB/s\e[0m\n"
    speeds+=($mb)
  else
    echo -e "\e[1;31m✘ Nicht erreichbar\e[0m\n"
  fi
done

echo -e "\e[1;36m══════════════════════════\e[0m"

if [ ${#speeds[@]} -gt 0 ]; then
  avg=$(echo "${speeds[@]}" | tr " " "\n" | awk '{s+=$1;c++} END {printf "%.2f", s/c}')
  best=$(echo "${speeds[@]}" | tr " " "\n" | awk 'BEGIN{m=0} {$1>m&&(m=$1)} END {printf "%.2f", m}')
  echo -e "Erfolgreich  -> \e[1;33m${#speeds[@]}/$total Server\e[0m"
  echo -e "Beste        -> \e[1;32m${best} MB/s\e[0m"
  echo -e "Durchschnitt -> \e[1;35m${avg} MB/s\e[0m"
fi
