#!/bin/bash

# Auto-install iperf3
if ! command -v iperf3 &>/dev/null; then
  echo -e "\e[1;33mInstalliere iperf3...\e[0m"
  if command -v apt &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt install -y iperf3
  elif command -v dnf &>/dev/null; then
    dnf install -y iperf3
  elif command -v yum &>/dev/null; then
    yum install -y iperf3
  elif command -v zypper &>/dev/null; then
    zypper install -y iperf3
  elif command -v pacman &>/dev/null; then
    pacman -S --noconfirm iperf3
  elif command -v pkg &>/dev/null; then
    pkg install -y iperf3
  elif command -v apk &>/dev/null; then
    apk add iperf3
  else
    echo -e "\e[1;31mKein Paketmanager gefunden! Bitte iperf3 manuell installieren.\e[0m"
    exit 1
  fi
fi

servers=(
  "iperf.he.net|5201|Hurricane Electric"
  "iperf.par2.as49434.net|9200|Hosting.de Frankfurt"
  "bouygues.testdebit.info|5209|Bouygues Paris"
  "ping.online.net|5200|Online.net Paris"
  "iperf.appliwave.com|5200|Appliwave Frankfurt"
)

echo -e "\e[1;36m=== iperf3 Speedtest ===\e[0m\n"
echo -e "\e[1;33m[1/2] Ping-Test aller Server...\e[0m\n"

ping_list=""
i=0
for e in "${servers[@]}"; do
  h=$(echo "$e" | cut -d"|" -f1)
  l=$(echo "$e" | cut -d"|" -f3)
  p=$(ping -c 2 -W 2 "$h" 2>/dev/null | awk -F"/" '/avg/{print $5}')
  if [ -n "$p" ]; then
    ping_list+="$p $i\n"
    printf "\e[1;32m✔ %-30s %s ms\e[0m\n" "$l" "$p"
  else
    ping_list+="9999 $i\n"
    printf "\e[1;31m✘ %-30s nicht erreichbar\e[0m\n" "$l"
  fi
  i=$((i+1))
done

echo -e "\n\e[1;33m[2/2] Top 3 werden je 10s getestet...\e[0m\n"

top3=$(echo -e "$ping_list" | sort -n | head -3 | awk '{print $2}')
speeds=()
n=0

for idx in $top3; do
  n=$((n+1))
  e="${servers[$idx]}"
  h=$(echo "$e" | cut -d"|" -f1)
  port=$(echo "$e" | cut -d"|" -f2)
  l=$(echo "$e" | cut -d"|" -f3)
  p=$(echo -e "$ping_list" | awk -v i="$idx" '$2==i{print $1}')

  echo -e "\e[1;36m[$n/3]\e[0m \e[1;33m$l\e[0m \e[2m(ping: ${p}ms)\e[0m"

  r=$(iperf3 -c "$h" -p "$port" -t 10 --connect-timeout 3000 2>&1)
  if echo "$r" | grep -q "receiver"; then
    mbps=$(echo "$r" | grep "receiver" | awk '{print $(NF-2), $(NF-1)}')
    mbs=$(echo "$r" | grep "receiver" | awk '{printf "%.2f", $(NF-2)*125000/1048576}')
    echo -e "\e[1;32m✔ ${mbps} = ${mbs} MB/s\e[0m\n"
    speeds+=($mbs)
  else
    echo -e "\e[1;31m✘ Nicht erreichbar\e[0m\n"
  fi
done

echo -e "\e[1;36m══════════════════════════\e[0m"
if [ ${#speeds[@]} -gt 0 ]; then
  avg=$(echo "${speeds[@]}" | tr " " "\n" | awk '{s+=$1;c++} END {printf "%.2f", s/c}')
  best=$(echo "${speeds[@]}" | tr " " "\n" | awk 'BEGIN{m=0} {$1>m&&(m=$1)} END {printf "%.2f", m}')
  echo -e "Erfolgreich  -> \e[1;33m${#speeds[@]}/3 Server\e[0m"
  echo -e "Beste        -> \e[1;32m${best} MB/s\e[0m"
  echo -e "Durchschnitt -> \e[1;35m${avg} MB/s\e[0m"
fi
