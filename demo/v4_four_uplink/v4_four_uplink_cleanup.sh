#!/bin/bash
set -euo pipefail

echo "🧹 V4 Four Uplink Cleanup Script"
echo "================================="
echo "This script will undo all changes made by v4_four_uplink_demo.sh"
echo "Includes cleanup for FOUR interface configuration"
echo ""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMS_FILE="$SCRIPT_DIR/parameters.txt"

# Function to check if the interface exists
check_interface() {
    if ! ip link show "$1" &> /dev/null; then
        echo "⚠️  Interface $1 does not exist on the host."
        return 1
    fi
    return 0
}

# Function to parse parameters.txt file
parse_parameters() {
    echo "📄 Reading parameters from: $PARAMS_FILE"
    
    if [ ! -f "$PARAMS_FILE" ]; then
        echo "⚠️  Parameters file not found: $PARAMS_FILE"
        echo "   Will try to clean up with default interface names"
        return 1
    fi
    
    # Read and parse parameters using source
    # Remove quotes when parsing
    eval "$(grep -E '^uplink[1-4]_' "$PARAMS_FILE" | sed 's/"//g')" 2>/dev/null || true
    
    return 0
}

# Function to remove interface from netplan
remove_interface_from_netplan_simple() {
    local interface="$1"
    local netplan_file="$2"
    
    echo "🔄 Removing interface $interface from netplan configuration..."
    
    # Use Python to remove the interface from netplan
    sudo python3 -c "
import yaml
import sys

try:
    # Read the existing netplan file
    with open('$netplan_file', 'r') as f:
        config = yaml.safe_load(f)
    
    # Remove the interface if it exists
    if 'network' in config and 'ethernets' in config['network']:
        if '$interface' in config['network']['ethernets']:
            del config['network']['ethernets']['$interface']
            print('✅ Interface $interface removed from configuration')
        else:
            print('ℹ️  Interface $interface not found in configuration')
    else:
        print('ℹ️  No ethernets section found in netplan configuration')
    
    # Write the updated configuration
    with open('$netplan_file', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    print('✅ Netplan configuration updated successfully')
    
except Exception as e:
    print(f'❌ Error updating netplan: {e}')
    sys.exit(1)
" || {
    echo "❌ Failed to remove interface from netplan configuration"
    return 1
}
}

# Function to remove all four interfaces from netplan and apply changes
remove_four_interfaces_from_netplan() {
    local netplan_file="$1"
    
    echo "🔄 Removing ALL FOUR interfaces from netplan configuration..."
    
    # Try to get interface names from parameters
    local interfaces_to_remove=()
    
    if parse_parameters; then
        # Use interfaces from parameters.txt
        for i in {1..4}; do
            local interface_var="uplink${i}_interface"
            if [ -n "${!interface_var:-}" ]; then
                interfaces_to_remove+=("${!interface_var}")
                echo "   Found interface from parameters: ${!interface_var}"
            fi
        done
    fi
    
    # If no interfaces found in parameters, use defaults
    if [ ${#interfaces_to_remove[@]} -eq 0 ]; then
        echo "   Using default interface names (eth0, eth1, eth2, eth3)"
        interfaces_to_remove=("eth0" "eth1" "eth2" "eth3")
    fi
    
    # Remove each interface
    for interface in "${interfaces_to_remove[@]}"; do
        remove_interface_from_netplan_simple "$interface" "$netplan_file"
    done
    
    # Apply the updated configuration once after all removals
    sudo netplan apply
    echo "✅ Applied updated netplan configuration for all four interfaces"
}

# Function to stop and remove Docker containers
cleanup_containers() {
    echo "🐳 Cleaning up Docker containers..."
    
    # Stop and remove V4 specific containers
    local containers=("frr_a" "dhcpd_a" "radiusd_a")
    
    for container in "${containers[@]}"; do
        if docker ps -a --format "table {{.Names}}" | grep -q "^${container}$"; then
            echo "🛑 Stopping and removing container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
            echo "✅ Removed container: $container"
        else
            echo "ℹ️  Container $container not found"
        fi
    done
}

# Function to check Docker images (but not remove them)
check_images() {
    echo "🖼️  Checking Docker images (keeping them for reuse)..."
    
    local images=("dhcpd" "radiusd")
    
    for image in "${images[@]}"; do
        if docker images --format "table {{.Repository}}" | grep -q "^${image}$"; then
            echo "✅ Image $image found (keeping for reuse)"
        else
            echo "ℹ️  Image $image not found"
        fi
    done
    
    echo "ℹ️  Docker images are preserved for future use"
}

# Function to remove configuration files
cleanup_config_files() {
    echo "📄 Cleaning up configuration files..."
    
    local config_files=(
        "frr_a.conf"
        "daemons"
        "dhcpdContainerfile"
        "dhcpdStartup.sh"
        "dhcpd.conf"
        "clients.conf"
        "authorize"
        "dictionary.nile"
        "default"
        "radiusdContainerfile"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            echo "🗑️  Removed: $file"
        else
            echo "ℹ️  File not found: $file"
        fi
    done
}

# Function to remove V4 specific systemd service and NAT configuration
cleanup_nat_service() {
    echo "🔧 Cleaning up V4 NAT service and configuration..."
    
    # Stop and disable the V4 service
    if systemctl is-active --quiet setup-nat-v4.service 2>/dev/null; then
        echo "🛑 Stopping setup-nat-v4.service"
        sudo systemctl stop setup-nat-v4.service
    fi
    
    if systemctl is-enabled --quiet setup-nat-v4.service 2>/dev/null; then
        echo "🚫 Disabling setup-nat-v4.service"
        sudo systemctl disable setup-nat-v4.service
    fi
    
    # Remove the V4 service file
    if [ -f "/etc/systemd/system/setup-nat-v4.service" ]; then
        sudo rm -f /etc/systemd/system/setup-nat-v4.service
        echo "🗑️  Removed: /etc/systemd/system/setup-nat-v4.service"
    fi
    
    # Remove the V4 setup script
    if [ -f "/usr/local/bin/setup-nat-v4.sh" ]; then
        sudo rm -f /usr/local/bin/setup-nat-v4.sh
        echo "🗑️  Removed: /usr/local/bin/setup-nat-v4.sh"
    fi
    
    # Also check for and clean up older services (v2/v3) if they exist
    if systemctl is-active --quiet setup-nat-v3.service 2>/dev/null; then
        echo "🛑 Also stopping old setup-nat-v3.service"
        sudo systemctl stop setup-nat-v3.service
    fi
    
    if systemctl is-enabled --quiet setup-nat-v3.service 2>/dev/null; then
        echo "🚫 Also disabling old setup-nat-v3.service"
        sudo systemctl disable setup-nat-v3.service
    fi
    
    if [ -f "/etc/systemd/system/setup-nat-v3.service" ]; then
        sudo rm -f /etc/systemd/system/setup-nat-v3.service
        echo "🗑️  Removed old: /etc/systemd/system/setup-nat-v3.service"
    fi
    
    if [ -f "/usr/local/bin/setup-nat-v3.sh" ]; then
        sudo rm -f /usr/local/bin/setup-nat-v3.sh
        echo "🗑️  Removed old: /usr/local/bin/setup-nat-v3.sh"
    fi
    
    if systemctl is-active --quiet setup-nat.service 2>/dev/null; then
        echo "🛑 Also stopping old setup-nat.service (v2)"
        sudo systemctl stop setup-nat.service
    fi
    
    if systemctl is-enabled --quiet setup-nat.service 2>/dev/null; then
        echo "🚫 Also disabling old setup-nat.service (v2)"
        sudo systemctl disable setup-nat.service
    fi
    
    if [ -f "/etc/systemd/system/setup-nat.service" ]; then
        sudo rm -f /etc/systemd/system/setup-nat.service
        echo "🗑️  Removed old: /etc/systemd/system/setup-nat.service"
    fi
    
    if [ -f "/usr/local/bin/setup-nat.sh" ]; then
        sudo rm -f /usr/local/bin/setup-nat.sh
        echo "🗑️  Removed old: /usr/local/bin/setup-nat.sh"
    fi
    
    # Reload systemd
    sudo systemctl daemon-reload
    echo "🔄 Reloaded systemd daemon"
    
    # Remove iptables rules (this is tricky, so we'll provide instructions)
    echo "⚠️  Note: You may need to manually remove iptables NAT rules if they were added"
    echo "   Check with: sudo iptables -t nat -L"
    echo "   Remove with: sudo iptables -t nat -D POSTROUTING -o <interface> -j MASQUERADE"
}

# Function to reset IP forwarding
reset_ip_forwarding() {
    echo "🌐 Resetting IP forwarding..."
    
    # Disable IP forwarding
    echo "0" | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    echo "✅ Disabled IP forwarding"
    
    # Remove from sysctl.conf if it was added
    if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "⚠️  Found net.ipv4.ip_forward=1 in /etc/sysctl.conf"
        echo "   You may want to remove this line manually if it wasn't there originally"
    fi
}

# Function to clean up OSPF routes
cleanup_ospf_routes() {
    echo "🗺️  Cleaning up OSPF routes..."
    
    # Get OSPF routes and remove them individually
    OSPF_ROUTES_LIST=$(ip route show proto ospf 2>/dev/null)
    
    if [ -n "$OSPF_ROUTES_LIST" ]; then
        ROUTE_COUNT=$(echo "$OSPF_ROUTES_LIST" | wc -l)
        echo "   Found $ROUTE_COUNT OSPF routes to remove"
        
        # Show the routes that will be removed
        echo "   OSPF routes to be removed:"
        echo "$OSPF_ROUTES_LIST" | sed 's/^/      /'
        
        # Remove each OSPF route individually
        echo "   Removing routes individually..."
        REMOVED_COUNT=0
        while IFS= read -r route_line; do
            if [ -n "$route_line" ]; then
                # Extract just the destination network from the route line
                DEST_NETWORK=$(echo "$route_line" | awk '{print $1}')
                if [ -n "$DEST_NETWORK" ]; then
                    echo "      Removing: $DEST_NETWORK"
                    if sudo ip route del "$DEST_NETWORK" 2>/dev/null; then
                        echo "      ✅ Successfully removed: $DEST_NETWORK"
                        REMOVED_COUNT=$((REMOVED_COUNT + 1))
                    else
                        echo "      ⚠️  Failed to remove: $DEST_NETWORK"
                    fi
                fi
            fi
        done <<< "$OSPF_ROUTES_LIST"
        
        echo "✅ Removed $REMOVED_COUNT OSPF routes from routing table"
        
        # Verify cleanup
        REMAINING_OSPF=$(ip route show proto ospf 2>/dev/null | wc -l)
        if [ "$REMAINING_OSPF" -eq 0 ]; then
            echo "✅ Verified: All OSPF routes successfully removed"
        else
            echo "⚠️  Warning: $REMAINING_OSPF OSPF routes still remain"
            echo "   Remaining routes:"
            ip route show proto ospf | sed 's/^/      /'
        fi
    else
        echo "ℹ️  No OSPF routes found in routing table"
    fi
}

# Function to display configuration being cleaned up
display_cleanup_info() {
    echo "🔍 Configuration to be cleaned up:"
    echo ""
    
    # Try to parse parameters
    if parse_parameters; then
        for i in {1..4}; do
            local interface_var="uplink${i}_interface"
            local lan_ip_var="uplink${i}_lan_ip"
            local lan_subnet_var="uplink${i}_lan_subnet"
            
            if [ -n "${!interface_var:-}" ]; then
                echo "   🔗 UPLINK $i:"
                echo "      Interface:   ${!interface_var}"
                echo "      LAN IP:      ${!lan_ip_var:-N/A}"
                echo "      LAN Subnet:  ${!lan_subnet_var:-N/A}"
            fi
        done
    else
        echo "   Using default interfaces: eth0, eth1, eth2, eth3"
    fi
    
    echo ""
}

# Main cleanup function
main_cleanup() {
    echo "🚀 Starting FOUR interface cleanup process..."
    echo ""
    
    # Display what will be cleaned up
    display_cleanup_info
    
    # Check if interfaces exist
    echo ""
    echo "🔍 Checking interfaces..."
    
    local interfaces_to_check=()
    
    # Try to get interface names from parameters
    if parse_parameters; then
        for i in {1..4}; do
            local interface_var="uplink${i}_interface"
            if [ -n "${!interface_var:-}" ]; then
                interfaces_to_check+=("${!interface_var}")
            fi
        done
    else
        # Use default interfaces
        interfaces_to_check=("eth0" "eth1" "eth2" "eth3")
    fi
    
    for interface in "${interfaces_to_check[@]}"; do
        if ! check_interface "$interface"; then
            echo "⚠️  Interface $interface not found, but continuing with cleanup..."
        else
            echo "✅ Found interface: $interface"
        fi
    done
    
    echo ""
    echo "🔍 Finding netplan configuration file..."
    
    # Find netplan file
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "❌ No netplan configuration file found in /etc/netplan/"
        echo "   Skipping netplan cleanup..."
    else
        echo "✅ Found netplan file: $NETPLAN_FILE"
        
        # Remove all four interfaces from netplan
        remove_four_interfaces_from_netplan "$NETPLAN_FILE"
    fi
    
    echo ""
    
    # Clean up Docker containers
    cleanup_containers
    echo ""
    
    # Check Docker images (but keep them)
    check_images
    echo ""
    
    # Clean up configuration files
    cleanup_config_files
    echo ""
    
    # Clean up NAT service
    cleanup_nat_service
    echo ""
    
    # Reset IP forwarding
    reset_ip_forwarding
    echo ""
    
    # Clean up OSPF routes
    cleanup_ospf_routes
    echo ""
    
    echo "✅ FOUR interface cleanup completed!"
    echo ""
    echo "📋 Summary of actions performed:"
    echo "   • Removed ALL FOUR interfaces from netplan configuration"
    echo "   • Stopped and removed Docker containers (frr_a, dhcpd_a, radiusd_a)"
    echo "   • Preserved Docker images (dhcpd, radiusd) for reuse"
    echo "   • Removed all V4 configuration files"
    echo "   • Stopped and removed V4 NAT systemd service"
    echo "   • Disabled IP forwarding"
    echo "   • Cleaned up all OSPF routes from routing table"
    echo ""
    echo "⚠️  Manual cleanup may be required for:"
    echo "   • iptables NAT rules (check with: sudo iptables -t nat -L)"
    echo "   • Any custom sysctl settings"
    echo ""
    echo "🔄 You may want to reboot the system to ensure all changes take effect."
}

# Display interface information from parameters.txt if available
display_interface_info() {
    if parse_parameters; then
        echo "🔧 Configured interfaces to clean up (from parameters.txt):"
        for i in {1..4}; do
            local interface_var="uplink${i}_interface"
            local lan_ip_var="uplink${i}_lan_ip"
            
            if [ -n "${!interface_var:-}" ] && [ -n "${!lan_ip_var:-}" ]; then
                echo "   • Uplink $i: ${!interface_var} (${!lan_ip_var})"
            fi
        done
    else
        echo "🔧 Default interfaces to clean up:"
        echo "   • Uplink 1: eth0 (172.16.0.1/30)"
        echo "   • Uplink 2: eth1 (172.16.1.1/30)"
        echo "   • Uplink 3: eth2 (172.16.2.1/30)"
        echo "   • Uplink 4: eth3 (172.16.3.1/30)"
    fi
}

# Confirmation prompt
echo "⚠️  WARNING: This will undo all changes made by v4_four_uplink_demo.sh"
echo "   This includes:"
echo "   • Removing Docker containers"
echo "   • Restoring network configuration for ALL FOUR interfaces"
echo "   • Removing systemd services"
echo "   • Cleaning up configuration files"
echo ""

display_interface_info

echo ""
read -p "Are you sure you want to continue? [y/N]: " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    main_cleanup
else
    echo "❌ Cleanup cancelled."
    exit 0
fi
