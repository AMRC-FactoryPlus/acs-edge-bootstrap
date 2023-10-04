# ACS Cell Gateway bootstrap script
# Install dependencies

if [ "$(id -u)" != 0 ]
then
    echo "Software installation must run as root!" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo Installing Dependencies...
install ./install/kitware.asc /etc/apt/trusted.gpg.d/kitware.asc
install ./install/nodesource.asc /etc/apt/trusted.gpg.d/nodesource.asc
apt-add-repository -ny -S 'deb https://apt.kitware.com/ubuntu/ jammy main'
apt-add-repository -ny -S 'deb https://deb.nodesource.com/node_20.x nodistro main'
apt-get update 

apt-get install -y \
    apt-transport-https ca-certificates gnupg software-properties-common wget

apt-get install -y \
    wireguard g++ iptables-persistent dnsmasq krb5-user \
    cmake libkrb5-dev nodejs jq dialog

bash ./install/helm.sh
bash ./install/flux.sh
