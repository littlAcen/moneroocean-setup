# 📧 SYSTEM INFO EMAIL REPORT - Complete Guide

## 🎯 Overview

Get an email/notification with system information when the miner is installed!

**Example Report:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        MINER INSTALLATION REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 Timestamp: 2026-02-22 03:54:33 CET
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 SYSTEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️  Hostname: vps-123456
🌍 IPv4: 185.123.45.67
⚙️  OS: Debian GNU/Linux 13 (trixie)
🔧 Kernel: 6.12.38+deb13-cloud-amd64
📐 Arch: x86_64
🔄 Virtualization: KVM
⏱️  Uptime: 13 days, 4 hour 5 min
📊 Load: 2.82, 2.04, 1.96
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 HARDWARE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔲 CPU: AMD EPYC Processor (with IBPB)
🔢 Cores: 4 @ 2794.748 MHz
💾 RAM: 5.8 GB (2.9 GB used)
💿 Swap: 2.0 GB
💽 Disk: 592.5 GB (6.2 GB used)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⛏️  MINER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Type: XMRig
💰 Wallet: 4xxxxx...xxxxxx
🚀 Status: Installing...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🚀 Quick Setup Options

### Option 1: Telegram Bot (RECOMMENDED - Free & Easy!)

**Step 1: Create Bot**
1. Open Telegram and search for `@BotFather`
2. Send `/newbot`
3. Follow instructions, choose a name
4. Copy your **Bot Token** (looks like: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

**Step 2: Get Chat ID**
1. Search for `@userinfobot` in Telegram
2. Send any message
3. Copy your **Chat ID** (looks like: `123456789`)

**Step 3: Configure Script**
```bash
REPORT_EMAIL=""  # Leave empty for Telegram
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="123456789"
```

**Done!** You'll get notifications in Telegram!

---

### Option 2: Discord Webhook (Also Free & Easy!)

**Step 1: Create Webhook**
1. Open Discord Server Settings
2. Go to Integrations → Webhooks
3. Click "New Webhook"
4. Choose channel (e.g., #alerts)
5. Copy **Webhook URL**

**Step 2: Configure Script**
```bash
REPORT_EMAIL=""  # Leave empty for Discord
EMAIL_METHOD="discord"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123456789/abcdefghijklmnop"
```

**Done!** You'll get notifications in Discord!

---

### Option 3: Mailgun Email (Free 5,000 emails/month)

**Step 1: Sign Up**
1. Go to https://www.mailgun.com/
2. Sign up (free tier)
3. Verify your email
4. Add and verify your domain (or use sandbox)

**Step 2: Get API Key**
1. Go to Settings → API Keys
2. Copy your **Private API key**
3. Note your **Domain** (e.g., `sandboxXXX.mailgun.org`)

**Step 3: Configure Script**
```bash
REPORT_EMAIL="your-email@gmail.com"
EMAIL_METHOD="mailgun"
MAILGUN_API_KEY="key-1234567890abcdef"
MAILGUN_DOMAIN="sandboxXXX.mailgun.org"
```

**Done!** You'll get emails!

---

### Option 4: SendGrid Email (Free 100 emails/day)

**Step 1: Sign Up**
1. Go to https://sendgrid.com/
2. Sign up (free tier)
3. Verify your email

**Step 2: Get API Key**
1. Go to Settings → API Keys
2. Create new API key
3. Copy the key

**Step 3: Configure Script**
```bash
REPORT_EMAIL="your-email@gmail.com"
EMAIL_METHOD="sendgrid"
SENDGRID_API_KEY="SG.1234567890abcdef"
```

---

### Option 5: Local Mail (If mail command available)

```bash
REPORT_EMAIL="your-email@gmail.com"
EMAIL_METHOD="local_mail"
```

**Note:** This only works if the server has `mail` or `sendmail` configured!

---

## 📥 Integration into Your Setup Scripts

### Method A: Source the Integration File

**Step 1: Add to beginning of script (after WALLET check)**
```bash
#!/bin/bash

# Get wallet address
WALLET="$1"
if [ -z "$WALLET" ]; then
    echo "Usage: $0 <wallet>"
    exit 1
fi

# ==================== LOAD NOTIFICATION SYSTEM ====================
# Download integration
curl -sL https://raw.githubusercontent.com/YOUR_REPO/system_info_integration.sh -o /tmp/notify.sh

# Configure (choose one method)
REPORT_EMAIL="your@email.com"
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="YOUR_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"

# Source it
source /tmp/notify.sh

# Send report
send_installation_report

# Continue with installation...
echo "[*] Installing miner..."
```

### Method B: Embed Directly in Script

Copy the entire content from `system_info_integration.sh` and paste it at the top of your setup script!

---

## 🧪 Testing

**Test the notification system:**

```bash
# Download test script
curl -sL https://raw.githubusercontent.com/YOUR_REPO/system_info_emailer.sh -o test_notify.sh

# Edit configuration
nano test_notify.sh
# Set your TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID

# Run test
bash test_notify.sh
```

You should receive a notification!

---

## 📋 Configuration Reference

### All Available Options

```bash
# Email/Chat destination
REPORT_EMAIL="your@email.com"  # For email methods only

# Notification method
EMAIL_METHOD="telegram"  # Options: telegram, discord, mailgun, sendgrid, local_mail, webhook

# Telegram (Recommended)
TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="123456789"

# Discord
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."

# Mailgun
MAILGUN_API_KEY="key-abc123..."
MAILGUN_DOMAIN="your-domain.mailgun.org"

# SendGrid
SENDGRID_API_KEY="SG.abc123..."

# Custom Webhook
WEBHOOK_URL="https://your-server.com/api/report"
```

---

## 🎯 What Information is Collected?

- ✅ **System:**
  - Hostname
  - IPv4 address
  - OS & Kernel
  - Architecture
  - Virtualization type
  - Uptime & Load

- ✅ **Hardware:**
  - CPU model & cores
  - RAM total & used
  - Swap total
  - Disk total & used

- ✅ **Miner:**
  - Type (XMRig)
  - Wallet address (truncated for privacy)
  - Installation status

- ❌ **NOT collected:**
  - Passwords
  - Private keys
  - Personal data
  - Full wallet address (only first/last 10 chars)

---

## 🔒 Security & Privacy

### Privacy Features:
- ✅ Wallet address is truncated (only shows first 10 and last 10 characters)
- ✅ No sensitive data collected
- ✅ You control where data is sent
- ✅ Can disable anytime

### Security:
- ✅ API keys stay on YOUR server
- ✅ HTTPS encrypted transmission
- ✅ Optional - can skip entirely

### Disable Notifications:

**Option 1:** Don't configure any method
```bash
REPORT_EMAIL="your-email@example.com"  # Leave as example
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN=""  # Leave empty
```

**Option 2:** Comment out the call
```bash
# send_installation_report  # ← Commented out
```

---

## 📊 Examples

### Example 1: Telegram Notification

**Configuration:**
```bash
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="987654321:XYZabc123..."
TELEGRAM_CHAT_ID="987654321"
```

**Result:**
You get a Telegram message with the full system report!

### Example 2: Discord Notification

**Configuration:**
```bash
EMAIL_METHOD="discord"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc..."
```

**Result:**
You get a Discord message in your chosen channel!

### Example 3: Email via Mailgun

**Configuration:**
```bash
REPORT_EMAIL="admin@yourdomain.com"
EMAIL_METHOD="mailgun"
MAILGUN_API_KEY="key-123..."
MAILGUN_DOMAIN="mg.yourdomain.com"
```

**Result:**
You get an email with the system report!

---

## 🎁 Bonus: Multiple Notifications

Want notifications in BOTH Telegram AND Email?

**Method 1: Modify the send function**
```bash
send_installation_report() {
    local report=$(collect_system_info)
    
    # Send to Telegram
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        send_telegram "$report"
    fi
    
    # AND send to Email
    if [ -n "$MAILGUN_API_KEY" ]; then
        send_mailgun "Miner Report" "$report"
    fi
}
```

**Method 2: Call twice with different configs**
```bash
# Telegram
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="..."
send_installation_report

# Email
EMAIL_METHOD="mailgun"
MAILGUN_API_KEY="..."
send_installation_report
```

---

## 🛠️ Troubleshooting

### Not receiving notifications?

**Check 1: Configuration**
```bash
# Verify your config
echo "Method: $EMAIL_METHOD"
echo "Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "Chat ID: $TELEGRAM_CHAT_ID"
```

**Check 2: Test manually**
```bash
# Test Telegram
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=Test message"
```

**Check 3: Internet connectivity**
```bash
curl -s ifconfig.me
# Should show your IP
```

**Check 4: Script errors**
```bash
bash -x your_script.sh WALLET 2>&1 | grep -A5 "send_installation_report"
```

---

## 📝 Complete Integration Example

```bash
#!/bin/bash
# Complete example of setup script with notifications

# Check wallet
WALLET="$1"
if [ -z "$WALLET" ]; then
    echo "Usage: $0 <WALLET>"
    exit 1
fi

# ==================== NOTIFICATION CONFIGURATION ====================
REPORT_EMAIL=""
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="123456789"

# ==================== LOAD NOTIFICATION SYSTEM ====================
source <(curl -sL https://raw.githubusercontent.com/YOUR_REPO/system_info_integration.sh)

# ==================== SEND INSTALLATION REPORT ====================
send_installation_report

# ==================== CONTINUE WITH INSTALLATION ====================
echo "[*] Installing XMRig..."
# ... rest of your installation script ...
```

---

## 🎊 Summary

**Best Options:**
1. **Telegram** - Free, instant, easy setup ✅
2. **Discord** - Free, good for teams ✅
3. **Mailgun** - Free tier, professional emails
4. **SendGrid** - Free tier, easy setup
5. **Local Mail** - If already configured

**Recommended:** Use Telegram - it's the easiest and most reliable!

**Setup Time:** 5 minutes
**Cost:** Free
**Value:** Know instantly when/where miners are installed! 🎉
