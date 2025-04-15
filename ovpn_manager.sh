#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Function to display menu
show_menu() {
    clear
    echo -e "${GREEN}OpenVPN Manager${NC}"
    echo -e "${BLUE}User Management:${NC}"
    echo "1. Add new user"
    echo "2. List all users"
    echo "3. Revoke user"
    echo "4. Show user details"
    echo -e "${BLUE}Server Management:${NC}"
    echo "5. Show server status"
    echo "6. Restart OpenVPN server"
    echo "7. Show server configuration"
    echo "8. Setup routing files"
    echo -e "${BLUE}Configuration:${NC}"
    echo "9. Show download URL for user"
    echo "10. Backup configurations"
    echo "11. Restore configurations"
    echo -e "${BLUE}System:${NC}"
    echo "12. Update OpenVPN"
    echo "13. Exit"
    echo
    read -p "Enter your choice [1-13]: " choice
}

# Function to add new user
add_user() {
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty${NC}"
        return
    fi

    # Check if user already exists
    if [ -f ~/openvpn-ca/pki/issued/$username.crt ]; then
        echo -e "${RED}User $username already exists${NC}"
        return
    fi

    cd ~/openvpn-ca
    ./easyrsa gen-req $username nopass
    ./easyrsa sign-req client $username

    # Create client configuration directory if it doesn't exist
    mkdir -p ~/client-configs/files
    chmod 700 ~/client-configs/files

    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me)

    # Create client configuration file
    cat > ~/client-configs/files/$username.ovpn << EOF
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
$(cat pki/ca.crt)
</ca>
<cert>
$(cat pki/issued/$username.crt)
</cert>
<key>
$(cat pki/private/$username.key)
</key>
<tls-auth>
$(cat ta.key)
</tls-auth>
key-direction 1
EOF

    echo -e "${GREEN}User $username created successfully${NC}"
    echo -e "${YELLOW}Configuration file: ~/client-configs/files/$username.ovpn${NC}"
}

# Function to list all users
list_users() {
    echo -e "${GREEN}List of all users:${NC}"
    cd ~/openvpn-ca
    for cert in pki/issued/*.crt; do
        username=$(basename "$cert" .crt)
        if [ "$username" != "server" ]; then
            echo "- $username"
        fi
    done
}

# Function to show user details
show_user_details() {
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty${NC}"
        return
    fi

    if [ ! -f ~/openvpn-ca/pki/issued/$username.crt ]; then
        echo -e "${RED}User $username does not exist${NC}"
        return
    fi

    echo -e "${GREEN}Details for user $username:${NC}"
    echo -e "${YELLOW}Certificate:${NC} ~/openvpn-ca/pki/issued/$username.crt"
    echo -e "${YELLOW}Key:${NC} ~/openvpn-ca/pki/private/$username.key"
    echo -e "${YELLOW}Configuration:${NC} ~/client-configs/files/$username.ovpn"
    
    # Show certificate expiration date
    echo -e "${YELLOW}Certificate Expiration:${NC}"
    openssl x509 -in ~/openvpn-ca/pki/issued/$username.crt -noout -enddate | cut -d= -f2
}

# Function to revoke user
revoke_user() {
    read -p "Enter username to revoke: " username
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty${NC}"
        return
    fi

    if [ ! -f ~/openvpn-ca/pki/issued/$username.crt ]; then
        echo -e "${RED}User $username does not exist${NC}"
        return
    fi

    cd ~/openvpn-ca
    ./easyrsa revoke $username
    ./easyrsa gen-crl

    # Remove user's configuration file
    rm -f ~/client-configs/files/$username.ovpn

    echo -e "${GREEN}User $username has been revoked${NC}"
}

# Function to show server status
show_server_status() {
    echo -e "${GREEN}OpenVPN Server Status:${NC}"
    systemctl status openvpn-server@server | grep "Active:"
    echo -e "${YELLOW}Connected Clients:${NC}"
    cat /var/log/openvpn/openvpn-status.log 2>/dev/null || echo "No status log found"
}

# Function to restart OpenVPN server
restart_server() {
    echo -e "${YELLOW}Restarting OpenVPN server...${NC}"
    systemctl restart openvpn-server@server
    echo -e "${GREEN}OpenVPN server restarted${NC}"
}

# Function to show server configuration
show_server_config() {
    echo -e "${GREEN}Server Configuration:${NC}"
    cat /etc/openvpn/server/server.conf
}

# Function to show download URL
show_download_url() {
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty${NC}"
        return
    fi

    if [ ! -f ~/client-configs/files/$username.ovpn ]; then
        echo -e "${RED}Configuration file for $username not found${NC}"
        return
    fi

    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me)
    
    echo -e "${GREEN}Download URL for $username:${NC}"
    echo -e "${YELLOW}http://$SERVER_IP:8000/$username.ovpn${NC}"
    echo
    echo -e "${YELLOW}To start the download server, run:${NC}"
    echo "cd ~/client-configs/files && python3 -m http.server 8000"
}

# Function to backup configurations
backup_configs() {
    BACKUP_DIR="openvpn_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    echo -e "${YELLOW}Creating backup...${NC}"
    cp -r ~/openvpn-ca $BACKUP_DIR/
    cp -r ~/client-configs $BACKUP_DIR/
    cp /etc/openvpn/server/server.conf $BACKUP_DIR/
    
    # Create a tar archive
    tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
    rm -rf $BACKUP_DIR
    
    echo -e "${GREEN}Backup created: $BACKUP_DIR.tar.gz${NC}"
}

# Function to restore configurations
restore_configs() {
    read -p "Enter backup file path: " backup_file
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Backup file not found${NC}"
        return
    fi

    echo -e "${YELLOW}Restoring from backup...${NC}"
    tar -xzf "$backup_file" -C /
    echo -e "${GREEN}Backup restored${NC}"
}

# Function to update OpenVPN
update_openvpn() {
    echo -e "${YELLOW}Updating OpenVPN...${NC}"
    apt-get update
    apt-get upgrade -y openvpn easy-rsa
    echo -e "${GREEN}OpenVPN updated${NC}"
}

# Function to setup routing files
setup_routing() {
    echo -e "${YELLOW}Setting up routing files...${NC}"
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
    sysctl -p /etc/sysctl.d/99-openvpn.conf
    
    # Create iptables rules
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

    # Create iptables rules for IPv6
    cat > /etc/iptables/rules.v6 << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmpv6 -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -j DROP
COMMIT
EOF

    # Apply iptables rules
    iptables-restore < /etc/iptables/rules.v4
    ip6tables-restore < /etc/iptables/rules.v6

    # Create systemd service for iptables
    cat > /etc/systemd/system/iptables.service << EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
ExecStart=/sbin/ip6tables-restore /etc/iptables/rules.v6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start iptables service
    systemctl enable iptables
    systemctl start iptables

    echo -e "${GREEN}Routing files setup completed${NC}"
    echo -e "${YELLOW}IP forwarding enabled${NC}"
    echo -e "${YELLOW}Firewall rules configured${NC}"
    echo -e "${YELLOW}Iptables service enabled${NC}"
}

# Main menu loop
while true; do
    show_menu
    case $choice in
        1)
            add_user
            ;;
        2)
            list_users
            ;;
        3)
            revoke_user
            ;;
        4)
            show_user_details
            ;;
        5)
            show_server_status
            ;;
        6)
            restart_server
            ;;
        7)
            show_server_config
            ;;
        8)
            setup_routing
            ;;
        9)
            show_download_url
            ;;
        10)
            backup_configs
            ;;
        11)
            restore_configs
            ;;
        12)
            update_openvpn
            ;;
        13)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    read -p "Press Enter to continue..."
done 