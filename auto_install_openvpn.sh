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

echo -e "${GREEN}Starting automatic OpenVPN installation...${NC}"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update
apt-get upgrade -y

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
apt-get install -y openvpn easy-rsa curl iptables-persistent net-tools

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
-A POSTROUTING -s 10.8.0.0/24 -o $(ip route get 8.8.8.8 | awk '{print $5}') -j MASQUERADE
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

# Create systemd service for iptables
cat > /etc/systemd/system/iptables.service << EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start iptables service
systemctl enable iptables
systemctl start iptables

# Enable and start OpenVPN service
echo -e "${YELLOW}Starting OpenVPN service...${NC}"
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

# Create client configuration directory
mkdir -p ~/client-configs/files
chmod 700 ~/client-configs/files

# Create client creation script
cat > create_client.sh << 'EOF'
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <client_name>"
    exit 1
fi

CLIENT_NAME=$1
cd ~/openvpn-ca

# Generate client certificate and key
./easyrsa gen-req $CLIENT_NAME nopass
./easyrsa sign-req client $CLIENT_NAME

# Create client configuration directory if it doesn't exist
mkdir -p ~/client-configs/files
chmod 700 ~/client-configs/files

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || wget -qO- ifconfig.me)

# Create client configuration file with proper certificate formatting
cat > ~/client-configs/files/$CLIENT_NAME.ovpn << EOF
client
dev tun
proto udp
remote $SERVER_IP 53
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3

<ca>
$(cat ~/openvpn-ca/pki/ca.crt)
</ca>

<cert>
$(cat ~/openvpn-ca/pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat ~/openvpn-ca/pki/private/$CLIENT_NAME.key)
</key>

<tls-auth>
$(cat ~/openvpn-ca/ta.key)
</tls-auth>
key-direction 1
EOF

echo "Client configuration created: ~/client-configs/files/$CLIENT_NAME.ovpn"
EOF

chmod +x create_client.sh

# Create first client automatically
echo -e "${YELLOW}Creating default client...${NC}"
./create_client.sh client1

echo -e "${GREEN}OpenVPN installation completed successfully!${NC}"
echo -e "${YELLOW}Your client configuration is at:${NC}"
echo "~/client-configs/files/client1.ovpn"
echo
echo -e "${YELLOW}To create additional clients, run:${NC}"
echo "sudo ./create_client.sh client_name"
echo
echo -e "${YELLOW}To check OpenVPN status, run:${NC}"
echo "systemctl status openvpn-server@server" 