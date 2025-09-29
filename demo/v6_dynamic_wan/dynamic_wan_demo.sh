#!/bin/bash
set -euo pipefail

echo "🚀 Dynamic WAN Network Setup Script"
echo "===================================="
echo "This script configures 1-4 network uplinks dynamically using parameters.txt"
echo "Configure only the interfaces you need - unused ones should have empty quotes"
echo ""

# Script directory and parameters file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMS_FILE="$SCRIPT_DIR/parameters.txt"

# Global variables for dynamic configuration
declare -a ACTIVE_INTERFACES=()
declare -a ACTIVE_LAN_IPS=()
declare -a ACTIVE_LAN_SUBNETS=()
declare -a ACTIVE_LAN_NET_ADDRS=()
NUM_ACTIVE_UPLINKS=0

# Function to check if the interface exists
check_interface() {
    if ! ip link show "$1" &> /dev/null; then
        echo "❌ ERROR: Interface $1 does not exist on the host."
        echo "   Please check the interface name with: ip link show"
        echo "   Available interfaces:"
        ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print "     " $2}' | sed 's/@.*$//'
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

# Function to parse and validate parameters.txt file
parse_parameters() {
    echo "📄 Reading parameters from: $PARAMS_FILE"
    
    if [ ! -f "$PARAMS_FILE" ]; then
        echo "❌ ERROR: Parameters file not found: $PARAMS_FILE"
        exit 1
    fi
    
    # Read and parse parameters, removing quotes
    eval "$(grep -E '^uplink[1-4]_' "$PARAMS_FILE" | sed 's/"//g')" 2>/dev/null
    
    # Validate and collect active uplinks
    local active_count=0
    for i in {1..4}; do
        local interface_var="uplink${i}_interface"
        local lan_ip_var="uplink${i}_lan_ip"
        local lan_subnet_var="uplink${i}_lan_subnet"
        
        local interface="${!interface_var:-}"
        local lan_ip="${!lan_ip_var:-}"
        local lan_subnet="${!lan_subnet_var:-}"
        
        # Skip empty interfaces
        if [ -z "$interface" ] || [ -z "$lan_ip" ] || [ -z "$lan_subnet" ]; then
            echo "ℹ️  Uplink $i: Disabled (empty parameters)"
            continue
        fi
        
        # Validate interface exists
        echo "🔍 Validating uplink $i interface: $interface"
        check_interface "$interface"
        echo "✅ Interface $interface exists"
        
        # Add to active arrays
        ACTIVE_INTERFACES+=("$interface")
        ACTIVE_LAN_IPS+=("$lan_ip")
        ACTIVE_LAN_SUBNETS+=("$lan_subnet")
        
        # Extract network address
        local lan_net_addr=$(echo "$lan_subnet" | cut -d'/' -f1)
        ACTIVE_LAN_NET_ADDRS+=("$lan_net_addr")
        
        active_count=$((active_count + 1))
        echo "✅ Uplink $i: $interface -> $lan_ip (subnet: $lan_subnet)"
    done
    
    NUM_ACTIVE_UPLINKS=$active_count
    
    if [ $NUM_ACTIVE_UPLINKS -eq 0 ]; then
        echo "❌ ERROR: No active uplinks found in parameters file"
        echo "   Please configure at least one uplink with valid interface, IP, and subnet"
        exit 1
    fi
    
    echo "✅ Successfully parsed $NUM_ACTIVE_UPLINKS active uplink(s)"
    echo "--------------------------------------------------------------"
}

# Function to display configuration summary
display_configuration() {
    echo "📋 Dynamic WAN Configuration Summary:"
    echo ""
    echo "   Active Uplinks: $NUM_ACTIVE_UPLINKS"
    echo ""
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        echo "  🔗 UPLINK $((i+1)):"
        echo "     Interface:    ${ACTIVE_INTERFACES[i]}"
        echo "     LAN IP:       ${ACTIVE_LAN_IPS[i]}"
        echo "     LAN Subnet:   ${ACTIVE_LAN_SUBNETS[i]}"
        echo "     Network Addr: ${ACTIVE_LAN_NET_ADDRS[i]}"
        echo ""
    done
    echo "--------------------------------------------------------------"
}

# Function to run FRR container
create_frr_container() {
    local containerName="frr_dynamicwan"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
    -v ./frr_dynamicwan.conf:/etc/frr/frr.conf:Z \
    -v ./daemons:/etc/frr/daemons:Z  \
     docker.io/frrouting/frr

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run DHCPD container
create_dhcpd_container() {
    local containerName="dhcpd_dynamicwan"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     dhcpd

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run RADIUS container
create_radiusd_container() {
    local containerName="radiusd_dynamicwan"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     radiusd
    
    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to generate dynamic FRR config file
generate_frr_config() {
    local config_file="frr_dynamicwan.conf"

    cat <<EOF > "$config_file"
frr version 8.4_git
frr defaults traditional
hostname frr
log stdout
ip forwarding
no ipv6 forwarding
!
EOF

    # Add interface configurations dynamically for active uplinks
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        cat <<EOF >> "$config_file"
interface ${ACTIVE_INTERFACES[i]}
 ip address ${ACTIVE_LAN_IPS[i]}
 ip ospf network point-to-point
!
EOF
    done

    # Add OSPF configuration
    cat <<EOF >> "$config_file"
router ospf
 ospf router-id 1.1.1.1
EOF

    # Add networks to OSPF dynamically for active uplinks
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        echo " network ${ACTIVE_LAN_SUBNETS[i]} area 0" >> "$config_file"
    done

    cat <<EOF >> "$config_file"
 default-information originate always
!
line vty
!
EOF

    echo "✅ FRR config written to $config_file for $NUM_ACTIVE_UPLINKS active uplink(s)"
    echo "--------------------------------------------------------------"
}

# Function to configure netplan for all active interfaces
configure_netplan() {
    echo "🔧 Configuring netplan for $NUM_ACTIVE_UPLINKS active uplink(s)..."
    
    # Find the netplan configuration file
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "❌ No netplan configuration file found in /etc/netplan/"
        exit 1
    fi

    echo "✅ Using netplan file: $NETPLAN_FILE"
    
    # Create Dynamic WAN state tracking file
    local dynamicwan_state_file="/tmp/dynamicwan_configured_interfaces.conf"
    echo "# Dynamic WAN Network Setup - Configured Interfaces" > "$dynamicwan_state_file"
    echo "# Generated: $(date)" >> "$dynamicwan_state_file"
    echo "# Netplan file: $NETPLAN_FILE" >> "$dynamicwan_state_file"
    echo "# Number of active uplinks: $NUM_ACTIVE_UPLINKS" >> "$dynamicwan_state_file"
    echo "# Script version: dynamic-wan-v6" >> "$dynamicwan_state_file"
    echo "" >> "$dynamicwan_state_file"

    # Build Python script dynamically for netplan configuration
    local python_script=""
    python_script+="import yaml\n"
    python_script+="import sys\n\n"
    python_script+="try:\n"
    python_script+="    # Read the existing netplan file\n"
    python_script+="    with open('$NETPLAN_FILE', 'r') as f:\n"
    python_script+="        config = yaml.safe_load(f)\n"
    python_script+="    \n"
    python_script+="    # Ensure network section exists\n"
    python_script+="    if 'network' not in config:\n"
    python_script+="        config['network'] = {}\n"
    python_script+="    \n"
    python_script+="    # Add/update the interface configurations\n"
    python_script+="    if 'ethernets' not in config['network']:\n"
    python_script+="        config['network']['ethernets'] = {}\n"
    python_script+="    \n"
    
    # Add each active interface configuration and record in state file
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        local ip_addr=$(echo "${ACTIVE_LAN_IPS[i]}" | cut -d'/' -f1)
        local prefix=$(echo "${ACTIVE_LAN_IPS[i]}" | cut -d'/' -f2)
        
        # Record this interface in our state file
        echo "interface=${ACTIVE_INTERFACES[i]}" >> "$dynamicwan_state_file"
        echo "lan_ip=${ACTIVE_LAN_IPS[i]}" >> "$dynamicwan_state_file"
        echo "lan_subnet=${ACTIVE_LAN_SUBNETS[i]}" >> "$dynamicwan_state_file"
        echo "" >> "$dynamicwan_state_file"
        
        python_script+="    # Configure ${ACTIVE_INTERFACES[i]} (Dynamic WAN)\n"
        python_script+="    config['network']['ethernets']['${ACTIVE_INTERFACES[i]}'] = {\n"
        python_script+="        'dhcp4': False,\n"
        python_script+="        'addresses': ['$ip_addr/$prefix']\n"
        python_script+="    }\n"
        python_script+="    \n"
    done
    
    python_script+="    # Write the updated configuration\n"
    python_script+="    with open('$NETPLAN_FILE', 'w') as f:\n"
    python_script+="        yaml.dump(config, f, default_flow_style=False, sort_keys=False)\n"
    python_script+="    \n"
    python_script+="    print('✅ Netplan configuration updated successfully')\n"
    python_script+="    \n"
    python_script+="except Exception as e:\n"
    python_script+="    print(f'❌ Error updating netplan: {e}')\n"
    python_script+="    sys.exit(1)\n"

    # Execute the Python script
    echo -e "$python_script" | sudo python3 || {
        echo "❌ Failed to update netplan configuration"
        exit 1
    }

    # Apply the netplan configuration
    sudo netplan apply
    
    echo "✅ All $NUM_ACTIVE_UPLINKS active uplink(s) configured with static IPs"
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        echo "   ${ACTIVE_INTERFACES[i]}: ${ACTIVE_LAN_IPS[i]}"
    done
    
    # Wait for network to stabilize
    sleep 2
    
    # Make state file persistent and secure it
    sudo mv "$dynamicwan_state_file" "/etc/dynamicwan_configured_interfaces.conf"
    sudo chown root:root "/etc/dynamicwan_configured_interfaces.conf"
    sudo chmod 644 "/etc/dynamicwan_configured_interfaces.conf"
    
    echo "✅ Dynamic WAN state tracking file created: /etc/dynamicwan_configured_interfaces.conf"
    echo "   This file tracks interfaces configured by Dynamic WAN for safe cleanup"
    
    # Export Dynamic WAN state file path for use by setup_nat function
    export DYNAMIC_WAN_STATE_FILE="/etc/dynamicwan_configured_interfaces.conf"
    
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
        
        # Record internet interface in state file for cleanup tracking
        if [ -n "$DYNAMIC_WAN_STATE_FILE" ]; then
            echo "# Internet interface used for NAT" >> "$DYNAMIC_WAN_STATE_FILE"
            echo "internet_interface=$INTERNET_IFACE" >> "$DYNAMIC_WAN_STATE_FILE"
            echo "" >> "$DYNAMIC_WAN_STATE_FILE"
        fi
    else
        echo "❌ No default internet interface found."
        echo "   Please ensure you have internet connectivity before running this script."
        exit 1
    fi
    
    # Create setup-nat.sh dynamically
    sudo tee /usr/local/bin/setup-nat-dynamicwan.sh > /dev/null <<EOF
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
    sudo chmod +x /usr/local/bin/setup-nat-dynamicwan.sh
    
    # Enable IP forwarding persistently in sysctl.conf
    echo "🔧 Configuring persistent IP forwarding..."
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        # Create backup before modifying
        sudo cp /etc/sysctl.conf /etc/sysctl.conf.dynamicwan_backup.$(date +%Y%m%d_%H%M%S)
        echo "   💾 Created backup: /etc/sysctl.conf.dynamicwan_backup.$(date +%Y%m%d_%H%M%S)"
        
        # Add IP forwarding setting
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
        echo "   ✅ Added net.ipv4.ip_forward=1 to /etc/sysctl.conf"
        
        # Apply the setting immediately
        sudo sysctl -p /etc/sysctl.conf > /dev/null
        echo "   ✅ Applied sysctl configuration"
    else
        echo "   ℹ️  IP forwarding already enabled in sysctl.conf"
    fi
    
    # Run setup-nat-dynamicwan.sh
    echo "🔧 Setting up NAT with internet interface: $INTERNET_IFACE"
    /usr/local/bin/setup-nat-dynamicwan.sh
    
    echo "🔧 Creating NAT systemd service..."
    sudo tee /etc/systemd/system/setup-nat-dynamicwan.service > /dev/null <<EOF
[Unit]
Description=Dynamic WAN Network NAT and IP Forwarding Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-nat-dynamicwan.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable/start the service
    sudo systemctl daemon-reload
    sudo systemctl enable setup-nat-dynamicwan.service
    sudo systemctl start setup-nat-dynamicwan.service
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

# Function to create DHCP configuration for dynamic subnets
create_dhcp_config() {
    echo "🔧 Creating DHCP configuration for $NUM_ACTIVE_UPLINKS active uplink(s)..."
    
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
    
    # Create DHCP Startup script using first active interface
    cat <<EOF > dhcpdStartup.sh
#!/bin/bash
set -e

echo "\$(date): Starting Dynamic WAN DHCP service startup script" >> /var/log/startup.log
echo "\$(date): Starting Dynamic WAN DHCP service startup script"

# Start the DHCP server on first active interface
echo "\$(date): Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid ${ACTIVE_INTERFACES[0]}

echo "\$(date): DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
EOF

    echo "✅ Created dhcpdStartup.sh"
    
    # Create dhcpd.conf with dynamic subnets
    cat <<EOF > dhcpd.conf
# dhcpd.conf for Dynamic WAN Network Configuration ($NUM_ACTIVE_UPLINKS active uplinks)
#
# Sample configuration file for ISC dhcpd
#

# option definitions common to all supported networks...
option domain-name "dynamicwan.local";
option domain-name-servers 8.8.8.8, 8.8.4.4;

default-lease-time 600;
max-lease-time 7200;

# The ddns-updates-style parameter controls whether or not the server will
# attempt to do a DNS update when a lease is confirmed.
ddns-update-style none;

# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
authoritative;

EOF

    # Add subnet declarations dynamically for active uplinks
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        echo "# Active uplink $((i+1)) subnet declaration" >> dhcpd.conf
        echo "subnet ${ACTIVE_LAN_NET_ADDRS[i]} netmask 255.255.255.252 {" >> dhcpd.conf
        echo "}" >> dhcpd.conf
        echo "" >> dhcpd.conf
    done

    # Add example client subnets
    cat <<EOF >> dhcpd.conf
# Example client subnets (can be modified as needed)
subnet 192.168.18.0 netmask 255.255.255.0 {
  range 192.168.18.11 192.168.18.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "dynamicwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.18.1;
  option broadcast-address 192.168.18.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.19.0 netmask 255.255.255.0 {
  range 192.168.19.11 192.168.19.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "dynamicwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.19.1;
  option broadcast-address 192.168.19.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.20.0 netmask 255.255.255.0 {
  range 192.168.20.11 192.168.20.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "dynamicwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.20.1;
  option broadcast-address 192.168.20.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.21.0 netmask 255.255.255.0 {
  range 192.168.21.11 192.168.21.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "dynamicwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.21.1;
  option broadcast-address 192.168.21.255;
  default-lease-time 600;
  max-lease-time 7200;
}

EOF

    echo "✅ Created dhcpd.conf with $NUM_ACTIVE_UPLINKS active uplink subnet(s)"
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

EOF

    # Add dynamic uplink clients for active interfaces
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        cat <<EOF >> clients.conf
# Allow connections from active uplink $((i+1)) subnet
client activeuplink$((i+1)) {
 ipaddr = ${ACTIVE_LAN_SUBNETS[i]}
 proto = *
 secret = nile123
}

EOF
    done

    cat <<EOF >> clients.conf
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
    
    # Create other RADIUS files (reusing from multi_wan)
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
    
    # Create RADIUS Containerfile
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
    echo "✅ Dynamic WAN Network Setup Complete!"
    echo ""
    echo "==============================================================="
    echo "                    CONFIGURATION SUMMARY"
    echo "==============================================================="
    
    for ((i=0; i<NUM_ACTIVE_UPLINKS; i++)); do
        echo "| ACTIVE UPLINK $((i+1)) (${ACTIVE_INTERFACES[i]}):"
        echo "|   Interface IP:     ${ACTIVE_LAN_IPS[i]}"
        echo "|   Network Subnet:   ${ACTIVE_LAN_SUBNETS[i]}"
        echo "|   DHCP Server IP:   ${ACTIVE_LAN_IPS[i]}"
        echo "|   RADIUS Server IP: ${ACTIVE_LAN_IPS[i]}"
        echo "|____________________________________________________________"
    done
    
    echo ""
    echo "🐳 Docker Containers Started:"
    echo "   • frr_dynamicwan (FRR Routing - $NUM_ACTIVE_UPLINKS interfaces)"
    echo "   • dhcpd_dynamicwan (DHCP Server)"
    echo "   • radiusd_dynamicwan (RADIUS Server)"
    echo ""
    echo "🔧 Services Configured:"
    echo "   • NAT and IP Forwarding enabled"
    echo "   • OSPF routing for all $NUM_ACTIVE_UPLINKS active uplinks"
    echo "   • Static IP addresses assigned"
    echo ""
    echo "ℹ️  Use dynamic_wan_cleanup.sh to remove all configuration when done"
}

# ===============================================================
#                         MAIN EXECUTION
# ===============================================================

echo "🔍 Starting Dynamic WAN Network configuration process..."
echo ""

# Parse parameters and determine active uplinks
parse_parameters

# Display configuration summary
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

echo "🎉 Dynamic WAN Network setup completed successfully!"
echo ""
echo "📋 Configuration Details:"
echo "   • Parameter file: $PARAMS_FILE"
echo "   • Active uplinks: $NUM_ACTIVE_UPLINKS"
echo "   • State file: /etc/dynamicwan_configured_interfaces.conf"
echo "   • Domain: dynamicwan.local"

