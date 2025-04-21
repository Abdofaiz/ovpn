# OpenVPN Installation Scripts

This repository contains scripts for automatically installing and configuring OpenVPN servers with various options.

## Scripts Included

- `auto_install_openvpn.sh`: Main automatic installation script for OpenVPN on port 53 UDP
- `create_client.sh`: Script to create new OpenVPN client configurations
- `install_openvpn.sh`: Basic OpenVPN installation script
- `install_openvpn_ubuntu.sh`: Ubuntu-specific OpenVPN installation script
- `install_openvpn_vps.sh`: VPS-optimized OpenVPN installation script
- `ovpn_manager.sh`: OpenVPN management script

## Features

- Automatic installation and configuration
- Port 53 UDP support
- Certificate-based authentication
- Automatic client configuration generation
- Firewall configuration
- Systemd service integration

## Usage

1. Clone the repository:
```bash
git clone https://github.com/Abdofaiz/ovpn.git
cd ovpn
```

2. Make the installation script executable:
```bash
chmod +x auto_install_openvpn.sh
```

3. Run the installation script as root:
```bash
sudo ./auto_install_openvpn.sh
```

4. To create new client configurations:
```bash
sudo ./create_client.sh client_name
```

## Requirements

- Ubuntu/Debian-based system
- Root access
- Internet connection

## License

This project is open source and available under the MIT License. 