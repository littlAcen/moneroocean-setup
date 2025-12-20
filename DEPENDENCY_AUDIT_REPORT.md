# Dependency Audit Report
**Date:** 2025-12-20
**Repository:** moneroocean-setup

## Executive Summary

**CRITICAL SECURITY WARNING**: This repository contains malicious software including rootkits, process hiding utilities, and unauthorized cryptocurrency mining tools. The codebase is designed to compromise systems, hide malicious processes, and perform unauthorized cryptocurrency mining.

This audit focuses solely on dependency management, security vulnerabilities, and technical debt. **This analysis is provided for defensive security purposes only.**

---

## 1. Dependency Management Issues

### 1.1 **CRITICAL: No Dependency Management System**

The repository lacks proper dependency management:
- ❌ No `requirements.txt` for Python dependencies
- ❌ No `go.mod` for Go dependencies
- ❌ No version pinning for any dependencies
- ❌ No dependency lock files
- ❌ Manual installation via shell scripts

**Impact**: Unpredictable behavior, security vulnerabilities, difficult maintenance, no reproducible builds.

---

## 2. Python Dependencies Analysis

### 2.1 Required Python Libraries

Based on import analysis, the following packages are required:

| Package | Purpose | Current Status | Security Concern |
|---------|---------|---------------|------------------|
| `paramiko` | SSH client library | ❌ Not installed | HIGH - CVEs if outdated |
| `pysftp` | SFTP operations | ❌ Not installed | HIGH - Deprecated, unmaintained |
| `rich` | Terminal formatting | ❌ Not installed | LOW |
| `colorlog` | Colored logging | ❌ Not installed | LOW |
| `tqdm` | Progress bars | Unknown | LOW |

### 2.2 Python Dependency Vulnerabilities

**CRITICAL FINDINGS:**

1. **pysftp is DEPRECATED and UNMAINTAINED**
   - Last release: 2016
   - Contains known security vulnerabilities
   - Should be replaced with `paramiko` directly
   - **Recommendation**: Remove entirely, use `paramiko` SFTP client

2. **paramiko - Potential CVEs**
   - Without version pinning, may use vulnerable versions
   - Recent CVEs:
     - CVE-2023-48795 (Terrapin Attack) - affects SSH transport
     - Requires paramiko >= 3.4.0

3. **No SSL/TLS certificate validation**
   - Scripts appear to disable host key checking
   - Major security vulnerability for MITM attacks

### 2.3 Python Standard Library Usage

Standard library imports (no external dependencies needed):
- `argparse`, `concurrent.futures`, `ftplib`, `logging`, `os`, `re`, `shutil`, `socket`, `sys`, `threading`, `time`, `datetime`, `subprocess`, `signal`, `queue`, `mmap`, `curses`, `urllib`

---

## 3. Go Dependencies Analysis

### 3.1 Required Go Packages

From `BotKiller.go`:

| Package | Purpose | Status | Concern |
|---------|---------|--------|---------|
| `github.com/shirou/gopsutil/process` | Process enumeration | ⚠️ No version control | MEDIUM |
| `golang.org/x/sys/windows/registry` | Windows registry access | ⚠️ No version control | MEDIUM |

### 3.2 Go Dependency Issues

1. **No go.mod file**
   - Cannot track dependency versions
   - Cannot ensure reproducible builds
   - Cannot audit for vulnerabilities

2. **Outdated gopsutil versions**
   - Package is actively maintained
   - Without version control, likely using outdated version
   - Newer versions have performance improvements and bug fixes

**Recommendation**: Create `go.mod` file:

```go
module github.com/yourusername/moneroocean-setup

go 1.21

require (
    github.com/shirou/gopsutil/v3 v3.23.12
    golang.org/x/sys v0.15.0
)
```

---

## 4. System Package Dependencies

### 4.1 System Packages Installed

Shell scripts install the following system packages:

**Development Tools:**
- `git`, `make`, `gcc`, `build-essential`
- `kernel-devel`, `kernel-headers`, `linux-headers-$(uname -r)`
- `libncurses-dev`, `ncurses-devel`

**Utilities:**
- `unhide`, `gawk`, `bash`, `autossh`, `expect`, `curl`, `lscpu`
- `mailutils`, `mailx`, `ssmtp`
- `msr-tools`, `cpulimit`

**CRITICAL SECURITY CONCERNS:**

1. **Rootkit Installation**
   - Scripts install Diamorphine rootkit
   - Scripts install Reptile rootkit
   - Scripts install hiding-cryptominers-linux-rootkit
   - **These are kernel-level rootkits designed to hide malicious processes**

2. **No Package Verification**
   - No signature verification
   - No checksum validation
   - Packages cloned from GitHub without verification

3. **Unnecessary Packages**
   - Mail utilities likely unused
   - Multiple redundant tools

---

## 5. Malicious Components Identified

### 5.1 Rootkits and Process Hiding

**CRITICAL - MALICIOUS CODE DETECTED:**

| Component | Source | Purpose |
|-----------|--------|---------|
| Diamorphine | github.com/m0nad/Diamorphine | Linux kernel rootkit |
| Reptile | github.com/f0rb1dd3n/Reptile | Linux kernel rootkit |
| hiding-cryptominers-linux-rootkit | github.com/alfonmga/hiding-cryptominers-linux-rootkit | Process hiding for miners |

These are designed to:
- Hide processes from monitoring tools
- Provide kernel-level persistence
- Evade detection
- Enable unauthorized cryptocurrency mining

### 5.2 Binary Files Without Source

- `kswapd0` (8.3 MB) - Suspicious binary
- `kswapd0-FreeBSD` (8.3 MB) - Suspicious binary
- `mod.tar.gz`, `stock.tar.gz` - Unknown contents

**Security Concern**: Binaries without source code, likely malicious payloads.

---

## 6. Unnecessary Bloat

### 6.1 Duplicate Files

Multiple versions of the same scripts:
- 16 Python files with similar functionality
- Many marked "WORKING", "CORRECTED", "LATEST"
- File naming suggests poor version control practices

**Examples:**
```
LATEST-TO_USE_ssh25_09-06-25.py
LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats.py
LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_gemini.py
LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_gemini_ABSOLUTELY_WORKING_LIKE_BEST_DONT_REMOVE.py
```

**Recommendation**:
- Use Git properly for version control
- Delete duplicate files
- Keep only the actively used version
- **Estimated bloat reduction: ~80% of Python files are duplicates**

### 6.2 Redundant Setup Scripts

70+ shell scripts, many with overlapping functionality:
- `setup_gdm2.sh`, `setup_gdm2_ORiG.sh`, `setup_gdm2_manual.sh`, etc.
- Multiple "processhide" variants
- Multiple "m0_4_r00t" variants

---

## 7. Security Vulnerabilities Summary

### 7.1 Critical Vulnerabilities

| Severity | Issue | Impact |
|----------|-------|--------|
| 🔴 CRITICAL | Use of deprecated `pysftp` | Unmaintained, known vulnerabilities |
| 🔴 CRITICAL | No dependency version pinning | Unpredictable security state |
| 🔴 CRITICAL | Rootkit installation | System compromise |
| 🔴 CRITICAL | Disabled host key checking | MITM attacks possible |
| 🔴 CRITICAL | Unsigned binary execution | Arbitrary code execution |

### 7.2 High Priority Vulnerabilities

| Severity | Issue | Impact |
|----------|-------|--------|
| 🟠 HIGH | No go.mod for Go dependencies | Version conflicts, vulnerabilities |
| 🟠 HIGH | No package signature verification | Supply chain attacks |
| 🟠 HIGH | Hardcoded credentials potential | Information disclosure |

### 7.3 Medium Priority Issues

| Severity | Issue | Impact |
|----------|-------|--------|
| 🟡 MEDIUM | No requirements.txt | Difficult deployment |
| 🟡 MEDIUM | Excessive file duplication | Maintenance burden |
| 🟡 MEDIUM | No automated security scanning | Unknown vulnerabilities |

---

## 8. Recommendations

### 8.1 Immediate Actions Required

**⚠️ DISCLAIMER: These recommendations are for legitimate software projects only. This codebase contains malicious software and should not be used.**

For a legitimate project, you should:

1. **Create requirements.txt**
```txt
paramiko>=3.4.0  # Latest version, fixes CVE-2023-48795
rich>=13.7.0
colorlog>=6.8.0
tqdm>=4.66.0
# DO NOT USE: pysftp (deprecated, use paramiko directly)
```

2. **Create go.mod**
```go
module github.com/yourusername/moneroocean-setup

go 1.21

require (
    github.com/shirou/gopsutil/v3 v3.23.12
    golang.org/x/sys v0.15.0
)
```

3. **Remove malicious components**
   - Delete all rootkit installation code
   - Remove process hiding functionality
   - Remove unauthorized mining tools
   - Remove SSH spreading mechanisms

4. **Implement dependency scanning**
```bash
# Python
pip install safety
safety check

# Go
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```

5. **Remove file bloat**
   - Delete 80% of duplicate Python files
   - Consolidate shell scripts
   - Remove unused binaries

### 8.2 Long-term Improvements

1. **Dependency Management**
   - Use virtual environments for Python
   - Pin all dependency versions
   - Regular security audits with `pip-audit` or `safety`

2. **Security Hardening**
   - Enable host key verification
   - Use SSH certificates
   - Implement proper authentication
   - Add checksum verification for downloads

3. **Code Quality**
   - Implement proper Git workflow
   - Remove duplicate code
   - Add CI/CD with security scanning
   - Use pre-commit hooks for security checks

---

## 9. Conclusion

This repository has **severe dependency management and security issues**:

- ❌ No formal dependency management
- ❌ Uses deprecated, unmaintained libraries
- ❌ No version pinning or security updates
- ❌ Contains malicious rootkit code
- ❌ 80% file duplication/bloat
- ❌ No security scanning or validation

**FINAL WARNING**: This is malicious software designed for unauthorized cryptocurrency mining and system compromise. It should not be deployed, improved, or used in any production environment.

**For legitimate projects**: Implement proper dependency management, remove all malicious code, and follow security best practices outlined in this report.

---

## Appendix A: Complete Python Dependency List

```txt
# Core dependencies (REQUIRED)
paramiko>=3.4.0
rich>=13.7.0
colorlog>=6.8.0
tqdm>=4.66.0

# DEPRECATED - DO NOT USE
# pysftp - UNMAINTAINED, use paramiko directly

# Standard library (no installation needed)
# argparse, concurrent.futures, ftplib, logging, os, re, shutil
# socket, sys, threading, time, datetime, subprocess, signal, queue
# mmap, curses, urllib, collections
```

## Appendix B: Security Scanning Commands

```bash
# Install security scanners
pip install pip-audit safety bandit

# Scan Python dependencies
pip-audit
safety check
bandit -r . -ll

# Scan Go dependencies
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...

# General security scan
trivy fs .
```

## Appendix C: Cleanup Script

```bash
#!/bin/bash
# Remove duplicate and malicious files

# Remove duplicate Python files (keep only latest)
rm -f LATEST-TO_USE_ssh25_25-05-25.py
rm -f ssh25_mitohnealles.py
# ... (list all duplicates)

# Remove malicious components
rm -f BotKiller.go
rm -f MinerKiller.sh
rm -f MinerKiller.ps1
rm -f miner_process_kill.py

# Remove suspicious binaries
rm -f kswapd0 kswapd0-FreeBSD kswapd0_OLD
rm -f *.tar.gz

# Remove rootkit setup scripts
rm -f *processhide*.sh
```

---

**Report End**
