#!/bin/bash
set -euo pipefail

# Global flags to track rollback state
ROLLBACK_NEEDED=false
NETPLAN_APPLIED=false

# Function to rollback changes if something fails
rollback_changes() {
    local exit_code=$?
    if [ "$ROLLBACK_NEEDED" = true ] && [ $exit_code -ne 0 ]; then
        echo ""
        echo "🚨 ERROR DETECTED - ROLLING BACK CHANGES"
        echo "========================================"
        
        if [ "$NETPLAN_APPLIED" = true ] && [ -n "${ACTIVE_INTERFACES:-}" ]; then
            echo "🔄 Rolling back netplan configuration..."
            
            # Find netplan file
            local netplan_file=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
            if [ -n "$netplan_file" ]; then
                # Remove the interfaces we configured
                for interface in "${ACTIVE_INTERFACES[@]:-}"; do
                    echo "   🗑️  Removing interface $interface from netplan..."
                    
                    # Remove interface using Python (same logic as cleanup script)
                    sudo python3 -c "
import yaml
import sys

try:
    with open('$netplan_file', 'r') as f:
        config = yaml.safe_load(f)
    
    if 'network' in config and 'ethernets' in config['network']:
        if '$interface' in config['network']['ethernets']:
            del config['network']['ethernets']['$interface']
            print('   ✅ Removed $interface from netplan')
        else:
            print('   ℹ️  Interface $interface not found in netplan')
    
    with open('$netplan_file', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

except Exception as e:
    print(f'   ❌ Error removing $interface: {e}')
" 2>/dev/null || echo "   ⚠️  Failed to remove $interface"
                done
                
                # Apply rollback
                echo "   🔄 Applying netplan rollback..."
                if sudo netplan apply 2>/dev/null; then
                    echo "   ✅ Successfully rolled back netplan configuration"
                else
                    echo "   ⚠️  Warning: Failed to apply netplan rollback automatically"
                    echo "   ℹ️  You may need to manually run 'sudo netplan apply'"
                fi
            else
                echo "   ⚠️  Could not find netplan file for rollback"
            fi
        fi
        
        # Clean up any temporary files
        local temp_state_file="/tmp/dynamicwan_configured_interfaces.conf"
        if [ -f "$temp_state_file" ]; then
            rm -f "$temp_state_file"
            echo "   🗑️  Cleaned up temporary state file"
        fi
        
        echo ""
        echo "❌ ROLLBACK COMPLETED"
        echo "   All network configuration changes have been reverted"
        echo "   System should be back to original state"
        echo ""
        exit 1
    fi
}

# Function to disable rollback when script completes successfully
disable_rollback() {
    ROLLBACK_NEEDED=false
    trap - ERR EXIT
}

# Trap to handle script failures and rollback
trap rollback_changes ERR EXIT

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

# Function to check if user has sudo access
check_sudo_access() {
    echo "🔐 Checking sudo access..."
    
    # Check if sudo is available and user can use it
    if ! command -v sudo &> /dev/null; then
        echo "❌ ERROR: sudo is not installed on this system"
        echo "   This script requires sudo access to configure network settings"
        exit 1
    fi
    
    # Test sudo access
    if ! sudo -n true 2>/dev/null; then
        echo "🔐 This script requires sudo privileges for network configuration"
        echo "   Please enter your password when prompted"
        
        # Prompt for password with timeout
        if ! sudo -v; then
            echo "❌ ERROR: Unable to obtain sudo privileges"
            echo "   This script requires sudo access to:"
            echo "   • Modify netplan configuration"
            echo "   • Create system services"
            echo "   • Configure iptables rules"
            echo "   • Write system state files"
            exit 1
        fi
        echo "✅ Sudo access confirmed"
    else
        echo "✅ Sudo access already available"
    fi
    
    # Keep sudo timestamp fresh for the duration of the script
    sudo -v
    echo "--------------------------------------------------------------"
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

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "🐳 Docker not found. Installing Docker..."
        install_docker
        handle_docker_permissions
    else
        echo "✅ Docker is available"
        handle_docker_permissions
    fi
    
    # Check if Docker daemon is running
    if ! sudo docker info &> /dev/null; then
        echo "🔄 Starting Docker daemon..."
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # Wait a moment for Docker to start
        sleep 3
        
        if ! sudo docker info &> /dev/null; then
            echo "❌ Failed to start Docker daemon"
            exit 1
        fi
        echo "✅ Docker daemon started successfully"
    else
        echo "✅ Docker daemon is running"
    fi
}

# Function to install Docker
install_docker() {
    echo "📦 Installing Docker..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index again
    sudo apt-get update
    
    # Install Docker
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker "$USER"
    
    echo "✅ Docker installed successfully"
    echo "ℹ️  Note: You may need to log out and back in for Docker group changes to take effect"
}

# Function to handle Docker permissions
handle_docker_permissions() {
    # Check if user is in docker group
    if ! groups "$USER" | grep -qw docker; then
        echo "👥 Adding user to docker group..."
        sudo usermod -aG docker "$USER"
        echo "✅ User added to docker group"
        echo "ℹ️  Note: Docker group changes require a new login session"
        echo "   For now, the script will use sudo for Docker commands"
    else
        echo "✅ User is already in docker group"
    fi
}

# Function to check and install essential packages
check_essential_packages() {
    echo "📦 Checking essential packages..."
    
    local packages=(
        "git"
        "openssh-server"
        "net-tools"
        "iproute2"
        "netplan.io"
        "isc-dhcp-server"
        "freeradius-utils"
        "curl"
        "wget"
        "iptables"
        "iptables-persistent"
    )
    
    local missing_packages=()
    
    # Check which packages are missing
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package "; then
            missing_packages+=("$package")
        fi
    done
    
    # Install missing packages
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "📥 Installing missing packages: ${missing_packages[*]}"
        sudo apt-get update
        sudo apt-get install -y "${missing_packages[@]}"
        echo "✅ Essential packages installed successfully"
    else
        echo "✅ All essential packages are available"
    fi
}

# Function to verify netplan configuration
verify_netplan() {
    echo "🔧 Verifying netplan configuration..."
    
    # Check if netplan is available
    if ! command -v netplan &> /dev/null; then
        echo "❌ netplan command not found"
        echo "   Installing netplan.io..."
        sudo apt-get install -y netplan.io
        if ! command -v netplan &> /dev/null; then
            echo "❌ Failed to install netplan"
            exit 1
        fi
    fi
    
    # Check if netplan directory exists
    if [ ! -d "/etc/netplan" ]; then
        echo "❌ /etc/netplan directory not found"
        echo "   Creating netplan directory..."
        sudo mkdir -p /etc/netplan
    fi
    
    # Check if there's at least one netplan file
    local netplan_files=($(ls /etc/netplan/*.yaml 2>/dev/null || true))
    if [ ${#netplan_files[@]} -eq 0 ]; then
        echo "⚠️  No netplan configuration files found in /etc/netplan/"
        echo "   Creating a basic netplan configuration..."
        
        # Create a basic netplan configuration
        sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    # Network interfaces will be configured here
EOF
        
        echo "✅ Created basic netplan configuration"
    fi
    
    echo "✅ Netplan configuration verified"
}

# Function to check and install dependencies
check_dependencies() {
    echo "🔍 Checking dependencies..."
    check_sudo_access
    check_essential_packages
    check_python3
    check_pyyaml
    check_docker
    verify_netplan
    echo "✅ All dependencies are available"
    echo "--------------------------------------------------------------"
}

# Function to validate subnet mask
validate_subnet_mask() {
    local ip_with_mask="$1"
    local param_name="$2"
    local uplink_num="$3"
    
    # Extract subnet mask
    if [[ "$ip_with_mask" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/([0-9]+)$ ]]; then
        local subnet_mask="${BASH_REMATCH[1]}"
        
        # Check if subnet mask is in valid range (1-32)
        if [ "$subnet_mask" -lt 1 ] || [ "$subnet_mask" -gt 32 ]; then
            echo "❌ ERROR: Invalid subnet mask /$subnet_mask in uplink $uplink_num"
            echo "   Parameter: $param_name = $ip_with_mask"
            echo "   Subnet mask must be between /1 and /32"
            echo "   Examples: /24 (254 hosts), /30 (2 hosts), /32 (1 host)"
            exit 1
        fi
        
        echo "✅ Valid /$subnet_mask subnet mask for $param_name"
    else
        echo "❌ ERROR: Invalid IP address format in uplink $uplink_num"
        echo "   Parameter: $param_name = $ip_with_mask"
        echo "   Expected format: x.x.x.x/y (e.g., 172.16.0.1/24, 172.16.0.1/30, 172.16.0.1/32)"
        exit 1
    fi
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
        
        # Validate subnet masks (must be /1 to /32)
        echo "🔍 Validating uplink $i subnet masks..."
        validate_subnet_mask "$lan_ip" "uplink${i}_lan_ip" "$i"
        validate_subnet_mask "$lan_subnet" "uplink${i}_lan_subnet" "$i"
        
        # Validate that lan_subnet matches the network portion of lan_ip
        local ip_addr=$(echo "$lan_ip" | cut -d'/' -f1)
        local ip_mask=$(echo "$lan_ip" | cut -d'/' -f2)
        local subnet_addr=$(echo "$lan_subnet" | cut -d'/' -f1)
        local subnet_mask=$(echo "$lan_subnet" | cut -d'/' -f2)
        
        # Ensure both have the same subnet mask
        if [ "$ip_mask" != "$subnet_mask" ]; then
            echo "❌ ERROR: Subnet mask mismatch in uplink $i"
            echo "   LAN IP: $lan_ip (mask: /$ip_mask)"
            echo "   LAN Subnet: $lan_subnet (mask: /$subnet_mask)"
            echo "   Both must use the same subnet mask"
            exit 1
        fi
        
        # Calculate network address from the lan_ip
        local ip_octets=($(echo "$ip_addr" | tr '.' ' '))
        local expected_network=""
        
        # Calculate subnet mask in decimal format
        local mask_bits=$ip_mask
        local mask_value=$((0xFFFFFFFF << (32 - mask_bits)))
        
        # Convert IP to 32-bit integer
        local ip_int=$(( (${ip_octets[0]} << 24) + (${ip_octets[1]} << 16) + (${ip_octets[2]} << 8) + ${ip_octets[3]} ))
        
        # Apply subnet mask to get network address
        local network_int=$((ip_int & mask_value))
        
        # Convert back to dotted decimal
        local net_octet1=$(((network_int >> 24) & 0xFF))
        local net_octet2=$(((network_int >> 16) & 0xFF))
        local net_octet3=$(((network_int >> 8) & 0xFF))
        local net_octet4=$((network_int & 0xFF))
        
        local expected_network="$net_octet1.$net_octet2.$net_octet3.$net_octet4"
        
        if [ "$subnet_addr" != "$expected_network" ]; then
            echo "❌ ERROR: LAN subnet does not match LAN IP network in uplink $i"
            echo "   LAN IP: $lan_ip"
            echo "   LAN Subnet: $lan_subnet"
            echo "   Expected LAN Subnet: $expected_network/$ip_mask"
            echo ""
            echo "   The LAN subnet must be the network address of the LAN IP's /$ip_mask subnet"
            exit 1
        fi
        
        echo "✅ LAN subnet matches LAN IP network (/$ip_mask)"
        
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
    local containerName="frr_dyn"
    
    sudo docker run -dt --name "$containerName" --network=host --privileged --restart=always \
    -v ./frr_dyn.conf:/etc/frr/frr.conf:Z \
    -v ./daemons:/etc/frr/daemons:Z  \
     docker.io/frrouting/frr

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run DHCPD container
create_dhcpd_container() {
    local containerName="dhcpd_dyn"
    
    sudo docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     dhcpd

    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run RADIUS container
create_radiusd_container() {
    local containerName="radiusd_dyn"
    
    sudo docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     radiusd
    
    echo "✅ Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to generate dynamic FRR config file
generate_frr_config() {
    local config_file="frr_dyn.conf"

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
    NETPLAN_APPLIED=true
    ROLLBACK_NEEDED=true
    
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

# Function to detect the best internet-facing interface automatically
detect_best_internet_interface() {
    echo "🔍 Automatically detecting best internet interface..."
    
    # Method 1: Use actual route taken (most reliable)
    local primary_interface=$(ip route get 8.8.8.8 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    
    if [ -n "$primary_interface" ]; then
        echo "✅ Primary interface via route lookup: $primary_interface"
        echo "$primary_interface"
        return 0
    fi
    
    # Method 2: Analyze all default routes by priority
    echo "🔍 Analyzing default routes by priority..."
    
    local best_interface=""
    local best_score=999999
    
    # Get all default routes
    while IFS= read -r route; do
        local interface=$(echo "$route" | awk '{print $5}')
        local metric=$(echo "$route" | awk '{print $7}')
        local gateway=$(echo "$route" | awk '{print $3}')
        
        # Skip if interface doesn't exist or is down
        if ! ip link show "$interface" &>/dev/null; then
            continue
        fi
        
        # Calculate priority score (lower = better)
        local score=0
        
        # 1. Metric-based scoring (most important)
        if [ -n "$metric" ] && [ "$metric" -gt 0 ]; then
            score=$((score + metric * 10))
        else
            score=$((score + 50))  # Default metric penalty
        fi
        
        # 2. Interface type scoring
        if [[ "$interface" =~ ^(eth|enp|ens|em) ]]; then
            score=$((score - 20))  # Wired = better
        elif [[ "$interface" =~ ^(wlan|wlp|wifi) ]]; then
            score=$((score + 30))  # Wireless = worse
        fi
        
        # 3. Interface state scoring
        if ip link show "$interface" | grep -q "state UP.*LOWER_UP"; then
            score=$((score - 10))  # Up with carrier = better
        else
            score=$((score + 50))  # Down = much worse
        fi
        
        # 4. Gateway reachability test (quick ping)
        if ping -c 1 -W 1 "$gateway" &>/dev/null; then
            score=$((score - 5))   # Reachable = better
        else
            score=$((score + 20))  # Unreachable = worse
        fi
        
        echo "  Interface: $interface, Gateway: $gateway, Metric: ${metric:-default}, Score: $score"
        
        # Keep track of best interface
        if [ "$score" -lt "$best_score" ]; then
            best_score=$score
            best_interface="$interface"
        fi
        
    done < <(ip route | grep '^default')
    
    if [ -n "$best_interface" ]; then
        echo "✅ Best interface selected: $best_interface (score: $best_score)"
        echo "$best_interface"
        return 0
    fi
    
    # Method 3: Fallback to first available
    local fallback=$(ip route | grep '^default' | awk '{print $5}' | head -1)
    if [ -n "$fallback" ]; then
        echo "⚠️  Using fallback interface: $fallback"
        echo "$fallback"
        return 0
    fi
    
    echo "❌ No suitable internet interface found"
    return 1
}

# Function to setup NAT and IP forwarding
setup_nat() {
    echo "🔧 Setting up NAT and IP forwarding..."
    
    # Detect the best internet-facing interface automatically
    echo "🔍 Detecting best internet-facing interface..."
    INTERNET_IFACE=$(detect_best_internet_interface)
    
    if [ -n "$INTERNET_IFACE" ]; then
        echo "✅ Selected interface: $INTERNET_IFACE"
        
        # Validate interface
        if ! ip link show "$INTERNET_IFACE" &>/dev/null; then
            echo "❌ Selected interface $INTERNET_IFACE does not exist"
            exit 1
        fi
        
        # Record internet interface in state file for cleanup tracking
        if [ -n "$DYNAMIC_WAN_STATE_FILE" ]; then
            echo "# Internet interface used for NAT" | sudo tee -a "$DYNAMIC_WAN_STATE_FILE" > /dev/null
            echo "internet_interface=$INTERNET_IFACE" | sudo tee -a "$DYNAMIC_WAN_STATE_FILE" > /dev/null
            echo "" | sudo tee -a "$DYNAMIC_WAN_STATE_FILE" > /dev/null
        fi
    else
        echo "❌ No suitable internet interface found."
        echo "   Please ensure you have internet connectivity before running this script."
        exit 1
    fi
    
    # Create setup-nat.sh dynamically
    sudo tee /usr/local/bin/setup-nat-dynamicwan.sh > /dev/null <<EOF
#!/bin/bash
set -euo pipefail

# Function to detect the best internet-facing interface automatically
detect_best_internet_interface() {
    echo "🔍 Automatically detecting best internet interface..." >&2
    
    # Method 1: Use actual route taken (most reliable)
    local primary_interface=\$(ip route get 8.8.8.8 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if(\$i=="dev") print \$(i+1)}')
    
    if [ -n "\$primary_interface" ]; then
        echo "✅ Primary interface via route lookup: \$primary_interface" >&2
        echo "\$primary_interface"
        return 0
    fi
    
    # Method 2: Analyze all default routes by priority
    echo "🔍 Analyzing default routes by priority..." >&2
    
    local best_interface=""
    local best_score=999999
    
    # Get all default routes
    while IFS= read -r route; do
        local interface=\$(echo "\$route" | awk '{print \$5}')
        local metric=\$(echo "\$route" | awk '{print \$7}')
        local gateway=\$(echo "\$route" | awk '{print \$3}')
        
        # Skip if interface doesn't exist or is down
        if ! ip link show "\$interface" &>/dev/null; then
            continue
        fi
        
        # Calculate priority score (lower = better)
        local score=0
        
        # 1. Metric-based scoring (most important)
        if [ -n "\$metric" ] && [ "\$metric" -gt 0 ]; then
            score=\$((score + metric * 10))
        else
            score=\$((score + 50))  # Default metric penalty
        fi
        
        # 2. Interface type scoring
        if [[ "\$interface" =~ ^(eth|enp|ens|em) ]]; then
            score=\$((score - 20))  # Wired = better
        elif [[ "\$interface" =~ ^(wlan|wlp|wifi) ]]; then
            score=\$((score + 30))  # Wireless = worse
        fi
        
        # 3. Interface state scoring
        if ip link show "\$interface" | grep -q "state UP.*LOWER_UP"; then
            score=\$((score - 10))  # Up with carrier = better
        else
            score=\$((score + 50))  # Down = much worse
        fi
        
        # 4. Gateway reachability test (quick ping)
        if ping -c 1 -W 1 "\$gateway" &>/dev/null; then
            score=\$((score - 5))   # Reachable = better
        else
            score=\$((score + 20))  # Unreachable = worse
        fi
        
        echo "  Interface: \$interface, Gateway: \$gateway, Metric: \${metric:-default}, Score: \$score" >&2
        
        # Keep track of best interface
        if [ "\$score" -lt "\$best_score" ]; then
            best_score=\$score
            best_interface="\$interface"
        fi
        
    done < <(ip route | grep '^default')
    
    if [ -n "\$best_interface" ]; then
        echo "✅ Best interface selected: \$best_interface (score: \$best_score)" >&2
        echo "\$best_interface"
        return 0
    fi
    
    # Method 3: Fallback to first available
    local fallback=\$(ip route | grep '^default' | awk '{print \$5}' | head -1)
    if [ -n "\$fallback" ]; then
        echo "⚠️  Using fallback interface: \$fallback" >&2
        echo "\$fallback"
        return 0
    fi
    
    echo "❌ No suitable internet interface found" >&2
    return 1
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
INTERNET_IFACE=\$(detect_best_internet_interface)
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
    sudo docker build -t dhcpd -f dhcpdContainerfile .
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
    sudo docker build -t radiusd -f radiusdContainerfile .
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
    echo "   • frr_dyn (FRR Routing - $NUM_ACTIVE_UPLINKS interfaces)"
    echo "   • dhcpd_dyn (DHCP Server)"
    echo "   • radiusd_dyn (RADIUS Server)"
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

# Disable rollback since everything completed successfully
disable_rollback

