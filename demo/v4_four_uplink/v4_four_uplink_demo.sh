#!/bin/bash
set -euo pipefail

echo "🚀 V4 Four Uplink Demo Script"
echo "============================="
echo "This script configures 4 network uplinks using parameters from parameters.txt"
echo ""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMS_FILE="$SCRIPT_DIR/parameters.txt"

# Function to check if the interface exists
check_interface() {
    if ! ip link show "$1" &> /dev/null; then
        echo "❌ Error: Interface $1 does not exist on the host."
        exit 1
    fi
}

# Function to check if Python3 is installed
check_python3() {
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python3 not found. Installing..."
        sudo apt-get update
        sudo apt-get install -y python3
        if ! command -v python3 &> /dev/null; then
            echo "❌ Failed to install Python3"
            exit 1
        fi
        echo "✅ Python3 installed successfully"
    else
        echo "✅ Python3 is available"
    fi
}

# Function to check if PyYAML is installed
check_pyyaml() {
    if ! python3 -c "import yaml" &> /dev/null; then
        echo "❌ PyYAML not found. Installing..."
        sudo apt-get update
        sudo apt-get install -y python3-yaml
        if ! python3 -c "import yaml" &> /dev/null; then
            echo "❌ Failed to install PyYAML"
            exit 1
        fi
        echo "✅ PyYAML installed successfully"
    else
        echo "✅ PyYAML is available"
    fi
}

# Function to check and install dependencies
check_dependencies() {
    echo "🔍 Checking dependencies..."
    check_python3
    check_pyyaml
    echo "✅ All dependencies are available"
    echo "--------------------------------------------------------------"
}

# Function to parse parameters.txt file
parse_parameters() {
    echo "📄 Reading parameters from: $PARAMS_FILE"
    
    if [ ! -f "$PARAMS_FILE" ]; then
        echo "❌ Error: Parameters file not found: $PARAMS_FILE"
        exit 1
    fi
    
    # Read and parse parameters using source
    # Remove quotes when parsing
    eval "$(grep -E '^uplink[1-4]_' "$PARAMS_FILE" | sed 's/"//g')"
    
    # Validate that all required parameters are set
    for i in {1..4}; do
        local interface_var="uplink${i}_interface"
        local lan_ip_var="uplink${i}_lan_ip"
        local lan_subnet_var="uplink${i}_lan_subnet"
        
        if [ -z "${!interface_var:-}" ]; then
            echo "❌ Error: Missing parameter: $interface_var"
            exit 1
        fi
        
        if [ -z "${!lan_ip_var:-}" ]; then
            echo "❌ Error: Missing parameter: $lan_ip_var"
            exit 1
        fi
        
        if [ -z "${!lan_subnet_var:-}" ]; then
            echo "❌ Error: Missing parameter: $lan_subnet_var"
            exit 1
        fi
    done
    
    echo "✅ Successfully parsed parameters for 4 uplinks"
    echo "--------------------------------------------------------------"
}

# Function to display parsed configuration
display_configuration() {
    echo "📋 Configuration Summary:"
    echo ""
    for i in {1..4}; do
        local interface_var="uplink${i}_interface"
        local lan_ip_var="uplink${i}_lan_ip"
        local lan_subnet_var="uplink${i}_lan_subnet"
        
        echo "  🔗 UPLINK $i:"
        echo "     Interface:   ${!interface_var}"
        echo "     LAN IP:      ${!lan_ip_var}"
        echo "     LAN Subnet:  ${!lan_subnet_var}"
        echo ""
    done
    echo "--------------------------------------------------------------"
}

# Function to validate interfaces exist
validate_interfaces() {
    echo "🔍 Validating network interfaces..."
    
    for i in {1..4}; do
        local interface_var="uplink${i}_interface"
        local interface_name="${!interface_var}"
        echo "  Checking interface: $interface_name"
        check_interface "$interface_name"
        echo "  ✅ Interface $interface_name exists"
    done
    
    echo "✅ All interfaces validated successfully"
    echo "--------------------------------------------------------------"
}

# Function to run FRR container
create_frr_container() {
    local containerName="frr_a"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
    -v ./frr_a.conf:/etc/frr/frr.conf:Z \
    -v ./daemons:/etc/frr/daemons:Z  \
     docker.io/frrouting/frr

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run DHCPD container
create_dhcpd_container() {
    local containerName="dhcpd_a"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     dhcpd

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run RADIUS container
create_radiusd_container() {
    local containerName="radiusd_a"
    
    docker run -dt --name $containerName --network=host --privileged --restart=always \
     radiusd
    
    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to generate FRR config file for 4 uplinks
generate_frr_config() {
    local config_file="frr_a.conf"

    cat <<EOF > "$config_file"
frr version 8.4_git
frr defaults traditional
hostname frr
log stdout
ip forwarding
no ipv6 forwarding
!
interface $uplink1_interface
 ip address $uplink1_lan_ip
 ip ospf network point-to-point
!
interface $uplink2_interface
 ip address $uplink2_lan_ip
 ip ospf network point-to-point
!
interface $uplink3_interface
 ip address $uplink3_lan_ip
 ip ospf network point-to-point
!
interface $uplink4_interface
 ip address $uplink4_lan_ip
 ip ospf network point-to-point
!
router ospf
 ospf router-id 1.1.1.1
 network $uplink1_lan_subnet area 0
 network $uplink2_lan_subnet area 0
 network $uplink3_lan_subnet area 0
 network $uplink4_lan_subnet area 0
 default-information originate always
!
line vty
!
EOF

    echo "✅ FRR config written to $config_file"
    echo "--------------------------------------------------------------"
}

# Function to configure netplan for all 4 interfaces
configure_netplan() {
    echo "🔧 Configuring netplan for 4 uplinks..."
    
    # Find the netplan configuration file
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "❌ No netplan configuration file found in /etc/netplan/"
        exit 1
    fi

    echo "✅ Using netplan file: $NETPLAN_FILE"

    # Extract IP addresses and prefixes for all uplinks
    local ip_addr1=$(echo "$uplink1_lan_ip" | cut -d'/' -f1)
    local prefix1=$(echo "$uplink1_lan_ip" | cut -d'/' -f2)
    local ip_addr2=$(echo "$uplink2_lan_ip" | cut -d'/' -f1)
    local prefix2=$(echo "$uplink2_lan_ip" | cut -d'/' -f2)
    local ip_addr3=$(echo "$uplink3_lan_ip" | cut -d'/' -f1)
    local prefix3=$(echo "$uplink3_lan_ip" | cut -d'/' -f2)
    local ip_addr4=$(echo "$uplink4_lan_ip" | cut -d'/' -f1)
    local prefix4=$(echo "$uplink4_lan_ip" | cut -d'/' -f2)
    
    # Update netplan configuration for all 4 interfaces
    sudo python3 -c "
import yaml
import sys

try:
    # Read the existing netplan file
    with open('$NETPLAN_FILE', 'r') as f:
        config = yaml.safe_load(f)
    
    # Ensure network section exists
    if 'network' not in config:
        config['network'] = {}
    
    # Add/update the interface configurations
    if 'ethernets' not in config['network']:
        config['network']['ethernets'] = {}
    
    # Configure all 4 uplinks
    config['network']['ethernets']['$uplink1_interface'] = {
        'dhcp4': False,
        'addresses': ['$ip_addr1/$prefix1']
    }
    
    config['network']['ethernets']['$uplink2_interface'] = {
        'dhcp4': False,
        'addresses': ['$ip_addr2/$prefix2']
    }
    
    config['network']['ethernets']['$uplink3_interface'] = {
        'dhcp4': False,
        'addresses': ['$ip_addr3/$prefix3']
    }
    
    config['network']['ethernets']['$uplink4_interface'] = {
        'dhcp4': False,
        'addresses': ['$ip_addr4/$prefix4']
    }
    
    # Write the updated configuration
    with open('$NETPLAN_FILE', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    print('✅ Netplan configuration updated successfully')
    
except Exception as e:
    print(f'❌ Error updating netplan: {e}')
    sys.exit(1)
" || {
    echo "❌ Failed to update netplan configuration"
    exit 1
}

    # Apply the netplan configuration
    sudo netplan apply
    
    echo "✅ All 4 uplinks configured with static IPs"
    for i in {1..4}; do
        local interface_var="uplink${i}_interface"
        local lan_ip_var="uplink${i}_lan_ip"
        echo "   ${!interface_var}: ${!lan_ip_var}"
    done
    
    # Wait for network to stabilize
    sleep 2
    echo "--------------------------------------------------------------"
}

# Function to setup NAT and IP forwarding
setup_nat() {
    echo "🔧 Setting up NAT and IP forwarding..."
    
    # Get the interface used for the default route (internet access)
    echo "🔍 Detecting internet-facing interface..."
    
    INTERNET_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    
    # Fallback method if the first one fails
    if [ -z "$INTERNET_IFACE" ]; then
        INTERNET_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -1)
    fi
    
    if [ -n "$INTERNET_IFACE" ]; then
        echo "✅ Internet-facing interface: $INTERNET_IFACE"
    else
        echo "❌ No default internet interface found."
        echo "   Please ensure you have internet connectivity before running this script."
        exit 1
    fi
    
    # Create setup-nat.sh dynamically
    sudo tee /usr/local/bin/setup-nat-v4.sh > /dev/null <<EOF
#!/bin/bash
set -euo pipefail

# Function to detect the internet-facing interface
detect_internet_interface() {
    INTERNET_IFACE=\$(ip route | awk '/^default/ {print \$5; exit}')
    
    if [ -n "\$INTERNET_IFACE" ]; then
        if ip link show "\$INTERNET_IFACE" &>/dev/null && ip link show "\$INTERNET_IFACE" | grep -q "state UP"; then
            echo "Internet-facing interface: \$INTERNET_IFACE" >&2
            echo "\$INTERNET_IFACE"
        else
            echo "Warning: Interface \$INTERNET_IFACE found in routing table but is not available or not up" >&2
            exit 1
        fi
    else
        echo "No default internet interface found." >&2
        exit 1
    fi
}

# Function to setup NAT rules for multiple interfaces
setup_nat() {
    local internet_iface="\$1"
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    
    # Add iptables rules for internet interface
    sudo iptables -t nat -A POSTROUTING -o "\$internet_iface" -j MASQUERADE
    sudo iptables -A FORWARD -o "\$internet_iface" -j ACCEPT
    sudo iptables -A FORWARD -i "\$internet_iface" -m state --state ESTABLISHED,RELATED -j ACCEPT
}

# Main execution
INTERNET_IFACE=\$(detect_internet_interface)
setup_nat "\$INTERNET_IFACE"
EOF
    
    # Make it executable
    sudo chmod +x /usr/local/bin/setup-nat-v4.sh
    
    # Run setup-nat-v4.sh
    echo "🔧 Setting up NAT with internet interface: $INTERNET_IFACE"
    /usr/local/bin/setup-nat-v4.sh
    
    echo "🔧 Creating NAT systemd service..."
    sudo tee /etc/systemd/system/setup-nat-v4.service > /dev/null <<EOF
[Unit]
Description=V4 Four Uplink NAT and IP Forwarding Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-nat-v4.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable/start the service
    sudo systemctl daemon-reload
    sudo systemctl enable setup-nat-v4.service
    sudo systemctl start setup-nat-v4.service
    echo "✅ NAT service created and started"
    echo "--------------------------------------------------------------"
}

# Function to create shared FRR daemons file
create_frr_daemons() {
    cat <<EOF > daemons
zebra=yes
bgpd=no
ospfd=yes
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no
#
# If this option is set the /etc/init.d/frr script automatically loads
# the config via "vtysh -b" when the servers are started.
# Check /etc/pam.d/frr if you intend to use "vtysh"!
#
vtysh_enable=yes
zebra_options=" -s 90000000 --daemon -A 127.0.0.1"
bgpd_options="   --daemon -A 127.0.0.1"
ospfd_options="  --daemon -A 127.0.0.1"
ospf6d_options=" --daemon -A ::1"
ripd_options="   --daemon -A 127.0.0.1"
ripngd_options=" --daemon -A ::1"
isisd_options="  --daemon -A 127.0.0.1"
pimd_options="  --daemon -A 127.0.0.1"
ldpd_options="  --daemon -A 127.0.0.1"
nhrpd_options="  --daemon -A 127.0.0.1"
eigrpd_options="  --daemon -A 127.0.0.1"
babeld_options="  --daemon -A 127.0.0.1"
sharpd_options="  --daemon -A 127.0.0.1"
staticd_options="  --daemon -A 127.0.0.1"
pbrd_options="  --daemon -A 127.0.0.1"
bfdd_options="  --daemon -A 127.0.0.1"
fabricd_options="  --daemon -A 127.0.0.1"

#MAX_FDS=1024
# The list of daemons to watch is automatically generated by the init script.
#watchfrr_options=""

# for debugging purposes, you can specify a "wrap" command to start instead
# of starting the daemon directly, e.g. to use valgrind on ospfd:
#   ospfd_wrap="/usr/bin/valgrind"
# or you can use "all_wrap" for all daemons, e.g. to use perf record:
#   all_wrap="/usr/bin/perf record --call-graph -"
# the normal daemon command is added to this at the end.
EOF

    echo "✅ Created FRR daemons file"
    echo "--------------------------------------------------------------"
}

# Function to create DHCP configuration for 4 subnets
create_dhcp_config() {
    echo "🔧 Creating DHCP configuration for 4 uplinks..."
    
    # Extract network addresses
    local lan_net_addr1=$(echo "$uplink1_lan_subnet" | cut -d'/' -f1)
    local lan_net_addr2=$(echo "$uplink2_lan_subnet" | cut -d'/' -f1)
    local lan_net_addr3=$(echo "$uplink3_lan_subnet" | cut -d'/' -f1)
    local lan_net_addr4=$(echo "$uplink4_lan_subnet" | cut -d'/' -f1)
    
    # Create DHCP Containerfile
    cat <<EOF > dhcpdContainerfile
FROM ubuntu:latest

# Install necessary tools
RUN apt-get update && apt-get install -y iproute2 isc-dhcp-server freeradius-utils

# Create a DHCPD startup script
COPY dhcpdStartup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

# Copy the DHCP server configuration
COPY ./dhcpd.conf /etc/dhcp/dhcpd.conf
RUN touch /var/lib/dhcp/dhcpd.leases

# Command to execute the startup script
CMD ["/usr/local/bin/startup.sh"]
EOF

    echo "✅ Created dhcpdContainerfile"
    
    # Create DHCP Startup script
    cat <<EOF > dhcpdStartup.sh
#!/bin/bash
set -e

echo "\$(date): Starting V4 Four Uplink DHCP service startup script" >> /var/log/startup.log
echo "\$(date): Starting V4 Four Uplink DHCP service startup script"

# Start the DHCP server on first interface (can be modified as needed)
echo "\$(date): Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid $uplink1_interface

echo "\$(date): DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
EOF

    echo "✅ Created dhcpdStartup.sh"
    
    # Create dhcpd.conf with 4 subnets
    cat <<EOF > dhcpd.conf
# dhcpd.conf for V4 Four Uplink Configuration
#
# Sample configuration file for ISC dhcpd
#

# option definitions common to all supported networks...
option domain-name "v4fourlink.local";
option domain-name-servers 8.8.8.8, 8.8.4.4;

default-lease-time 600;
max-lease-time 7200;

# The ddns-updates-style parameter controls whether or not the server will
# attempt to do a DNS update when a lease is confirmed.
ddns-update-style none;

# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
authoritative;

# Uplink 1 subnet declaration
subnet $lan_net_addr1 netmask 255.255.255.252 {
}

# Uplink 2 subnet declaration  
subnet $lan_net_addr2 netmask 255.255.255.252 {
}

# Uplink 3 subnet declaration
subnet $lan_net_addr3 netmask 255.255.255.252 {
}

# Uplink 4 subnet declaration
subnet $lan_net_addr4 netmask 255.255.255.252 {
}

# Example client subnets (can be modified as needed)
subnet 192.168.18.0 netmask 255.255.255.0 {
  range 192.168.18.11 192.168.18.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "v4fourlink.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.18.1;
  option broadcast-address 192.168.18.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.19.0 netmask 255.255.255.0 {
  range 192.168.19.11 192.168.19.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "v4fourlink.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.19.1;
  option broadcast-address 192.168.19.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.20.0 netmask 255.255.255.0 {
  range 192.168.20.11 192.168.20.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "v4fourlink.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.20.1;
  option broadcast-address 192.168.20.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.21.0 netmask 255.255.255.0 {
  range 192.168.21.11 192.168.21.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "v4fourlink.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.21.1;
  option broadcast-address 192.168.21.255;
  default-lease-time 600;
  max-lease-time 7200;
}

EOF

    echo "✅ Created dhcpd.conf with 4 uplink subnets"
    echo "--------------------------------------------------------------"
}

# Function to create RADIUS configuration files
create_radius_config() {
    echo "🔧 Creating RADIUS configuration..."
    
    # Create RADIUS clients.conf
    cat <<EOF > clients.conf
client local1 {
 ipaddr = 127.0.0.1
 proto = *
 secret = nile123
}

# Allow connections from all uplink subnets
client uplink1 {
 ipaddr = $uplink1_lan_subnet
 proto = *
 secret = nile123
}

client uplink2 {
 ipaddr = $uplink2_lan_subnet
 proto = *
 secret = nile123
}

client uplink3 {
 ipaddr = $uplink3_lan_subnet  
 proto = *
 secret = nile123
}

client uplink4 {
 ipaddr = $uplink4_lan_subnet
 proto = *
 secret = nile123
}

client hol1 {
 ipaddr = 172.16.0.0/16
 proto = *
 secret = nile123
}

client hol2 {
 ipaddr = 192.168.0.0/16
 proto = *
 secret = nile123
}

client hol3 {
 ipaddr = 10.0.0.0/8
 proto = *
 secret = nile123
}
EOF

    echo "✅ Created clients.conf"
    
    # Create other RADIUS files (reusing from v2_demo)
    cat <<EOF > dictionary.nile
VENDOR          Nile            58313

BEGIN-VENDOR    Nile

ATTRIBUTE       redirect-url  1   string
# This defines netsegment
ATTRIBUTE       netseg        2   string
# Nile AV Pair
ATTRIBUTE       nile-avpair   3   string

END-VENDOR      Nile
EOF

    echo "✅ Created dictionary.nile"
    
    # Create authorize file
    cat <<EOF > authorize
bob     Cleartext-Password := "hello"
        Reply-Message := "Hello, %{User-Name}"
#
#
employee      Cleartext-Password := "nilesecure"
              netseg = "Employee"
#
contractor    Cleartext-Password := "nilesecure"
              netseg = "contractor"
sally@nilenetworks.com      Cleartext-Password := "nilesecure"
              netseg = "corporate"
harry-ext@nilenetworks.com      Cleartext-Password := "nilesecure"
              netseg = "contractor"

EOF

    echo "✅ Created authorize file"
    echo "--------------------------------------------------------------"
}

# Function to create and build Docker images
create_docker_images() {
    echo "🐳 Creating Docker images..."
    
    # Create DHCP Image
    docker build -t dhcpd -f dhcpdContainerfile .
    echo "✅ DHCP Image created"
    
    # Create RADIUS Containerfile (reusing from v2_demo but updated)
    cat <<EOF > radiusdContainerfile
FROM docker.io/freeradius/freeradius-server:latest
RUN apt-get update && apt-get install -y iproute2 freeradius-utils
COPY ./clients.conf /etc/raddb/clients.conf
COPY ./authorize /etc/raddb/mods-config/files/authorize
COPY ./dictionary.nile /usr/share/freeradius/dictionary.nile
RUN cd /etc/raddb/certs && rm *.pem *.key *.crt *.p12 *.txt *.crl *.der *.old *.csr *.mk && ./bootstrap
EOF

    # Create RADIUS Image
    docker build -t radiusd -f radiusdContainerfile .
    echo "✅ RADIUS Image created"
    echo "--------------------------------------------------------------"
}

# Function to display final summary
display_summary() {
    echo "✅ V4 Four Uplink Setup Complete!"
    echo ""
    echo "==============================================================="
    echo "                    CONFIGURATION SUMMARY"
    echo "==============================================================="
    
    for i in {1..4}; do
        local interface_var="uplink${i}_interface"
        local lan_ip_var="uplink${i}_lan_ip"
        local lan_subnet_var="uplink${i}_lan_subnet"
        
        echo "| UPLINK $i (${!interface_var}):"
        echo "|   Interface IP:     ${!lan_ip_var}"
        echo "|   Network Subnet:   ${!lan_subnet_var}"
        echo "|   DHCP Server IP:   ${!lan_ip_var}"
        echo "|   RADIUS Server IP: ${!lan_ip_var}"
        echo "|____________________________________________________________"
    done
    
    echo ""
    echo "🐳 Docker Containers Started:"
    echo "   • frr_a (FRR Routing)"
    echo "   • dhcpd_a (DHCP Server)"
    echo "   • radiusd_a (RADIUS Server)"
    echo ""
    echo "🔧 Services Configured:"
    echo "   • NAT and IP Forwarding enabled"
    echo "   • OSPF routing for all 4 uplinks"
    echo "   • Static IP addresses assigned"
    echo ""
    echo "ℹ️  Use v4_four_uplink_cleanup.sh to remove all configuration when done"
}

# ===============================================================
#                         MAIN EXECUTION
# ===============================================================

echo "🔍 Starting V4 Four Uplink configuration process..."

# Parse parameters from file
parse_parameters

# Display configuration
display_configuration

# Ask for confirmation
echo "⚠️  This will configure your system with the above settings."
echo "   Make sure the interface names and IP addresses are correct."
echo ""
read -p "Do you want to continue? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Configuration cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting configuration..."

# Check dependencies
check_dependencies

# Validate interfaces
validate_interfaces


# Configure netplan
configure_netplan

# Setup NAT
setup_nat

# Create FRR configuration
create_frr_daemons
generate_frr_config

# Create DHCP configuration
create_dhcp_config

# Create RADIUS configuration
create_radius_config

# Create Docker images
create_docker_images

# Start containers
echo "🐳 Starting Docker containers..."
create_frr_container
create_dhcpd_container
create_radiusd_container

# Display final summary
display_summary

echo "🎉 V4 Four Uplink Demo setup completed successfully!"
