#!/bin/bash
# Quick Test - System Info Report
# Test your notification configuration before integrating into setup scripts

echo "========================================"
echo "SYSTEM INFO NOTIFICATION - QUICK TEST"
echo "========================================"
echo ""

# ==================== CONFIGURATION ====================
echo "Step 1: Choose notification method"
echo ""
echo "Available methods:"
echo "  1) Telegram Bot (Free & Easy - RECOMMENDED)"
echo "  2) Discord Webhook (Free & Easy)"
echo "  3) Mailgun Email (Free 5,000/month)"
echo "  4) SendGrid Email (Free 100/day)"
echo "  5) Local Mail (if configured)"
echo ""
read -p "Choose method (1-5): " METHOD_CHOICE

case "$METHOD_CHOICE" in
    1)
        EMAIL_METHOD="telegram"
        echo ""
        echo "Telegram Setup:"
        echo "1. Open Telegram and search for @BotFather"
        echo "2. Send /newbot and follow instructions"
        echo "3. Get your Bot Token"
        echo "4. Search for @userinfobot to get your Chat ID"
        echo ""
        read -p "Enter Bot Token: " TELEGRAM_BOT_TOKEN
        read -p "Enter Chat ID: " TELEGRAM_CHAT_ID
        ;;
    2)
        EMAIL_METHOD="discord"
        echo ""
        echo "Discord Setup:"
        echo "1. Open Discord Server Settings → Integrations → Webhooks"
        echo "2. Create New Webhook"
        echo "3. Copy the Webhook URL"
        echo ""
        read -p "Enter Discord Webhook URL: " DISCORD_WEBHOOK_URL
        ;;
    3)
        EMAIL_METHOD="mailgun"
        echo ""
        read -p "Enter your email address: " REPORT_EMAIL
        read -p "Enter Mailgun API Key: " MAILGUN_API_KEY
        read -p "Enter Mailgun Domain: " MAILGUN_DOMAIN
        ;;
    4)
        EMAIL_METHOD="sendgrid"
        echo ""
        read -p "Enter your email address: " REPORT_EMAIL
        read -p "Enter SendGrid API Key: " SENDGRID_API_KEY
        ;;
    5)
        EMAIL_METHOD="local_mail"
        read -p "Enter your email address: " REPORT_EMAIL
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "========================================"
echo "COLLECTING SYSTEM INFO"
echo "========================================"
echo ""

# ==================== COLLECT SYSTEM INFO ====================

collect_info() {
    # CPU
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs 2>/dev/null || echo "Unknown")
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "Unknown")
    local cpu_mhz=$(grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | xargs 2>/dev/null || echo "Unknown")
    
    # Memory
    local total_ram=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "Unknown")
    local used_ram=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "Unknown")
    local total_swap=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "Unknown")
    
    # Disk
    local disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "Unknown")
    local disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}' || echo "Unknown")
    
    # System
    local uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")
    local load=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "Unknown")
    local os=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")
    local kernel=$(uname -r 2>/dev/null || echo "Unknown")
    local arch=$(uname -m 2>/dev/null || echo "Unknown")
    
    # Network
    local hostname=$(hostname 2>/dev/null || echo "Unknown")
    local ipv4=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || echo "Offline")
    
    # Virt
    local virt=$(systemd-detect-virt 2>/dev/null || echo "Unknown")
    
    # Build message
    local msg=""
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    msg+="     SYSTEM INFO REPORT - TEST\n"
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    msg+="📅 $(date '+%Y-%m-%d %H:%M:%S %Z')\n"
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    msg+="💻 SYSTEM\n"
    msg+="🖥️  Host: $hostname\n"
    msg+="🌍 IP: $ipv4\n"
    msg+="⚙️  OS: $os\n"
    msg+="🔧 Kernel: $kernel\n"
    msg+="📐 Arch: $arch\n"
    msg+="🔄 Virt: $virt\n"
    msg+="⏱️  Up: $uptime\n"
    msg+="📊 Load: $load\n"
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    msg+="🧠 HARDWARE\n"
    msg+="🔲 CPU: $cpu_model\n"
    msg+="🔢 Cores: $cpu_cores @ $cpu_mhz MHz\n"
    msg+="💾 RAM: $total_ram ($used_ram used)\n"
    msg+="💿 Swap: $total_swap\n"
    msg+="💽 Disk: $disk_total ($disk_used used)\n"
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    msg+="✅ TEST SUCCESSFUL!\n"
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    echo -e "$msg"
}

INFO=$(collect_info)

echo "$INFO"
echo ""

# ==================== SEND NOTIFICATION ====================
echo "========================================"
echo "SENDING NOTIFICATION"
echo "========================================"
echo ""

case "$EMAIL_METHOD" in
    telegram)
        echo "[*] Sending to Telegram..."
        RESULT=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${INFO}" \
            -d "parse_mode=HTML")
        
        if echo "$RESULT" | grep -q '"ok":true'; then
            echo "[✓] Message sent successfully!"
            echo ""
            echo "Check your Telegram - you should see the report!"
        else
            echo "[!] Failed to send message"
            echo "Error: $RESULT"
        fi
        ;;
    
    discord)
        echo "[*] Sending to Discord..."
        RESULT=$(curl -s -X POST "$DISCORD_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"\`\`\`\n${INFO}\n\`\`\`\"}")
        
        if [ -z "$RESULT" ] || echo "$RESULT" | grep -q "id"; then
            echo "[✓] Message sent successfully!"
            echo ""
            echo "Check your Discord channel - you should see the report!"
        else
            echo "[!] Failed to send message"
            echo "Error: $RESULT"
        fi
        ;;
    
    mailgun)
        echo "[*] Sending email via Mailgun..."
        RESULT=$(curl -s --user "api:$MAILGUN_API_KEY" \
            "https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages" \
            -F from="Test <test@$MAILGUN_DOMAIN>" \
            -F to="$REPORT_EMAIL" \
            -F subject="System Info Test - $(hostname)" \
            -F text="$INFO")
        
        if echo "$RESULT" | grep -q "Queued"; then
            echo "[✓] Email sent successfully!"
            echo ""
            echo "Check your inbox: $REPORT_EMAIL"
        else
            echo "[!] Failed to send email"
            echo "Error: $RESULT"
        fi
        ;;
    
    sendgrid)
        echo "[*] Sending email via SendGrid..."
        RESULT=$(curl -s -X POST "https://api.sendgrid.com/v3/mail/send" \
            -H "Authorization: Bearer $SENDGRID_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"personalizations\": [{\"to\": [{\"email\": \"$REPORT_EMAIL\"}]}],
                \"from\": {\"email\": \"test@example.com\", \"name\": \"System Test\"},
                \"subject\": \"System Info Test\",
                \"content\": [{\"type\": \"text/plain\", \"value\": \"$INFO\"}]
            }")
        
        if [ -z "$RESULT" ]; then
            echo "[✓] Email sent successfully!"
            echo ""
            echo "Check your inbox: $REPORT_EMAIL"
        else
            echo "[!] Failed to send email"
            echo "Error: $RESULT"
        fi
        ;;
    
    local_mail)
        echo "[*] Sending via local mail..."
        if echo "$INFO" | mail -s "System Info Test" "$REPORT_EMAIL" 2>/dev/null; then
            echo "[✓] Email sent successfully!"
            echo ""
            echo "Check your inbox: $REPORT_EMAIL"
        else
            echo "[!] Failed to send email"
            echo "Is mail command configured on this system?"
        fi
        ;;
esac

echo ""
echo "========================================"
echo "TEST COMPLETE"
echo "========================================"
echo ""
echo "If you received the notification, you can now"
echo "integrate this into your setup scripts!"
echo ""
echo "See: NOTIFICATION_SETUP_GUIDE.md for details"
echo ""
