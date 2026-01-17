#!/bin/bash

PROCESS_NAME="swapd"
LOG_FILE="/var/log/process_check.log"

check_process() {
    local process="$1"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking process: $process" | tee -a "$LOG_FILE"
    
    # Method 1: Check with ps and count
    PS_COUNT=$(ps aux | grep -v grep | grep -c "$process")
    echo "[*] ps aux shows $PS_COUNT instances" | tee -a "$LOG_FILE"
    
    # Method 2: Check with pgrep
    PGREP_COUNT=$(pgrep -f "$process" | wc -l)
    echo "[*] pgrep shows $PGREP_COUNT PIDs" | tee -a "$LOG_FILE"
    
    # Method 3: Check with pidof
    PIDS=$(pidof "$process")
    if [ -n "$PIDS" ]; then
        echo "[*] pidof shows PIDs: $PIDS" | tee -a "$LOG_FILE"
        PID_COUNT=$(echo "$PIDS" | wc -w)
    else
        echo "[*] pidof shows no PIDs" | tee -a "$LOG_FILE"
        PID_COUNT=0
    fi
    
    # Method 4: Check service status (if it's a service)
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status "$process" 2>/dev/null | head -3 | tee -a "$LOG_FILE"
    elif [ -f "/etc/init.d/$process" ]; then
        /etc/init.d/"$process" status 2>/dev/null | tee -a "$LOG_FILE"
    fi
    
    # Method 5: Check process tree
    echo "[*] Process tree:" | tee -a "$LOG_FILE"
    pstree -p | grep -i "$process" | tee -a "$LOG_FILE"
    
    # Method 6: Check with lsof (open files)
    echo "[*] Open files:" | tee -a "$LOG_FILE"
    lsof -p $(pgrep -f "$process" 2>/dev/null | tr '\n' ',') 2>/dev/null | head -5 | tee -a "$LOG_FILE"
    
    # Determine if running
    if [ $PS_COUNT -gt 0 ] || [ $PGREP_COUNT -gt 0 ] || [ $PID_COUNT -gt 0 ]; then
        echo "[✓] PROCESS IS RUNNING" | tee -a "$LOG_FILE"
        return 0
    else
        echo "[✗] PROCESS IS NOT RUNNING" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Also check for hidden/rootkit processes
check_hidden_processes() {
    echo "========================================" | tee -a "$LOG_FILE"
    echo "[*] Checking for hidden processes..." | tee -a "$LOG_FILE"
    
    # Check /proc for hidden processes
    PROC_COUNT=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l)
    PS_COUNT=$(ps aux | wc -l)
    echo "[*] /proc shows $PROC_COUNT processes, ps shows $PS_COUNT processes" | tee -a "$LOG_FILE"
    
    # Look for suspicious mount points (rootkit hiding)
    echo "[*] Checking mount points..." | tee -a "$LOG_FILE"
    mount | grep -E "proc|hide|mask" | tee -a "$LOG_FILE"
    
    # Check for libhide.so
    if [ -f "/etc/ld.so.preload" ]; then
        echo "[!] WARNING: /etc/ld.so.preload exists (possible process hiding)" | tee -a "$LOG_FILE"
        cat /etc/ld.so.preload | tee -a "$LOG_FILE"
    fi
    
    # Check for rootkit modules
    echo "[*] Checking loaded kernel modules..." | tee -a "$LOG_FILE"
    lsmod | grep -i -E "rootkit|hide|reptile|diamorphine" | tee -a "$LOG_FILE"
}

# Main check
check_process "$PROCESS_NAME"
check_hidden_processes

echo "========================================" | tee -a "$LOG_FILE"
echo "[*] Full process list containing '$PROCESS_NAME':" | tee -a "$LOG_FILE"
ps aux | grep -i "$PROCESS_NAME" | grep -v grep | tee -a "$LOG_FILE"
