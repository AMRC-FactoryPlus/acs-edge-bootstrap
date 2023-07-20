# ACS Cell Gateway bootstrap script
# Networking setup

if [ "$(id -u)" != 0 ]
then
    echo "Networking setup must run as root!" >&2
    exit 1
fi

# Run `ip -br l` command and store the list of available interfaces in a variable
interfaces=$(ip -br l)

# Parse the output to extract interface name, status, and MAC address
options=()
while read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  status=$(echo "$line" | awk '{print $3}')
  mac=$(echo "$line" | awk '{print $2}')
  options+=("$name" "$status - $mac")
done <<< "$interfaces"


# Northbound interface
ENN=$(dialog --menu "Select the NORTHBOUND interface:" 0 0 0 "${options[@]}" 2>&1 >/dev/tty)

# Southbound interface
ENS=$(dialog --menu "Select the SOUTHBOUND interface:" 0 0 0 "${options[@]}" 2>&1 >/dev/tty)

# Cluster interface
ENC=$(dialog --menu "Select the CLUSTER interface:" 0 0 0 "${options[@]}" 2>&1 >/dev/tty)

# Quit if any of the interfaces are not selected
if [ -z "$ENN" ] || [ -z "$ENS" ] || [ -z "$ENC" ]
then
    echo "You must select all interfaces!" >&2
    exit 1
fi

# Clear the screen
clear

echo Northbound: $ENN
echo Southbound: $ENS
echo Cluster: $ENC

# Serial number
SERIAL=$(dmidecode -s system-serial-number | tr [:upper:] [:lower:])
echo Setting hostname...
hostnamectl set-hostname fpcgw-${SERIAL}
echo $(hostname)

echo Configuring network...

echo Setting iptables...
# Allow all incoming connections
iptables -P INPUT ACCEPT
# Allow all outgoing connections
iptables -P OUTPUT ACCEPT
# Block all forwarded connections
iptables -P FORWARD DROP
# Flush existing firewall rules
iptables -F
# Allow established and related inbound connections on all interfaces
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Allow SSH access on all interfaces
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# Allow K8s API access on all interfaces
iptables -A INPUT -p tcp --dport 6443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# Block all other incoming requests on the northbound interface
iptables -A INPUT -i $ENN -j DROP
# Save and persist
netfilter-persistent save
iptables-legacy-save

echo Configuring dnsmasq on the 10.0.0.1 interface...
echo -e $"interface=$ENC\nbind-interfaces\nno-hosts\ndhcp-range=10.0.0.2,10.0.0.150,12h" >"/etc/dnsmasq.conf"
systemctl restart dnsmasq

echo Writing netplan config...

# Backup the netplan directory
cp -r /etc/netplan ./netplan.bak
echo "Backed up existing netplan config to ./netplan.bak"

# Delete all files in the netplan directory
rm /etc/netplan/*.yaml

printf "network:
  version: 2
  renderer: networkd
  ethernets:
    $ENN:
      dhcp4: true
      critical: true
    $ENS:
      optional: true
      addresses:
        - 192.168.1.100/24
    $ENC:
      ignore-carrier: true
      addresses:
        - 10.0.0.1/24
" >/etc/netplan/99_config.yaml
netplan apply

echo Having a nap whilst the network comes back up...
sleep 10

