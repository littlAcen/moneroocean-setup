#!/bin/bash

# ==================== CENTOS 6.X EOL REPOSITORY FIX ====================
# Based on: https://www.mark-gilbert.co.uk/fixing-yum-repos-on-centos-6-now-its-eol/
# This fixes yum repositories on CentOS 6.x which is End-of-Life
# Old SSL libraries can't connect to modern HTTPS mirrors

fix_centos6_repos() {
    echo "[*] Detected CentOS 6.x (End-of-Life) - Fixing repositories..."
    
    # Backup original repos
    if [ ! -d /etc/yum.repos.d.backup ]; then
        cp -r /etc/yum.repos.d /etc/yum.repos.d.backup
        echo "[*] Original repos backed up to /etc/yum.repos.d.backup"
    fi
    
    # Create new CentOS-Base.repo pointing to vault
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[C6.10-base]
name=CentOS-6.10 - Base
baseurl=http://vault.centos.org/6.10/os/$basearch/
gpgcheck=0
enabled=1

[C6.10-updates]
name=CentOS-6.10 - Updates
baseurl=http://vault.centos.org/6.10/updates/$basearch/
gpgcheck=0
enabled=1

[C6.10-extras]
name=CentOS-6.10 - Extras
baseurl=http://vault.centos.org/6.10/extras/$basearch/
gpgcheck=0
enabled=1

[C6.10-contrib]
name=CentOS-6.10 - Contrib
baseurl=http://vault.centos.org/6.10/contrib/$basearch/
gpgcheck=0
enabled=0

[C6.10-centosplus]
name=CentOS-6.10 - CentOSPlus
baseurl=http://vault.centos.org/6.10/centosplus/$basearch/
gpgcheck=0
enabled=0
EOF
    
    echo "[✓] CentOS-Base.repo updated to vault.centos.org"
    
    # Create EPEL repo for CentOS 6
    cat > /etc/yum.repos.d/epel.repo << 'EOF'
[epel]
name=EPEL 6 - $basearch
baseurl=http://archives.fedoraproject.org/pub/archive/epel/6/$basearch
enabled=1
gpgcheck=0

[epel-debuginfo]
name=EPEL 6 - $basearch - Debug
baseurl=http://archives.fedoraproject.org/pub/archive/epel/6/$basearch/debug
enabled=0
gpgcheck=0

[epel-source]
name=EPEL 6 - $basearch - Source
baseurl=http://archives.fedoraproject.org/pub/archive/epel/6/SRPMS
enabled=0
gpgcheck=0
EOF
    
    echo "[✓] EPEL repo configured for CentOS 6"
    
    # Disable GPG checks globally (SSL too old to verify signatures)
    if ! grep -q "gpgcheck=0" /etc/yum.conf; then
        echo "gpgcheck=0" >> /etc/yum.conf
        echo "[✓] GPG check disabled in yum.conf"
    fi
    
    # Clean yum cache
    yum clean all 2>/dev/null
    
    # Rebuild cache
    echo "[*] Rebuilding yum cache..."
    yum makecache 2>&1 | grep -v "^Loaded plugins"
    
    # Disable GPG check in all repo files (additional safety)
    sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/*.repo 2>/dev/null
    
    # Try to update (with skip-broken to avoid dependency issues)
    echo "[*] Attempting yum update (may take a while)..."
    yum update -y --skip-broken 2>&1 | tail -20
    
    echo "[✓] CentOS 6 repository fix completed"
}

# ==================== DETECT CENTOS VERSION ====================
detect_and_fix_centos() {
    # Check if this is CentOS
    if [ -f /etc/redhat-release ]; then
        if grep -qi "CentOS release 6" /etc/redhat-release; then
            CENTOS_VERSION=6
            echo "[!] WARNING: CentOS 6.x detected (End-of-Life since 2020)"
            echo "[*] Applying repository fixes for CentOS 6..."
            fix_centos6_repos
            return 0
        elif grep -qi "CentOS Linux release 7" /etc/redhat-release; then
            CENTOS_VERSION=7
            echo "[*] CentOS 7 detected - repositories should work normally"
            return 0
        elif grep -qi "CentOS" /etc/redhat-release; then
            # CentOS 8 or later
            echo "[*] CentOS 8+ detected"
            return 0
        fi
    fi
    return 1
}

# ==================== USAGE EXAMPLE ====================
# Add this at the beginning of your main script, before any yum/curl operations:
#
# detect_and_fix_centos
# if [ $? -eq 0 ] && [ "$CENTOS_VERSION" = "6" ]; then
#     echo "[*] CentOS 6 fixes applied, proceeding with installation..."
# fi

# ==================== PACKAGE MANAGER COMPATIBILITY ====================
# For CentOS 6 vs 7+ compatibility

# Detect init system (sysvinit vs systemd)
detect_init_system() {
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
        SERVICE_CMD="systemctl"
        echo "[*] Init system: systemd"
    else
        INIT_SYSTEM="sysvinit"
        SERVICE_CMD="service"
        echo "[*] Init system: sysvinit (CentOS 6)"
    fi
}

# Service management wrapper
service_start() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl start "$service_name"
    else
        service "$service_name" start
    fi
}

service_stop() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop "$service_name"
    else
        service "$service_name" stop
    fi
}

service_enable() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable "$service_name"
    else
        chkconfig "$service_name" on
    fi
}

service_status() {
    local service_name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl status "$service_name"
    else
        service "$service_name" status
    fi
}

# ==================== COMPLETE INTEGRATION EXAMPLE ====================
# Place this near the top of your main installation script:

main() {
    echo "========================================="
    echo "MONERO MINER INSTALLATION"
    echo "========================================="
    
    # Detect and fix CentOS 6 if needed
    detect_and_fix_centos
    
    # Detect init system
    detect_init_system
    
    # Now safe to use yum/curl
    echo "[*] Installing dependencies..."
    
    if command -v yum >/dev/null 2>&1; then
        yum install -y curl wget git make gcc --skip-broken 2>&1 | tail -10
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl wget git build-essential
    fi
    
    # Rest of your installation script...
}

# Run main function
# main
