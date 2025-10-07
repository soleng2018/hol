# SA Demo Kit - Dynamic WAN Configuration

## Overview

The **SA Demo Kit** contains scripts for setting up and managing dynamic WAN configurations with support for 1, 2, or 4 uplink interfaces. This demo kit provides automated network configuration using FRR (Free Range Routing), DHCP, and RADIUS services running in Docker containers.

## Prerequisites

### System Requirements
- **Operating System**: Ubuntu 24.04.3 LTS 
- **Network Interfaces**: 1-4 physical network interfaces for uplinks
- **Memory**: Minimum 2GB RAM (4GB+ recommended)
- **Network**: Internet connection for downloading packages and Docker images

### Required Packages
The setup script will automatically install these dependencies:

```bash
# Core system packages
sudo apt-get update
sudo apt-get install -y python3 python3-yaml

# Docker (if not already installed)
# The script will check and install Docker if needed

# Network management tools
sudo apt-get install -y iproute2 netplan.io

# Additional tools for container management
sudo apt-get install -y isc-dhcp-server freeradius-utils
```

## Files Included

- **`dynamic_wan_setup.sh`** - Main setup script for configuring dynamic WAN
- **`dynamic_wan_cleanup.sh`** - Cleanup script to remove all configurations
- **`parameters.txt`** - Configuration file for interface settings

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/soleng2018/hol.git
cd hol/SA\ Demo\ Kit/v6_dynamic_wan
```

### 2. Make Scripts Executable
```bash
chmod +x *.sh
```

### 3. Configure Parameters
Edit `parameters.txt` to match your network setup:

```bash
nano parameters.txt
```

**Example Configuration for Single Uplink:**
```bash
uplink1_interface="eth0"
uplink1_lan_ip="172.16.0.1/30"
uplink1_lan_subnet="172.16.0.0/30"

# Leave other uplinks empty
uplink2_interface=""
uplink2_lan_ip=""
uplink2_lan_subnet=""
```

**Example Configuration for Dual Uplink:**
```bash
uplink1_interface="enp2s0"
uplink1_lan_ip="172.16.0.1/30"
uplink1_lan_subnet="172.16.0.0/30"

uplink2_interface="enp5s0"
uplink2_lan_ip="172.16.1.1/30"
uplink2_lan_subnet="172.16.1.0/30"

# Leave uplink3/4 empty
uplink3_interface=""
uplink3_lan_ip=""
uplink3_lan_subnet=""
```

### 4. Run Setup
```bash
sudo ./dynamic_wan_setup.sh
```

### 5. Cleanup (when done)
```bash
sudo ./dynamic_wan_cleanup.sh
```

## What the Setup Script Does

### 1. **Dependency Installation**
- Installs Python3 and PyYAML for configuration management
- Installs Docker if not present
- Installs network management tools

### 2. **Network Configuration**
- Configures netplan for specified interfaces
- Sets up static IP addresses on uplink interfaces
- Applies network configuration changes

### 3. **Docker Container Deployment**
- **FRR Container** (`frr_dyn`): Provides OSPF routing for dynamic WAN
- **DHCP Container** (`dhcpd_dyn`): Handles DHCP services
- **RADIUS Container** (`radiusd_dyn`): Provides authentication services

### 4. **Configuration Files Generated**
- `frr_dyn.conf`: FRR routing configuration
- `daemons`: FRR daemon configuration
- `dhcpd.conf`: DHCP server configuration
- Various RADIUS configuration files

## Configuration Options

### Supported Uplink Configurations
- **Single Uplink**: Configure only `uplink1_*` parameters
- **Dual Uplink**: Configure `uplink1_*` and `uplink2_*` parameters  
- **Quad Uplink**: Configure all four uplink parameters

### Interface Naming
Common interface names include:
- `eth0`, `eth1`, `eth2`, `eth3`
- `enp2s0`, `enp5s0`, `enp6s0`, `enp7s0`
- `eno1`, `eno2`, `eno3`, `eno4`

### IP Address Requirements
- Each uplink needs a unique `/30` subnet
- Gateway IP should be `.1` in each subnet
- Example: `172.16.0.1/30` with subnet `172.16.0.0/30`

## Troubleshooting

### Common Issues

**1. Interface Not Found**
```bash
# Check available interfaces
ip link show
# or
ls /sys/class/net/
```

**2. Docker Not Running**
```bash
# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker
```

**3. Netplan Configuration Issues**
```bash
# Check netplan status
sudo netplan status
# Apply netplan manually
sudo netplan apply
```

**4. Container Issues**
```bash
# Check running containers
docker ps -a
# Check container logs
docker logs frr_dyn
docker logs dhcpd_dyn
docker logs radiusd_dyn
```

### Rollback on Failure
The setup script includes automatic rollback functionality. If setup fails:
1. The script will attempt to undo netplan changes
2. Remove any created containers
3. Clean up configuration files

## Cleanup Process

The cleanup script (`dynamic_wan_cleanup.sh`) will:
1. Stop and remove all Docker containers
2. Remove interfaces from netplan configuration
3. Apply netplan changes
4. Clean up configuration files
5. Preserve Docker images for future use

## Security Notes

- Scripts require `sudo` privileges for network configuration
- Docker containers run with `--privileged` mode for network access
- All network changes are logged for audit purposes
- State files are created in `/etc/dynamicwan_configured_interfaces.conf`

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review container logs for specific errors
3. Ensure all prerequisites are met
4. Verify interface names and IP configurations

## Version Information

- **Script Version**: v6_dynamic_wan
- **Compatible OS**: Ubuntu 18.04+
- **Docker Images**: FRR, FreeRADIUS, Custom DHCP
- **Last Updated**: 2025

---

**⚠️ Important**: Always run the cleanup script when finished with the demo to restore your system to its original network configuration.
