# ==================== SYSTEM INFO & EMAIL REPORT ====================
# Add this to the beginning of your setup script (after WALLET check)

# CONFIGURATION - Set your email and method
REPORT_EMAIL="your-email@example.com"  # ← CHANGE THIS!
EMAIL_METHOD="telegram"  # Options: telegram, mailgun, sendgrid, local_mail, webhook, discord

# Telegram Bot Configuration (Easiest - Free!)
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"

# Discord Webhook (Free & Easy!)
DISCORD_WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL"

# Mailgun (if you prefer email)
MAILGUN_API_KEY="YOUR_API_KEY"
MAILGUN_DOMAIN="YOUR_DOMAIN.mailgun.org"

# ==================== SYSTEM INFO COLLECTOR ====================

collect_system_info() {
    local info=""
    
    # CPU Info
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    local cpu_mhz=$(grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | xargs)
    
    # Memory Info
    local total_ram=$(free -h | awk '/^Mem:/ {print $2}')
    local used_ram=$(free -h | awk '/^Mem:/ {print $3}')
    local total_swap=$(free -h | awk '/^Swap:/ {print $2}')
    
    # Disk Info
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_used=$(df -h / | awk 'NR==2 {print $3}')
    
    # System Info
    local uptime=$(uptime -p | sed 's/up //')
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local os=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    local kernel=$(uname -r)
    local arch=$(uname -m)
    
    # Network Info
    local hostname=$(hostname)
    local ipv4=$(curl -s4 ifconfig.me 2>/dev/null || echo "N/A")
    
    # Virtualization
    local virt=$(systemd-detect-virt 2>/dev/null || echo "Unknown")
    
    # Build report
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="        MINER INSTALLATION REPORT\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="📅 Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="💻 SYSTEM\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="🖥️  Hostname: $hostname\n"
    info+="🌍 IPv4: $ipv4\n"
    info+="⚙️  OS: $os\n"
    info+="🔧 Kernel: $kernel\n"
    info+="📐 Arch: $arch\n"
    info+="🔄 Virtualization: $virt\n"
    info+="⏱️  Uptime: $uptime\n"
    info+="📊 Load: $load\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="🧠 HARDWARE\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="🔲 CPU: $cpu_model\n"
    info+="🔢 Cores: $cpu_cores @ ${cpu_mhz} MHz\n"
    info+="💾 RAM: $total_ram ($used_ram used)\n"
    info+="💿 Swap: $total_swap\n"
    info+="💽 Disk: $disk_total ($disk_used used)\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="⛏️  MINER\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    info+="📦 Type: XMRig\n"
    info+="💰 Wallet: ${WALLET:0:10}...${WALLET: -10}\n"
    info+="🚀 Status: Installing...\n"
    info+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    echo -e "$info"
}

# ==================== SEND FUNCTIONS ====================

send_telegram() {
    local message="$1"
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null 2>&1
    
    return $?
}

send_discord() {
    local message="$1"
    
    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"content\": \"\`\`\`\n${message}\n\`\`\`\"
        }" > /dev/null 2>&1
    
    return $?
}

send_mailgun() {
    local subject="$1"
    local body="$2"
    
    curl -s --user "api:$MAILGUN_API_KEY" \
        "https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages" \
        -F from="Miner <noreply@$MAILGUN_DOMAIN>" \
        -F to="$REPORT_EMAIL" \
        -F subject="$subject" \
        -F text="$body" > /dev/null 2>&1
    
    return $?
}

# ==================== MAIN SEND FUNCTION ====================

send_installation_report() {
    # Skip if no email/chat configured
    if [ "$REPORT_EMAIL" = "your-email@example.com" ] && \
       [ -z "$TELEGRAM_BOT_TOKEN" ] && \
       [ -z "$DISCORD_WEBHOOK_URL" ]; then
        return 0
    fi
    
    echo ""
    echo "[*] Collecting system information..."
    
    local report=$(collect_system_info)
    local hostname=$(hostname)
    local subject="⛏️ Miner Installed - $hostname - $(date +%Y-%m-%d)"
    
    echo ""
    echo "$report"
    echo ""
    
    echo "[*] Sending installation report..."
    
    case "$EMAIL_METHOD" in
        telegram)
            if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                if send_telegram "$report"; then
                    echo "[✓] Report sent via Telegram"
                else
                    echo "[!] Failed to send Telegram message"
                fi
            fi
            ;;
        discord)
            if [ -n "$DISCORD_WEBHOOK_URL" ]; then
                if send_discord "$report"; then
                    echo "[✓] Report sent via Discord"
                else
                    echo "[!] Failed to send Discord message"
                fi
            fi
            ;;
        mailgun)
            if send_mailgun "$subject" "$report"; then
                echo "[✓] Report sent via Mailgun"
            else
                echo "[!] Failed to send email"
            fi
            ;;
        local_mail)
            if command -v mail >/dev/null 2>&1; then
                echo "$report" | mail -s "$subject" "$REPORT_EMAIL"
                echo "[✓] Report sent via local mail"
            fi
            ;;
        *)
            echo "[!] No notification method configured"
            ;;
    esac
    
    echo ""
}

# ==================== USAGE ====================
# Add this line after WALLET check in your setup script:
#
# send_installation_report
#
# ==================== EXAMPLE ====================
# #!/bin/bash
# WALLET="$1"
# if [ -z "$WALLET" ]; then
#     echo "Usage: $0 <wallet>"
#     exit 1
# fi
# 
# # Configure notification
# REPORT_EMAIL="your@email.com"
# EMAIL_METHOD="telegram"
# TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
# TELEGRAM_CHAT_ID="123456789"
# 
# # Send report
# send_installation_report
# 
# # Continue with installation...
# echo "Installing miner..."
