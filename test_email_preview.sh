#!/bin/bash
# Quick Test - Preview how your email will look with system info

echo "========================================"
echo "EMAIL PREVIEW - System Info Test"
echo "========================================"
echo ""
echo "This shows what the email will contain:"
echo ""

# ==================== COPY OF collect_bench_info FUNCTION ====================
collect_bench_info() {
    cat << 'BENCH_INFO'
======================================================================
           DETAILED SYSTEM INFORMATION (like bench.sh)
======================================================================
BENCH_INFO
    
    echo " Timestamp          : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "----------------------------------------------------------------------"
    
    # CPU Information
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "Unknown")
    local cpu_mhz=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    local cpu_cache=$(grep -m1 "cache size" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    
    echo " CPU Model          : $cpu_model"
    echo " CPU Cores          : $cpu_cores @ $cpu_mhz MHz"
    echo " CPU Cache          : $cpu_cache"
    
    # Check AES-NI support
    if grep -q aes /proc/cpuinfo 2>/dev/null; then
        echo " AES-NI             : ✓ Enabled"
    else
        echo " AES-NI             : ✗ Disabled"
    fi
    
    # Check VM extensions
    if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
        echo " VM-x/AMD-V         : ✓ Enabled"
    else
        echo " VM-x/AMD-V         : ✗ Disabled"
    fi
    
    # Disk Information
    local disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "Unknown")
    local disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}' || echo "Unknown")
    local disk_avail=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "Unknown")
    echo " Total Disk         : $disk_total ($disk_used Used, $disk_avail Available)"
    
    # RAM Information
    local ram_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "Unknown")
    local ram_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "Unknown")
    local ram_free=$(free -h 2>/dev/null | awk '/^Mem:/ {print $4}' || echo "Unknown")
    echo " Total RAM          : $ram_total ($ram_used Used, $ram_free Free)"
    
    # Swap Information
    local swap_total=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "Unknown")
    local swap_used=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3}' || echo "Unknown")
    echo " Total Swap         : $swap_total ($swap_used Used)"
    
    # System Uptime
    local uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    echo " System Uptime      : $uptime_str"
    
    # Load Average
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "Unknown")
    echo " Load Average       : $load_avg"
    
    # OS Information
    local os_name=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown Linux")
    local arch=$(uname -m 2>/dev/null || echo "Unknown")
    local kernel=$(uname -r 2>/dev/null || echo "Unknown")
    echo " OS                 : $os_name"
    echo " Arch               : $arch ($(getconf LONG_BIT 2>/dev/null || echo "?") Bit)"
    echo " Kernel             : $kernel"
    
    # TCP Congestion Control
    local tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
    echo " TCP Congestion Ctrl: $tcp_cc"
    
    # Virtualization
    local virt="Unknown"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        [ "$virt" = "none" ] && virt="Bare Metal"
    elif [ -f /proc/cpuinfo ]; then
        if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
            virt="Virtualized (Unknown Type)"
        else
            virt="Bare Metal"
        fi
    fi
    echo " Virtualization     : $virt"
    
    # IPv4 and IPv6 Status
    local ipv4=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    local ipv6=$(curl -6 -s --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    
    if [ "$ipv4" != "Offline" ]; then
        echo " IPv4/IPv6          : ✓ Online / $([ "$ipv6" != "Offline" ] && echo "✓ Online" || echo "✗ Offline")"
    else
        echo " IPv4/IPv6          : ✗ Offline / ✗ Offline"
    fi
    
    # ISP and Location Information
    if [ "$ipv4" != "Offline" ]; then
        echo " [*] Fetching ISP and location info..."
        local isp_json=$(curl -s --max-time 5 "http://ip-api.com/json/$ipv4" 2>/dev/null)
        if [ -n "$isp_json" ]; then
            local org=$(echo "$isp_json" | grep -o '"org":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local isp=$(echo "$isp_json" | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local city=$(echo "$isp_json" | grep -o '"city":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local country=$(echo "$isp_json" | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local region=$(echo "$isp_json" | grep -o '"regionName":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local asn=$(echo "$isp_json" | grep -o '"as":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            
            echo " Organization       : $org"
            echo " ISP                : $isp"
            echo " Location           : $city / $country"
            echo " Region             : $region"
            [ "$asn" != "Unknown" ] && echo " ASN                : $asn"
        fi
    fi
    
    echo "----------------------------------------------------------------------"
}

# ==================== SHOW PREVIEW ====================

cat << EOF
=== SYSTEM REPORT ===
Hostname: $(hostname)
User: $(whoami)
Public IP: $(curl -4 -s --max-time 5 ifconfig.me || echo "unavailable")
Local IP: $(hostname -I 2>/dev/null | awk '{print $1}' || echo "unavailable")

=== BASIC RESOURCES ===
RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "unavailable")
CPU: $(nproc 2>/dev/null || echo "unavailable") cores
Storage: $(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "unavailable")

$(collect_bench_info)

=== SHELL HISTORY ===
[... shell history would be here ...]

EOF

echo ""
echo "========================================"
echo "This is what will be in the email!"
echo "========================================"
echo ""
echo "The actual email will also include:"
echo "  - SSH connection information"
echo "  - Recent SSH commands from history"
echo "  - Full shell history"
echo ""
