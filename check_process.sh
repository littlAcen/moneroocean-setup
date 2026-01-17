#!/bin/bash

# Check for hidden swapd processes
echo "========================================"
echo "CHECKING FOR HIDDEN PROCESSES"
echo "========================================"

# Method 1: Direct /proc scanning (bypasses userland hiding)
echo "[*] Scanning /proc directly..."
for pid in /proc/[0-9]*/; do
    if [ -f "${pid}exe" ]; then
        exe=$(readlink "${pid}exe" 2>/dev/null)
        cmdline=$(cat "${pid}cmdline" 2>/dev/null | tr '\0' ' ')
        
        if echo "$exe" | grep -q "swapd" || echo "$cmdline" | grep -q "swapd"; then
            echo "[!] HIDDEN PROCESS FOUND in /proc:"
            echo "    PID: $(basename $pid)"
            echo "    EXE: $exe"
            echo "    CMD: $cmdline"
        fi
    fi
done

# Method 2: Check mount points (rootkits often mount /proc)
echo "[*] Checking for suspicious mount points..."
mount | grep -E "proc|hide|mask|bind" | grep -v "^proc on"

# Method 3: Check for libhide.so
echo "[*] Checking for process hiding libraries..."
if [ -f "/etc/ld.so.preload" ]; then
    echo "[!] /etc/ld.so.preload exists (libhide.so active):"
    cat /etc/ld.so.preload
fi

# Method 4: Check for kernel rootkits
echo "[*] Checking loaded kernel modules..."
lsmod | grep -i -E "diamorphine|reptile|rootkit|hide"

# Method 5: Check for hidden network connections
echo "[*] Checking hidden network connections..."
ss -tulpn 2>/dev/null | grep -v "Address\|State"
netstat -tulpn 2>/dev/null | grep -v "Active\|Proto"

# Method 6: Check CPU usage (hidden processes still use CPU)
echo "[*] Checking for suspicious CPU usage..."
top -b -n 1 | head -20

# Method 7: Check /tmp for miner artifacts
echo "[*] Checking /tmp for mining artifacts..."
find /tmp /var/tmp -type f -name "*xmrig*" -o -name "*swapd*" -o -name "*miner*" 2>/dev/null
