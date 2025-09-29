#!/bin/bash
set -euo pipefail

echo "🚀 Multi-WAN Network Setup Script"
echo "=================================="
echo "This script configures multiple network uplinks (1, 2, or 4 interfaces)"
echo ""

# Global variables for dynamic configuration
declare -a INTERFACES=()
declare -a LAN_IPS=()
declare -a LAN_SUBNETS=()
declare -a LAN_NET_ADDRS=()
NUM_UPLINKS=0

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

# Function to prompt for number of uplinks
prompt_uplink_count() {
    echo "🔢 How many uplink interfaces do you want to configure?"
    echo "   1) Single uplink (1 interface)"
    echo "   2) Dual uplink (2 interfaces)" 
    echo "   4) Quad uplink (4 interfaces)"
    echo ""
    
    while true; do
        read -p "Enter your choice (1, 2, or 4): " choice
        case $choice in
            1)
                NUM_UPLINKS=1
                echo "✅ Selected: Single uplink configuration"
                break
                ;;
            2)
                NUM_UPLINKS=2
                echo "✅ Selected: Dual uplink configuration"
                break
                ;;
            4)
                NUM_UPLINKS=4
                echo "✅ Selected: Quad uplink configuration"
                break
                ;;
            *)
                echo "❌ Invalid choice. Please enter 1, 2, or 4."
                ;;
        esac
    done
    echo "--------------------------------------------------------------"
}

# Function to prompt for interface details
prompt_interface_details() {
    echo "🌐 Configuring $NUM_UPLINKS uplink interface(s)..."
    echo ""
    
    # Default values for different configurations
    # Use generic interface names that work across different server types
    local default_interfaces=("eth0" "eth1" "eth2" "eth3")
    local default_ips=("172.16.0.1/30" "172.16.1.1/30" "172.16.2.1/30" "172.16.3.1/30")
    local default_subnets=("172.16.0.0/30" "172.16.1.0/30" "172.16.2.0/30" "172.16.3.0/30")
    
    echo "ℹ️  Default interface names are generic examples (eth0, eth1, etc.)"
    echo "   Please enter your actual interface names when prompted"
    echo ""
    
    for ((i=1; i<=NUM_UPLINKS; i++)); do
        echo "🔗 Uplink $i Configuration:"
        
        # Interface name
        local default_interface="${default_interfaces[$((i-1))]}"
        read -p "  Enter interface $i name (e.g., eth$((i-1)), enp${i}s0, eno${i}np0) [$default_interface]: " interface
        interface=${interface:-$default_interface}
        
        # Validate interface exists
        echo "  🔍 Validating interface: $interface"
        check_interface "$interface"
        echo "  ✅ Interface $interface exists"
        
        INTERFACES+=("$interface")
        
        # LAN IP
        local default_ip="${default_ips[$((i-1))]}"
        read -p "  Enter interface $i LAN IP (with /30 mask) [$default_ip]: " lan_ip
        lan_ip=${lan_ip:-$default_ip}
        LAN_IPS+=("$lan_ip")
        
        # LAN Subnet
        local default_subnet="${default_subnets[$((i-1))]}"
        read -p "  Enter interface $i LAN subnet (network address) [$default_subnet]: " lan_subnet
        lan_subnet=${lan_subnet:-$default_subnet}
        LAN_SUBNETS+=("$lan_subnet")
        
        # Extract network address
        local lan_net_addr=$(echo "$lan_subnet" | cut -d'/' -f1)
        LAN_NET_ADDRS+=("$lan_net_addr")
        
        echo "  ✅ Uplink $i: $interface -> $lan_ip (subnet: $lan_subnet)"
        echo ""
    done
    
    echo "--------------------------------------------------------------"
}

# Function to display configuration summary
display_configuration() {
    echo "📋 Configuration Summary:"
    echo ""
    for ((i=0; i<NUM_UPLINKS; i++)); do
        echo "  🔗 UPLINK $((i+1)):"
        echo "     Interface:   ${INTERFACES[i]}"
        echo "     LAN IP:      ${LAN_IPS[i]}"
        echo "     LAN Subnet:  ${LAN_SUBNETS[i]}"
        echo "     Network Addr: ${LAN_NET_ADDRS[i]}"
        echo ""
    done
    echo "--------------------------------------------------------------"
}

# Function to run FRR container
create_frr_container() {
    local containerName="frr_multi"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
    -v ./frr_multi.conf:/etc/frr/frr.conf:Z \
    -v ./daemons:/etc/frr/daemons:Z  \
     docker.io/frrouting/frr

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run DHCPD container
create_dhcpd_container() {
    local containerName="dhcpd_multi"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     dhcpd

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run RADIUS container
create_radiusd_container() {
    local containerName="radiusd_multi"
    
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     radiusd
    
    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to generate dynamic FRR config file
generate_frr_config() {
    local config_file="frr_multi.conf"

    cat <<EOF > "$config_file"
frr version 8.4_git
frr defaults traditional
hostname frr
log stdout
ip forwarding
no ipv6 forwarding
!
EOF

    # Add interface configurations dynamically
    for ((i=0; i<NUM_UPLINKS; i++)); do
        cat <<EOF >> "$config_file"
interface ${INTERFACES[i]}
 ip address ${LAN_IPS[i]}
 ip ospf network point-to-point
!
EOF
    done

    # Add OSPF configuration
    cat <<EOF >> "$config_file"
router ospf
 ospf router-id 1.1.1.1
EOF

    # Add networks to OSPF dynamically
    for ((i=0; i<NUM_UPLINKS; i++)); do
        echo " network ${LAN_SUBNETS[i]} area 0" >> "$config_file"
    done

    cat <<EOF >> "$config_file"
 default-information originate always
!
line vty
!
EOF

    echo "✅ FRR config written to $config_file with $NUM_UPLINKS interface(s)"
    echo "--------------------------------------------------------------"
}

# Function to configure netplan for all interfaces
configure_netplan() {
    echo "🔧 Configuring netplan for $NUM_UPLINKS uplink(s)..."
    
    # Find the netplan configuration file
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "❌ No netplan configuration file found in /etc/netplan/"
        exit 1
    fi

    echo "✅ Using netplan file: $NETPLAN_FILE"
    
    # Create Multi-WAN state tracking file to record what we configure
    local multi_wan_state_file="/tmp/multi_wan_configured_interfaces.conf"
    echo "# Multi-WAN Network Setup - Configured Interfaces" > "$multi_wan_state_file"
    echo "# Generated: $(date)" >> "$multi_wan_state_file"
    echo "# Netplan file: $NETPLAN_FILE" >> "$multi_wan_state_file"
    echo "# Number of uplinks: $NUM_UPLINKS" >> "$multi_wan_state_file"
    echo "# Script version: multi-wan" >> "$multi_wan_state_file"
    echo "" >> "$multi_wan_state_file"

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
    
    # Add each interface configuration and record in state file
    for ((i=0; i<NUM_UPLINKS; i++)); do
        local ip_addr=$(echo "${LAN_IPS[i]}" | cut -d'/' -f1)
        local prefix=$(echo "${LAN_IPS[i]}" | cut -d'/' -f2)
        
        # Record this interface in our state file
        echo "interface=${INTERFACES[i]}" >> "$multi_wan_state_file"
        echo "lan_ip=${LAN_IPS[i]}" >> "$multi_wan_state_file"
        echo "lan_subnet=${LAN_SUBNETS[i]}" >> "$multi_wan_state_file"
        echo "" >> "$multi_wan_state_file"
        
        python_script+="    # Configure ${INTERFACES[i]} (Multi-WAN)\n"
        python_script+="    config['network']['ethernets']['${INTERFACES[i]}'] = {\n"
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
    
    echo "✅ All $NUM_UPLINKS uplink(s) configured with static IPs"
    for ((i=0; i<NUM_UPLINKS; i++)); do
        echo "   ${INTERFACES[i]}: ${LAN_IPS[i]}"
    done
    
    # Wait for network to stabilize
    sleep 2
    
    # Make state file persistent and secure it
    sudo mv "$multi_wan_state_file" "/etc/multi_wan_configured_interfaces.conf"
    sudo chown root:root "/etc/multi_wan_configured_interfaces.conf"
    sudo chmod 644 "/etc/multi_wan_configured_interfaces.conf"
    
    echo "✅ Multi-WAN state tracking file created: /etc/multi_wan_configured_interfaces.conf"
    echo "   This file tracks interfaces configured by Multi-WAN for safe cleanup"
    
    # Export Multi-WAN state file path for use by setup_nat function
    export MULTI_WAN_STATE_FILE="/etc/multi_wan_configured_interfaces.conf"
    
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
        if [ -n "$MULTI_WAN_STATE_FILE" ]; then
            echo "# Internet interface used for NAT" >> "$MULTI_WAN_STATE_FILE"
            echo "internet_interface=$INTERNET_IFACE" >> "$MULTI_WAN_STATE_FILE"
            echo "" >> "$MULTI_WAN_STATE_FILE"
        fi
    else
        echo "❌ No default internet interface found."
        echo "   Please ensure you have internet connectivity before running this script."
        exit 1
    fi
    
    # Create setup-nat.sh dynamically
    sudo tee /usr/local/bin/setup-nat-multi.sh > /dev/null <<EOF
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
    sudo chmod +x /usr/local/bin/setup-nat-multi.sh
    
    # Enable IP forwarding persistently in sysctl.conf
    echo "🔧 Configuring persistent IP forwarding..."
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        # Create backup before modifying
        sudo cp /etc/sysctl.conf /etc/sysctl.conf.multiwan_backup.$(date +%Y%m%d_%H%M%S)
        echo "   💾 Created backup: /etc/sysctl.conf.multiwan_backup.$(date +%Y%m%d_%H%M%S)"
        
        # Add IP forwarding setting
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
        echo "   ✅ Added net.ipv4.ip_forward=1 to /etc/sysctl.conf"
        
        # Apply the setting immediately
        sudo sysctl -p /etc/sysctl.conf > /dev/null
        echo "   ✅ Applied sysctl configuration"
    else
        echo "   ℹ️  IP forwarding already enabled in sysctl.conf"
    fi
    
    # Run setup-nat-multi.sh
    echo "🔧 Setting up NAT with internet interface: $INTERNET_IFACE"
    /usr/local/bin/setup-nat-multi.sh
    
    echo "🔧 Creating NAT systemd service..."
    sudo tee /etc/systemd/system/setup-nat-multi.service > /dev/null <<EOF
[Unit]
Description=Multi-WAN Network NAT and IP Forwarding Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-nat-multi.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable/start the service
    sudo systemctl daemon-reload
    sudo systemctl enable setup-nat-multi.service
    sudo systemctl start setup-nat-multi.service
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

# Function to create DHCP configuration for multiple subnets
create_dhcp_config() {
    echo "🔧 Creating DHCP configuration for $NUM_UPLINKS uplink(s)..."
    
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

echo "\$(date): Starting Multi-WAN DHCP service startup script" >> /var/log/startup.log
echo "\$(date): Starting Multi-WAN DHCP service startup script"

# Start the DHCP server on first interface
echo "\$(date): Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid ${INTERFACES[0]}

echo "\$(date): DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
EOF

    echo "✅ Created dhcpdStartup.sh"
    
    # Create dhcpd.conf with dynamic subnets
    cat <<EOF > dhcpd.conf
# dhcpd.conf for Multi-WAN Network Configuration ($NUM_UPLINKS uplinks)
#
# Sample configuration file for ISC dhcpd
#

# option definitions common to all supported networks...
option domain-name "multiwan.local";
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

    # Add subnet declarations dynamically
    for ((i=0; i<NUM_UPLINKS; i++)); do
        echo "# Uplink $((i+1)) subnet declaration" >> dhcpd.conf
        echo "subnet ${LAN_NET_ADDRS[i]} netmask 255.255.255.252 {" >> dhcpd.conf
        echo "}" >> dhcpd.conf
        echo "" >> dhcpd.conf
    done

    # Add example client subnets
    cat <<EOF >> dhcpd.conf
# Example client subnets (can be modified as needed)
subnet 192.168.18.0 netmask 255.255.255.0 {
  range 192.168.18.11 192.168.18.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "multiwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.18.1;
  option broadcast-address 192.168.18.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.19.0 netmask 255.255.255.0 {
  range 192.168.19.11 192.168.19.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "multiwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.19.1;
  option broadcast-address 192.168.19.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.20.0 netmask 255.255.255.0 {
  range 192.168.20.11 192.168.20.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "multiwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.20.1;
  option broadcast-address 192.168.20.255;
  default-lease-time 600;
  max-lease-time 7200;
}

subnet 192.168.21.0 netmask 255.255.255.0 {
  range 192.168.21.11 192.168.21.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "multiwan.local";
  option subnet-mask 255.255.255.0;
  option routers 192.168.21.1;
  option broadcast-address 192.168.21.255;
  default-lease-time 600;
  max-lease-time 7200;
}

EOF

    echo "✅ Created dhcpd.conf with $NUM_UPLINKS uplink subnet(s)"
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

    # Add dynamic uplink clients
    for ((i=0; i<NUM_UPLINKS; i++)); do
        cat <<EOF >> clients.conf
# Allow connections from uplink $((i+1)) subnet
client uplink$((i+1)) {
 ipaddr = ${LAN_SUBNETS[i]}
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
    echo "✅ Multi-WAN Network Setup Complete!"
    echo ""
    echo "==============================================================="
    echo "                    CONFIGURATION SUMMARY"
    echo "==============================================================="
    
    for ((i=0; i<NUM_UPLINKS; i++)); do
        echo "| UPLINK $((i+1)) (${INTERFACES[i]}):"
        echo "|   Interface IP:     ${LAN_IPS[i]}"
        echo "|   Network Subnet:   ${LAN_SUBNETS[i]}"
        echo "|   DHCP Server IP:   ${LAN_IPS[i]}"
        echo "|   RADIUS Server IP: ${LAN_IPS[i]}"
        echo "|____________________________________________________________"
    done
    
    echo ""
    echo "🐳 Docker Containers Started:"
    echo "   • frr_multi (FRR Routing - $NUM_UPLINKS interfaces)"
    echo "   • dhcpd_multi (DHCP Server)"
    echo "   • radiusd_multi (RADIUS Server)"
    echo ""
    echo "🔧 Services Configured:"
    echo "   • NAT and IP Forwarding enabled"
    echo "   • OSPF routing for all $NUM_UPLINKS uplinks"
    echo "   • Static IP addresses assigned"
    echo ""
    echo "ℹ️  Use multi_wan_cleanup.sh to remove all configuration when done"
}

# ===============================================================
#                         MAIN EXECUTION
# ===============================================================

echo "🔍 Starting Multi-WAN Network configuration process..."
echo ""

# Prompt for number of uplinks
prompt_uplink_count

# Prompt for interface details
prompt_interface_details

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

echo "🎉 Multi-WAN Network setup completed successfully!"
