#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 <client_name>"
    exit 1
fi

CLIENT_NAME=$1
cd ~/openvpn-ca

# Generate client certificate and key
./easyrsa gen-req $CLIENT_NAME nopass
./easyrsa sign-req client $CLIENT_NAME

# Create client configuration directory
mkdir -p ~/client-configs/files
chmod 700 ~/client-configs/files

# Create client configuration file
cat > ~/client-configs/files/$CLIENT_NAME.ovpn << EOF
client
dev tun
proto udp
remote YOUR_SERVER_IP 53
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
<ca>
$(cat pki/ca.crt)
</ca>
<cert>
$(cat pki/issued/$CLIENT_NAME.crt)
</cert>
<key>
$(cat pki/private/$CLIENT_NAME.key)
</key>
<tls-auth>
$(cat ta.key)
</tls-auth>
key-direction 1
EOF

echo "Client configuration file created: ~/client-configs/files/$CLIENT_NAME.ovpn"
echo "Please replace YOUR_SERVER_IP with your actual server IP address" 