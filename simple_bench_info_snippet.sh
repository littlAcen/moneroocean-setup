#!/bin/bash
# ==================== COPY THIS INTO YOUR SCRIPT ====================
# Add this RIGHT BEFORE you send your existing email with the logfile
# It will collect system info and add it to your email body

# ==================== COLLECT SYSTEM INFO (like bench.sh) ====================

collect_bench_info() {
    echo "----------------------------------------------------------------------"
    echo "           SYSTEM INFORMATION REPORT (like bench.sh)"
    echo "----------------------------------------------------------------------"
    echo " Timestamp          : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "----------------------------------------------------------------------"
    
    # CPU
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    local cpu_mhz=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "?")
    local cpu_cache=$(grep -m1 "cache size" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "?")
    
    echo " CPU Model          : $cpu_model"
    echo " CPU Cores          : $cpu_cores @ $cpu_mhz MHz"
    echo " CPU Cache          : $cpu_cache"
    
    # AES-NI
    if grep -q aes /proc/cpuinfo 2>/dev/null; then
        echo " AES-NI             : ✓ Enabled"
    else
        echo " AES-NI             : ✗ Disabled"
    fi
    
    # VM support
    if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
        echo " VM-x/AMD-V         : ✓ Enabled"
    else
        echo " VM-x/AMD-V         : ✗ Disabled"
    fi
    
    # Disk
    local disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "?")
    local disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}' || echo "?")
    echo " Total Disk         : $disk_total ($disk_used Used)"
    
    # RAM
    local ram_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "?")
    local ram_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "?")
    local swap_total=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "?")
    local swap_used=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3}' || echo "?")
    echo " Total RAM          : $ram_total ($ram_used Used)"
    echo " Total Swap         : $swap_total ($swap_used Used)"
    
    # Uptime
    local uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "?")
    echo " System Uptime      : $uptime_str"
    echo " Load Average       : $load_avg"
    
    # OS
    local os_name=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Linux")
    local arch=$(uname -m 2>/dev/null || echo "?")
    local kernel=$(uname -r 2>/dev/null || echo "?")
    echo " OS                 : $os_name"
    echo " Arch               : $arch"
    echo " Kernel             : $kernel"
    
    # Network
    local tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    echo " TCP Congestion Ctrl: $tcp_cc"
    
    # Virtualization
    local virt=$(systemd-detect-virt 2>/dev/null || echo "Unknown")
    [ "$virt" = "none" ] && virt="Bare Metal"
    echo " Virtualization     : $virt"
    
    # IP
    local ipv4=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    local ipv6=$(curl -s6 --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    
    if [ "$ipv4" != "Offline" ]; then
        echo " IPv4/IPv6          : ✓ Online / $([ "$ipv6" != "Offline" ] && echo "✓ Online" || echo "✗ Offline")"
    else
        echo " IPv4/IPv6          : ✗ Offline / ✗ Offline"
    fi
    
    # ISP Info
    if [ "$ipv4" != "Offline" ]; then
        local isp_json=$(curl -s --max-time 5 "http://ip-api.com/json/$ipv4" 2>/dev/null)
        if [ -n "$isp_json" ]; then
            local org=$(echo "$isp_json" | grep -o '"org":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local city=$(echo "$isp_json" | grep -o '"city":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local country=$(echo "$isp_json" | grep -o '"countryCode":"[^"]*' | cut -d'"' -f4 || echo "?")
            local region=$(echo "$isp_json" | grep -o '"regionName":"[^"]*' | cut -d'"' -f4 || echo "?")
            
            echo " Organization       : $org"
            echo " Location           : $city / $country"
            echo " Region             : $region"
        fi
    fi
    
    echo "----------------------------------------------------------------------"
    echo " Miner Type         : XMRig"
    echo " Wallet             : ${WALLET:0:10}...${WALLET: -10}"
    echo " Installation       : Completed"
    echo "----------------------------------------------------------------------"
}

# ==================== HOW TO USE ====================
# 
# BEFORE your existing email code, add:
#
#   SYSTEM_INFO=$(collect_bench_info)
#
# THEN in your email body, add:
#
#   EMAIL_BODY="Installation Complete!
#
#   $SYSTEM_INFO
#
#   Full log attached.
#   "
#
# EXAMPLE:
#
#   # Collect system info
#   SYSTEM_INFO=$(collect_bench_info)
#   
#   # Build email
#   EMAIL_BODY="Miner installed successfully!
#   Hostname: $(hostname)
#   Time: $(date)
#   
#   $SYSTEM_INFO
#   
#   See attached log for details.
#   "
#   
#   # Send email (your existing code)
#   echo "$EMAIL_BODY" | mail -s "Miner Installed" -a /path/to/logfile.log your@email.com
#
# ==================== END ====================
