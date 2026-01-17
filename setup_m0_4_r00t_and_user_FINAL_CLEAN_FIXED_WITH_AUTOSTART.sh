#!/bin/bash

# ==================== CENTOS 6.X AUTO-FIX (EOL REPOSITORY) ====================
# CentOS 6.x reached End-of-Life in 2020 and has old SSL libraries that can't
# connect to modern HTTPS sites. This fix automatically detects CentOS 6 and
# updates repositories to use vault.centos.org with HTTP instead of HTTPS.
# Based on: https://www.mark-gilbert.co.uk/fixing-yum-repos-on-centos-6-now-its-eol/

if [ -f /etc/redhat-release ] && grep -qi "CentOS release 6" /etc/redhat-release 2>/dev/null; then
    echo "========================================="
    echo "[!] CentOS 6.x DETECTED (END-OF-LIFE)"
    echo "========================================="
    echo "[*] Applying repository fixes for CentOS 6..."
    echo ""
    
    # Backup original repositories
    if [ ! -d /etc/yum.repos.d.backup ]; then
        cp -r /etc/yum.repos.d /etc/yum.repos.d.backup 2>/dev/null
        echo "[✓] Original repos backed up to /etc/yum.repos.d.backup"
    fi
    
    # Create fixed CentOS Base repository pointing to vault
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'CENTOS6_BASE_EOF'
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
CENTOS6_BASE_EOF
    
    echo "[✓] CentOS-Base.repo updated to vault.centos.org"
    
    # Create fixed EPEL repository
    cat > /etc/yum.repos.d/epel.repo << 'CENTOS6_EPEL_EOF'
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
CENTOS6_EPEL_EOF
    
    echo "[✓] EPEL repository configured"
    
    # Disable GPG checking globally (SSL too old to verify signatures)
    if ! grep -q "^gpgcheck=0" /etc/yum.conf 2>/dev/null; then
        echo "gpgcheck=0" >> /etc/yum.conf
        echo "[✓] GPG checking disabled in yum.conf"
    fi
    
    # Disable GPG in all repository files
    sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/*.repo 2>/dev/null
    
    # Clean yum cache
    echo "[*] Cleaning yum cache..."
    yum clean all 2>&1 | tail -3
    
    # Rebuild metadata cache
    echo "[*] Rebuilding yum metadata cache..."
    yum makecache fast 2>&1 | tail -5
    
    # Run system update with skip-broken to avoid dependency issues
    echo "[*] Running yum update (this may take a while)..."
    yum update -y --skip-broken 2>&1 | tail -10
    
    echo ""
    echo "[✓] CentOS 6 repository fixes completed!"
    echo "[*] The script can now download files and install packages"
    echo "========================================="
    echo ""
    
    # Mark that we're on CentOS 6 for later use
    CENTOS6_DETECTED=true
fi

# ==================== 
