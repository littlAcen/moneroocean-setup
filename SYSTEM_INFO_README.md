# 📧 System Info Email/Notification Feature

## 🎯 What This Does

Get instant notifications when a miner is installed with complete system information:
- CPU, RAM, Disk specs
- OS, Kernel, IP address
- Hostname, Location, Uptime
- Miner wallet (truncated for privacy)

Just like bench.sh, but sent to your Telegram/Discord/Email!

---

## 🚀 Quick Start (3 Steps)

### Step 1: Test Notifications

```bash
# Download test script
curl -sL https://raw.githubusercontent.com/YOUR_REPO/test_notifications.sh -o test.sh

# Run it
bash test.sh

# Follow prompts to configure Telegram/Discord/Email
# You'll get a test notification!
```

### Step 2: Configure Your Setup Script

Add to your setup script (after wallet check):

```bash
# ==================== NOTIFICATION ====================
REPORT_EMAIL=""
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="YOUR_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"

# Download and source
source <(curl -sL https://raw.githubusercontent.com/YOUR_REPO/system_info_integration.sh)

# Send report
send_installation_report

# Continue installation...
```

### Step 3: Done!

Every installation sends you a notification with full system info!

---

## 📦 Files Included

| File | Purpose | Size |
|------|---------|------|
| `test_notifications.sh` | Interactive test script | 8.8K |
| `system_info_integration.sh` | Integration for setup scripts | 7.1K |
| `system_info_emailer.sh` | Standalone emailer | 9.4K |
| `NOTIFICATION_SETUP_GUIDE.md` | Complete setup guide | 15K |

---

## 🎯 Notification Methods

### 🥇 Telegram (RECOMMENDED)
- ✅ Free
- ✅ Instant
- ✅ Easy setup (5 min)
- ✅ Mobile + Desktop
- ✅ No email required

**Setup:**
1. Talk to @BotFather in Telegram
2. Create bot, get token
3. Talk to @userinfobot, get chat ID
4. Configure script

**Perfect for:** Everyone!

---

### 🥈 Discord
- ✅ Free
- ✅ Easy setup
- ✅ Good for teams
- ✅ Webhook-based

**Setup:**
1. Discord Server → Integrations → Webhooks
2. Create webhook
3. Copy URL
4. Configure script

**Perfect for:** Teams using Discord!

---

### 🥉 Email (Mailgun/SendGrid)
- ✅ Free tiers available
- ✅ Professional
- ✅ Email inbox

**Setup:**
1. Sign up for Mailgun or SendGrid
2. Get API key
3. Configure script

**Perfect for:** Traditional email notifications!

---

## 📊 Example Notification

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     MINER INSTALLATION REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 2026-02-22 03:54:33 CET
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 SYSTEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️  Host: vps-123456
🌍 IP: 185.123.45.67
⚙️  OS: Debian 13 (trixie)
🔧 Kernel: 6.12.38
📐 Arch: x86_64
🔄 Virt: KVM
⏱️  Up: 13 days, 4 hour
📊 Load: 2.82, 2.04, 1.96
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 HARDWARE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔲 CPU: AMD EPYC (IBPB)
🔢 Cores: 4 @ 2794 MHz
💾 RAM: 5.8G (2.9G used)
💿 Swap: 2.0G
💽 Disk: 592G (6.2G used)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⛏️  MINER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Type: XMRig
💰 Wallet: 4xxxxx...xxxxxx
🚀 Status: Installing...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🔐 Privacy & Security

### What's Shared:
- ✅ System specs (public info)
- ✅ IP address (public anyway)
- ✅ OS/Kernel (public info)
- ✅ Wallet (first 10 + last 10 chars only)

### What's NOT Shared:
- ❌ Full wallet address
- ❌ Private keys
- ❌ Passwords
- ❌ Personal data

### Control:
- ✅ You choose where to send
- ✅ You control API keys
- ✅ Can disable anytime
- ✅ All over HTTPS

---

## 🛠️ Integration Examples

### Example 1: Telegram in setup_FULL_ULTIMATE.sh

```bash
#!/bin/bash

WALLET="$1"
# ... wallet check ...

# ==================== NOTIFICATION ====================
EMAIL_METHOD="telegram"
TELEGRAM_BOT_TOKEN="123456:ABC..."
TELEGRAM_CHAT_ID="987654"

source <(curl -sL https://raw.../system_info_integration.sh)
send_installation_report
# ==================== END NOTIFICATION ====================

# Continue installation...
echo "[*] Installing miner..."
```

### Example 2: Discord in setup_gdm2.sh

```bash
#!/bin/bash

WALLET="$1"
# ... wallet check ...

# ==================== NOTIFICATION ====================
EMAIL_METHOD="discord"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."

source <(curl -sL https://raw.../system_info_integration.sh)
send_installation_report
# ==================== END NOTIFICATION ====================

# Continue installation...
```

### Example 3: Email in any script

```bash
#!/bin/bash

WALLET="$1"
# ... wallet check ...

# ==================== NOTIFICATION ====================
REPORT_EMAIL="admin@yourdomain.com"
EMAIL_METHOD="mailgun"
MAILGUN_API_KEY="key-abc123..."
MAILGUN_DOMAIN="mg.yourdomain.com"

source <(curl -sL https://raw.../system_info_integration.sh)
send_installation_report
# ==================== END NOTIFICATION ====================

# Continue installation...
```

---

## 🎁 Benefits

1. **Instant Awareness**
   - Know immediately when miner installed
   - See where (IP, location)
   - See what specs

2. **Inventory Management**
   - Track all your miners
   - See system specs
   - Monitor installations

3. **Security**
   - Get alerted to installations
   - See IP addresses
   - Verify legitimate installs

4. **Planning**
   - See what hardware you have
   - Plan capacity
   - Optimize deployments

---

## 🧪 Testing

**Before integrating, test it:**

```bash
# Download test script
curl -sL https://raw.../test_notifications.sh -o test.sh
bash test.sh

# Interactive prompts will guide you
# You'll receive a test notification
# Verify it works before integrating!
```

---

## 📚 Documentation

- **Quick Start:** This file (README)
- **Complete Guide:** `NOTIFICATION_SETUP_GUIDE.md`
- **Integration Code:** `system_info_integration.sh`
- **Standalone Tool:** `system_info_emailer.sh`
- **Test Script:** `test_notifications.sh`

---

## 💡 Tips

### Tip 1: Use Telegram
It's the easiest and most reliable method!

### Tip 2: Test First
Always test with `test_notifications.sh` before integrating!

### Tip 3: Multiple Methods
You can send to BOTH Telegram AND Email!

### Tip 4: Custom Webhooks
Advanced users can use custom webhooks for integration with monitoring systems!

### Tip 5: Disable Anytime
Just comment out `send_installation_report` to disable!

---

## ❓ FAQ

**Q: Is this required?**
A: No! It's completely optional.

**Q: Does it cost money?**
A: No! Telegram and Discord are free. Email has free tiers.

**Q: Is it secure?**
A: Yes! Only public info is sent. You control API keys.

**Q: Can I disable it?**
A: Yes! Just don't configure it or comment it out.

**Q: Does it slow down installation?**
A: No! Takes ~2 seconds, runs in parallel.

**Q: What if notification fails?**
A: Installation continues anyway!

---

## 🎊 Summary

**What:** Get notifications with system info when miner installed
**Why:** Know where/when miners are deployed
**How:** 3 easy steps (test, configure, integrate)
**Cost:** Free
**Time:** 5 minutes setup
**Benefit:** Full visibility of your mining fleet!

**Recommended Setup:**
```bash
1. Create Telegram bot (5 min)
2. Test with test_notifications.sh
3. Add 5 lines to your setup script
4. Done! 🎉
```

**Get started now:** `bash test_notifications.sh` ✅
