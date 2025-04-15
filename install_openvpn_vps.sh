#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo -e "${GREEN}Starting OpenVPN installation for VPS...${NC}"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update
apt-get upgrade -y

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
apt-get install -y openvpn easy-rsa curl iptables-persistent

# Set up the Easy-RSA directory
echo -e "${YELLOW}Setting up Easy-RSA...${NC}"
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Configure Easy-RSA
cat > vars << EOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "San Francisco"
set_var EASYRSA_REQ_ORG        "OpenVPN"
set_var EASYRSA_REQ_EMAIL      "admin@example.com"
set_var EASYRSA_REQ_OU         "OpenVPN"
set_var EASYRSA_KEY_SIZE       2048
set_var EASYRSA_ALGO           rsa
set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    3650
EOF

# Initialize PKI and build CA
echo -e "${YELLOW}Generating certificates...${NC}"
./easyrsa init-pki
./easyrsa build-ca nopass

# Generate server certificate and key
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate Diffie-Hellman parameters
./easyrsa gen-dh

# Generate HMAC signature
openvpn --genkey --secret ta.key

# Create server configuration directory
echo -e "${YELLOW}Creating server configuration...${NC}"
mkdir -p /etc/openvpn/server
cp pki/ca.crt /etc/openvpn/server/
cp pki/issued/server.crt /etc/openvpn/server/
cp pki/private/server.key /etc/openvpn/server/
cp pki/dh.pem /etc/openvpn/server/
cp ta.key /etc/openvpn/server/

# Create server configuration file
cat > /etc/openvpn/server/server.conf << EOF
port 53
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth ta.key 0
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

# Enable IP forwarding
echo -e "${YELLOW}Configuring network settings...${NC}"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl -p /etc/sysctl.d/99-openvpn.conf

# Configure firewall rules
echo -e "${YELLOW}Setting up firewall rules...${NC}"
cat > /etc/iptables/rules.v4 << EOF
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p udp --dport 53 -j ACCEPT
-A INPUT -p tcp --dport 53 -j ACCEPT
-A INPUT -j DROP
COMMIT
EOF

# Apply iptables rules
iptables-restore < /etc/iptables/rules.v4

# Enable and start OpenVPN service
echo -e "${YELLOW}Starting OpenVPN service...${NC}"
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

# Create client configuration directory
mkdir -p ~/client-configs/files
chmod 700 ~/client-configs/files

# Copy the management script
echo -e "${YELLOW}Setting up management tools...${NC}"
cp ovpn_manager.sh /usr/local/bin/ovpn_manager
chmod +x /usr/local/bin/ovpn_manager

echo -e "${GREEN}OpenVPN installation completed successfully!${NC}"
echo -e "${YELLOW}To manage your OpenVPN server, run:${NC}"
echo "sudo ovpn_manager"
echo
echo -e "${YELLOW}To create your first user, select option 1 from the menu${NC}"
echo -e "${YELLOW}To set up routing, select option 8 from the menu${NC}" 