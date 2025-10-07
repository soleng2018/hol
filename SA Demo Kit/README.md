# SA Demo Kit - Dynamic WAN Configuration

## Overview

🚀The **SA Demo Kit** contains scripts for setting up and managing dynamic WAN configurations with support for 1, 2, or 4 uplink interfaces. This demo kit provides automated network configuration using FRR (Free Range Routing), DHCP, and RADIUS services running in Docker containers.

** It will automatically installs all required packages and dependencies, making it perfect for fresh employees with no Linux/networking experience!

## Prerequisites

### System Requirements
- **Operating System**: 24.04.3 LTS
- **Network Interfaces**: 1-4 physical network interfaces for uplinks
- **Memory**: Minimum 2GB RAM (4GB+ recommended)
- **Network**: Internet connection for downloading packages and Docker images
- **Access**: Sudo privileges (script will prompt for password)

### Automatic Package Installation
The setup script will **automatically install** all required dependencies:

#### Core System Packages
- `git` - Version control
- `openssh-server` - SSH server
- `net-tools` - Network utilities (ifconfig, netstat, etc.)
- `iproute2` - Modern network tools (ip command)
- `netplan.io` - Network configuration management
- `curl`, `wget` - Download utilities
- `iptables`, `iptables-persistent` - Firewall management

#### Python Dependencies
- `python3` - Python interpreter
- `python3-yaml` - YAML configuration processing

#### Docker & Container Tools
- `docker-ce` - Docker Community Edition
- `docker-ce-cli` - Docker command line interface
- `containerd.io` - Container runtime
- `docker-buildx-plugin` - Extended build capabilities
- `docker-compose-plugin` - Container orchestration

#### Network Services
- `isc-dhcp-server` - DHCP server
- `freeradius-utils` - RADIUS authentication utilities

**✅ No Manual Installation Required** - The script handles everything automatically!

## Files Included

- **`dynamic_wan_setup.sh`** - Enhanced setup script with automatic package installation
- **`dynamic_wan_cleanup.sh`** - Safe cleanup script (removes only configurations)
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

### 4. Run Setup (Fully Automated!)
```bash
sudo ./dynamic_wan_setup.sh
```

**The script will automatically:**
- ✅ Check and install all required packages
- ✅ Install Docker if not present
- ✅ Configure network interfaces
- ✅ Deploy Docker containers
- ✅ Set up routing and services

### 5. Cleanup (when done)
```bash
sudo ./dynamic_wan_cleanup.sh
```

## What the Enhanced Setup Script Does

### 1. **Comprehensive Dependency Check & Installation**
- **System Packages**: git, openssh-server, net-tools, iproute2, netplan.io, curl, wget, iptables
- **Python Environment**: python3, python3-yaml
- **Docker Installation**: Full Docker CE with official repository setup
- **Network Services**: isc-dhcp-server, freeradius-utils
- **Netplan Verification**: Creates basic configuration if none exists

### 2. **Robust Error Handling & Rollback**
- **Automatic Rollback**: Reverts all changes if setup fails
- **Docker Permissions**: Handles user group membership gracefully
- **Interface Validation**: Verifies all specified interfaces exist
- **Configuration Backup**: Creates state files for safe cleanup

### 3. **Network Configuration**
- **Dynamic Interface Setup**: Supports 1, 2, or 4 uplink interfaces
- **Netplan Management**: Automated YAML configuration updates
- **IP Address Assignment**: Static IP configuration for each uplink
- **NAT & Routing**: Automatic IP forwarding and NAT rules

### 4. **Docker Container Deployment**
- **FRR Container** (`frr_dyn`): OSPF routing for dynamic WAN
- **DHCP Container** (`dhcpd_dyn`): DHCP services for each subnet
- **RADIUS Container** (`radiusd_dyn`): Authentication services
- **Custom Images**: Builds optimized container images

### 5. **Configuration Files Generated**
- `frr_dyn.conf`: Dynamic FRR routing configuration
- `daemons`: FRR daemon configuration
- `dhcpd.conf`: DHCP server configuration for all subnets
- `clients.conf`, `authorize`: RADIUS authentication files
- State tracking files for safe cleanup

## New Features & Improvements

### 🚀 **Fully Automated Installation**
- **Zero Manual Setup**: All packages installed automatically
- **Fresh Employee Ready**: No Linux/networking knowledge required
- **Progress Indicators**: Clear status messages throughout installation

### 🛡️ **Enhanced Error Handling**
- **Rollback Protection**: Automatic cleanup on failure
- **Dependency Validation**: Checks all requirements before proceeding
- **Graceful Failures**: Clear error messages and recovery instructions

### 🔧 **Improved Docker Management**
- **Official Repository**: Uses Docker's official Ubuntu repository
- **Permission Handling**: Automatic user group management
- **Sudo Compatibility**: Works with or without Docker group membership

### 📋 **Better Configuration Management**
- **Netplan Verification**: Creates basic config if missing
- **State Tracking**: Records all changes for safe cleanup
- **Interface Validation**: Verifies interfaces before configuration

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
sudo docker ps -a
# Check container logs
sudo docker logs frr_dyn
sudo docker logs dhcpd_dyn
sudo docker logs radiusd_dyn
```

### Rollback on Failure
The setup script includes automatic rollback functionality. If setup fails:
1. The script will attempt to undo netplan changes
2. Remove any created containers
3. Clean up configuration files
4. Restore system to original state

## Cleanup Process

The cleanup script (`dynamic_wan_cleanup.sh`) will:
1. **Stop and remove Docker containers** (frr_dyn, dhcpd_dyn, radiusd_dyn)
2. **Remove interfaces from netplan** configuration
3. **Apply netplan changes** to restore network
4. **Clean up configuration files** (frr_dyn.conf, dhcpd.conf, etc.)
5. **Preserve Docker images** for future use
6. **Preserve all installed packages** - no system changes

**✅ Safe Cleanup**: Only removes demo configurations, keeps all system packages and Docker images!

## Security Notes

- Scripts require `sudo` privileges for network configuration
- Docker containers run with `--privileged` mode for network access
- All network changes are logged for audit purposes
- State files are created in `/etc/dynamicwan_configured_interfaces.conf`
- User is automatically added to docker group for future use

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review container logs for specific errors
3. Ensure all prerequisites are met
4. Verify interface names and IP configurations
5. Check the automatic rollback logs if setup failed

## Version Information

- **Script Version**: v6_dynamic_wan (Enhanced)
- **Compatible OS**: Ubuntu 24.04.3 LTS
- **Docker Images**: FRR, FreeRADIUS, Custom DHCP
- **Features**: Fully automated installation, robust error handling, safe cleanup
- **Last Updated**: 2025

---

**⚠️ Important**: Always run the cleanup script when finished with the demo to restore your system to its original network configuration. The cleanup script only removes configurations, not packages.

**🎉 Ready to Use**: This script is now production-ready and perfect for fresh employees with no Linux/networking experience!