#!/bin/bash
set -euo pipefail

echo "🧹 V2 Demo Cleanup Script"
echo "========================="
echo "This script will undo all changes made by v2_demo.sh"
echo "Includes cleanup for DUAL interface configuration"
echo ""

# Function to check if the interface exists
check_interface() {
    if ! ip link show "$1" &> /dev/null; then
        echo "⚠️  Interface $1 does not exist on the host."
        return 1
    fi
    return 0
}

# Function to remove interface from netplan (simple approach)
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

# Function to remove both interfaces from netplan and apply changes
remove_dual_interfaces_from_netplan() {
    local interface1="$1"
    local interface2="$2"
    local netplan_file="$3"
    
    echo "🔄 Removing BOTH interfaces from netplan configuration..."
    
    # Remove interface1
    remove_interface_from_netplan_simple "$interface1" "$netplan_file"
    
    # Remove interface2
    remove_interface_from_netplan_simple "$interface2" "$netplan_file"
    
    # Apply the updated configuration once after both removals
    sudo netplan apply
    echo "✅ Applied updated netplan configuration for both interfaces"
}

# Function to stop and remove Docker containers
cleanup_containers() {
    echo "🐳 Cleaning up Docker containers..."
    
    # Stop and remove containers
    local containers=("frr0" "dhcpd0" "radiusd0")
    
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
        "frr0.conf"
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

# Function to remove systemd service and NAT configuration
cleanup_nat_service() {
    echo "🔧 Cleaning up NAT service and configuration..."
    
    # Stop and disable the service
    if systemctl is-active --quiet setup-nat.service 2>/dev/null; then
        echo "🛑 Stopping setup-nat.service"
        sudo systemctl stop setup-nat.service
    fi
    
    if systemctl is-enabled --quiet setup-nat.service 2>/dev/null; then
        echo "🚫 Disabling setup-nat.service"
        sudo systemctl disable setup-nat.service
    fi
    
    # Remove the service file
    if [ -f "/etc/systemd/system/setup-nat.service" ]; then
        sudo rm -f /etc/systemd/system/setup-nat.service
        echo "🗑️  Removed: /etc/systemd/system/setup-nat.service"
    fi
    
    # Remove the setup script
    if [ -f "/usr/local/bin/setup-nat.sh" ]; then
        sudo rm -f /usr/local/bin/setup-nat.sh
        echo "🗑️  Removed: /usr/local/bin/setup-nat.sh"
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

# Main cleanup function
main_cleanup() {
    echo "🚀 Starting DUAL interface cleanup process..."
    echo ""
    
    # Prompt for both interface names with defaults from v2_demo.sh
    read -p "Enter the FIRST interface name that was configured [eno2np1]: " interface1
    interface1=${interface1:-eno2np1}
    
    read -p "Enter the SECOND interface name that was configured [eno1np0]: " interface2
    interface2=${interface2:-eno1np0}
    
    # Check if interfaces exist
    echo ""
    echo "🔍 Checking interfaces..."
    if ! check_interface "$interface1"; then
        echo "⚠️  Interface $interface1 not found, but continuing with cleanup..."
    else
        echo "✅ Found interface: $interface1"
    fi
    
    if ! check_interface "$interface2"; then
        echo "⚠️  Interface $interface2 not found, but continuing with cleanup..."
    else
        echo "✅ Found interface: $interface2"
    fi
    
    echo ""
    echo "🔍 Finding netplan configuration file..."
    
    # Find netplan file
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "❌ No netplan configuration file found in /etc/netplan/"
        echo "   Skipping netplan cleanup..."
    else
        echo "✅ Found netplan file: $NETPLAN_FILE"
        
        # Remove both interfaces from netplan
        remove_dual_interfaces_from_netplan "$interface1" "$interface2" "$NETPLAN_FILE"
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
    
    echo "✅ DUAL interface cleanup completed!"
    echo ""
    echo "📋 Summary of actions performed:"
    echo "   • Removed BOTH interfaces ($interface1, $interface2) from netplan configuration"
    echo "   • Stopped and removed Docker containers (frr0, dhcpd0, radiusd0)"
    echo "   • Preserved Docker images (dhcpd, radiusd) for reuse"
    echo "   • Removed all configuration files"
    echo "   • Stopped and removed NAT systemd service"
    echo "   • Disabled IP forwarding"
    echo "   • Cleaned up all OSPF routes from routing table"
    echo ""
    echo "⚠️  Manual cleanup may be required for:"
    echo "   • iptables NAT rules (check with: sudo iptables -t nat -L)"
    echo "   • Any custom sysctl settings"
    echo ""
    echo "🔄 You may want to reboot the system to ensure all changes take effect."
}

# Confirmation prompt
echo "⚠️  WARNING: This will undo all changes made by v2_demo.sh"
echo "   This includes:"
echo "   • Removing Docker containers"
echo "   • Restoring network configuration for BOTH interfaces"
echo "   • Removing systemd services"
echo "   • Cleaning up configuration files"
echo ""
echo "🔧 Configured interfaces to clean up:"
echo "   • First interface: eno2np1 (172.16.250.1/30)"
echo "   • Second interface: eno1np0 (172.16.250.5/30)"
echo ""
read -p "Are you sure you want to continue? [y/N]: " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    main_cleanup
else
    echo "❌ Cleanup cancelled."
    exit 0
fi
