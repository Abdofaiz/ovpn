#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Update system
apt-get update
apt-get upgrade -y

# Install OpenVPN and Easy-RSA
apt-get install -y openvpn easy-rsa

# Set up the Easy-RSA directory
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
./easyrsa init-pki
./easyrsa build-ca nopass

# Generate server certificate and key
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate Diffie-Hellman parameters
./easyrsa gen-dh

# Generate HMAC signature
openvpn --genkey --secret ta.key

# Create server configuration
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
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Configure firewall rules
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables.rules

# Create systemd service
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

echo "OpenVPN installation and configuration complete!"
echo "Server is running on UDP port 53"
echo "To generate client certificates, run:"
echo "cd ~/openvpn-ca"
echo "./easyrsa gen-req client1 nopass"
echo "./easyrsa sign-req client client1" 