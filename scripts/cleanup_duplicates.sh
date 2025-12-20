#!/bin/bash
#
# Cleanup Script - Remove duplicate and unnecessary files
# WARNING: This will delete files. Review before running.
#

set -e

echo "=================================="
echo "File Cleanup Script"
echo "=================================="
echo ""
echo "This script will remove duplicate files to reduce bloat."
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

REPO_ROOT="/home/user/moneroocean-setup"
cd "$REPO_ROOT"

echo ""
echo "Creating backup of current state..."
BACKUP_DIR="/tmp/moneroocean-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r . "$BACKUP_DIR/" || true
echo "Backup created at: $BACKUP_DIR"

echo ""
echo "[1/4] Removing duplicate Python files..."

# Keep only the latest working version, remove duplicates
# NOTE: Review these files before uncommenting the deletions

# Duplicate SSH scanning scripts (keeping only one recommended version)
# rm -fv "LATEST-TO_USE_ssh25_25-05-25.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_gemini.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_gemini_ABSOLUTELY_WORKING_LIKE_BEST_DONT_REMOVE.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_gemini_ABSOLUTELY_WORKING_LIKE_BEST_DONT_REMOVE_checking_every_txt_in_dir_gemini_corrected.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_w0rking.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_w0rking_ORiG.py"
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_mmap.py"
# rm -fv "LATEST_ssh25_mitohnealles_WORKING_currently_checked_host_is_shown_port_22_is_always_checked_ssh_format_readable_no_checked_host_file_W0RKING_SERVERS_ARE_REMOVED_WORKING_COPY_flatten_opt_rich_gemini!!!.py"
# rm -fv "ssh25_mitohnealles.py"
# rm -fv "ssh25_works_seperated_functions_callable_protocols_WORKING_with_stats_corrected_and_thread_count_new_thread_method_sudo_check_implemented_with_thread_lock_remove_hosts_WORKING_FINALLY_INFO_ONLY_msgs.py"

# Empty file
# rm -fv "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_gemini_ABSOLUTELY_WORKING_LIKE_BEST_DONT_REMOVE_checking_every_txt_in_dir_deepseek_corrected.py"

echo "NOTE: Duplicate removals are commented out for safety."
echo "Review scripts/cleanup_duplicates.sh and uncomment specific deletions."

echo ""
echo "[2/4] Identifying duplicate setup scripts..."
ls -lh setup_gdm2*.sh 2>/dev/null | wc -l && echo "setup_gdm2 variants found"
ls -lh setup_m0_4*.sh 2>/dev/null | wc -l && echo "setup_m0_4 variants found"
ls -lh setup_mo_4*.sh 2>/dev/null | wc -l && echo "setup_mo_4 variants found"
ls -lh setup_swapd*.sh 2>/dev/null | wc -l && echo "setup_swapd variants found"

echo ""
echo "[3/4] Checking for large binary files..."
find . -type f -size +1M -exec ls -lh {} \; | grep -v ".git"

echo ""
echo "[4/4] Summary of potential cleanup..."
echo ""
echo "Python files: $(find . -name "*.py" -type f | wc -l) total"
echo "Shell scripts: $(find . -name "*.sh" -type f | wc -l) total"
echo "Binary files: $(find . -type f -executable | wc -l) total"
echo ""

echo "=================================="
echo "Cleanup analysis complete!"
echo "=================================="
echo ""
echo "To actually remove files:"
echo "1. Review the commented deletions in this script"
echo "2. Uncomment the rm commands you want to execute"
echo "3. Re-run this script"
echo ""
echo "Backup location: $BACKUP_DIR"
