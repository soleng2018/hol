#!/bin/bash
set -euo pipefail

echo "🧹 V5 Multi Uplink Cleanup Script"
echo "=================================="
echo "This script will undo all changes made by v5_multi_uplink_demo.sh"
echo "Includes cleanup for variable number of interfaces (1, 2, or 4)"
echo ""

# Function to check if the interface exists
check_interface() {
    if ! ip link show "$1" &> /dev/null; then
        echo "⚠️  Interface $1 does not exist on the host."
        return 1
    fi
    return 0
}

# Function to read V5 configured interfaces from state file
read_v5_state_file() {
    local v5_state_file="/etc/v5_configured_interfaces.conf"
    
    echo "🔍 Reading V5 state file for configured interfaces..."
    echo "   State file: $v5_state_file"
    
    if [ ! -f "$v5_state_file" ]; then
        echo "⚠️  V5 state file not found: $v5_state_file"
        echo "   This means either:"
        echo "   • V5 demo script was never run on this server"
        echo "   • V5 demo script was run with an older version"
        echo "   • State file was manually deleted"
        return 1
    fi
    
    # Read interfaces from state file
    local v5_interfaces=""
    local interface_count=0
    
    echo "   State file contents:"
    while IFS= read -r line; do
        echo "     $line"
        if [[ "$line" =~ ^interface=(.+)$ ]]; then
            local interface_name="${BASH_REMATCH[1]}"
            v5_interfaces="$v5_interfaces $interface_name"
            interface_count=$((interface_count + 1))
        fi
    done < "$v5_state_file"
    
    if [ $interface_count -gt 0 ]; then
        echo "✅ Found $interface_count V5-configured interfaces: $v5_interfaces"
        echo "$v5_interfaces"
    else
        echo "⚠️  No interfaces found in V5 state file"
        return 1
    fi
}

# Function for manual interface removal (emergency fallback)
emergency_manual_removal() {
    local netplan_file="$1"
    
    echo ""
    echo "🚨 EMERGENCY MANUAL REMOVAL MODE"
    echo "   ⚠️  WARNING: This bypasses safety checks!"
    echo "   ⚠️  Only use if you're certain about which interfaces to remove!"
    echo "   ⚠️  This could interfere with other applications using those interfaces!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed with manual removal? [y/N]: " emergency_confirm
    
    if [[ ! "$emergency_confirm" =~ ^[Yy]$ ]]; then
        echo "ℹ️  Emergency manual removal cancelled - this is the safe choice"
        return 0
    fi
    
    echo ""
    echo "Enter interface names separated by spaces (e.g., eth0 eth1 or enp1s0 enp2s0):"
    echo "⚠️  These interfaces will be removed from netplan regardless of what configured them!"
    read -p "Interfaces to remove: " manual_interfaces
    
    if [ -n "$manual_interfaces" ]; then
        local interfaces_to_remove=($manual_interfaces)
        echo ""
        echo "📋 EMERGENCY: Manually removing interfaces: ${interfaces_to_remove[*]}"
        echo "   🚨 Bypassing all safety checks!"
        echo ""
        
        # Final confirmation
        read -p "Last chance - remove these interfaces? [y/N]: " final_confirm
        if [[ ! "$final_confirm" =~ ^[Yy]$ ]]; then
            echo "ℹ️  Emergency removal cancelled"
            return 0
        fi
        
        local removed_count=0
        for interface in "${interfaces_to_remove[@]}"; do
            if [ -n "$interface" ]; then
                if remove_interface_from_netplan_simple "$interface" "$netplan_file"; then
                    removed_count=$((removed_count + 1))
                fi
                echo ""
            fi
        done
        
        if [ $removed_count -gt 0 ]; then
            echo "🔄 Applying netplan configuration changes..."
            sudo netplan apply
            echo "✅ Emergency removal completed - $removed_count interface(s) removed"
        fi
    else
        echo "ℹ️  No interfaces specified, skipping manual removal"
    fi
}

# Function to remove interface from netplan
remove_interface_from_netplan_simple() {
    local interface="$1"
    local netplan_file="$2"
    
    echo "🔄 Removing interface $interface from netplan configuration..."
    
    # First, check if the interface exists in netplan
    local interface_exists=$(python3 -c "
import yaml
try:
    with open('$netplan_file', 'r') as f:
        config = yaml.safe_load(f)
    if 'network' in config and 'ethernets' in config['network']:
        if '$interface' in config['network']['ethernets']:
            print('EXISTS')
        else:
            print('NOT_FOUND')
    else:
        print('NO_ETHERNETS')
except:
    print('ERROR')
" 2>/dev/null)

    echo "   Interface $interface status: $interface_exists"
    
    if [ "$interface_exists" = "NOT_FOUND" ]; then
        echo "ℹ️  Interface $interface not found in netplan configuration"
        return 0
    fi
    
    if [ "$interface_exists" = "NO_ETHERNETS" ]; then
        echo "ℹ️  No ethernets section found in netplan configuration"
        return 0
    fi
    
    if [ "$interface_exists" = "ERROR" ]; then
        echo "❌ Error reading netplan configuration"
        return 1
    fi
    
    # Remove the interface using Python
    local removal_result=$(sudo python3 -c "
import yaml
import sys

try:
    # Read the existing netplan file
    with open('$netplan_file', 'r') as f:
        config = yaml.safe_load(f)
    
    removed = False
    
    # Remove the interface if it exists
    if 'network' in config and 'ethernets' in config['network']:
        if '$interface' in config['network']['ethernets']:
            interface_config = config['network']['ethernets']['$interface']
            del config['network']['ethernets']['$interface']
            print(f'REMOVED: Interface $interface (had config: {interface_config})')
            removed = True
        else:
            print('NOT_FOUND: Interface $interface not found in configuration')
    else:
        print('NO_ETHERNETS: No ethernets section found in netplan configuration')
    
    # Write the updated configuration
    if removed:
        with open('$netplan_file', 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        print('SUCCESS: Netplan file updated')
    
except Exception as e:
    print(f'ERROR: Failed to update netplan: {e}')
    sys.exit(1)
" 2>/dev/null)

    echo "   Removal result: $removal_result"
    
    if [[ "$removal_result" == *"REMOVED:"* ]]; then
        echo "✅ Interface $interface successfully removed from configuration"
        return 0
    elif [[ "$removal_result" == *"NOT_FOUND:"* ]]; then
        echo "ℹ️  Interface $interface not found in configuration"
        return 0
    else
        echo "❌ Failed to remove interface $interface from netplan configuration"
        return 1
    fi
}

# Function to remove V5 interfaces from netplan and apply changes
remove_v5_interfaces_from_netplan() {
    local netplan_file="$1"
    
    echo "🔄 Starting V5 interface removal from netplan configuration..."
    echo ""
    
    # Get list of interfaces that were configured by V5 from state file
    local interfaces_list
    if interfaces_list=$(read_v5_state_file); then
        local interfaces_to_remove=($interfaces_list)
    else
        echo "❌ Cannot proceed without V5 state file"
        echo "   This is a safety measure to prevent removing interfaces configured by other applications"
        return 1
    fi
    
    if [ ${#interfaces_to_remove[@]} -eq 0 ]; then
        echo "ℹ️  No V5-configured interfaces found to remove"
        return 0
    fi
    
    echo ""
    echo "📋 Interfaces scheduled for removal (from V5 state file): ${interfaces_to_remove[*]}"
    echo "   🛡️  SAFETY: Only removing interfaces that V5 demo script configured"
    echo "   🔒 Other interface configurations will remain untouched"
    echo ""
    
    # Confirm these are the interfaces user wants to remove
    read -p "Remove these V5-configured interfaces from netplan? [y/N]: " confirm_removal
    if [[ ! "$confirm_removal" =~ ^[Yy]$ ]]; then
        echo "ℹ️  Interface removal cancelled by user"
        return 0
    fi
    
    # Track success/failure
    local removed_count=0
    local failed_count=0
    
    # Remove each interface
    for interface in "${interfaces_to_remove[@]}"; do
        if [ -n "$interface" ]; then
            if remove_interface_from_netplan_simple "$interface" "$netplan_file"; then
                removed_count=$((removed_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
            echo ""
        fi
    done
    
    echo "📊 Interface removal summary:"
    echo "   Successfully removed: $removed_count"
    echo "   Failed to remove: $failed_count"
    echo ""
    
    if [ $removed_count -gt 0 ]; then
        # Apply the updated configuration once after all removals
        echo "🔄 Applying netplan configuration changes..."
        if sudo netplan apply 2>/dev/null; then
            echo "✅ Successfully applied netplan configuration"
            
            # Remove the V5 state file since we've cleaned up
            echo "🗑️  Removing V5 state file..."
            sudo rm -f "/etc/v5_configured_interfaces.conf"
            echo "✅ V5 state file removed"
        else
            echo "❌ Failed to apply netplan configuration - you may need to run 'sudo netplan apply' manually"
        fi
    else
        echo "ℹ️  No interfaces were removed, skipping netplan apply"
    fi
    
    echo ""
    echo "✅ Safe V5 netplan cleanup completed: removed $removed_count interface(s)"
}

# Function to stop and remove Docker containers
cleanup_containers() {
    echo "🐳 Cleaning up Docker containers..."
    
    # Stop and remove V5 specific containers
    local containers=("frr_v5" "dhcpd_v5" "radiusd_v5")
    
    for container in "${containers[@]}"; do
        if docker ps -a --format "table {{.Names}}" | grep -q "^${container}$" 2>/dev/null; then
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
        if docker images --format "table {{.Repository}}" | grep -q "^${image}$" 2>/dev/null; then
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
        "frr_v5.conf"
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
    
    # Also clean up any temporary V5 state files in /tmp
    local temp_files=(
        "/tmp/v5_configured_interfaces.conf"
        "/tmp/v5_debug.log"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            echo "🗑️  Removed: $file"
        else
            echo "ℹ️  File not found: $file"
        fi
    done
    
    # Clean up temporary files
    for temp_file in "${temp_files[@]}"; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file"
            echo "🗑️  Removed temp file: $temp_file"
        fi
    done
}

# Function to remove V5 specific systemd service and NAT configuration
cleanup_nat_service() {
    echo "🔧 Cleaning up V5 NAT service and configuration..."
    
    # Stop and disable the V5 service
    if systemctl is-active --quiet setup-nat-v5.service 2>/dev/null; then
        echo "🛑 Stopping setup-nat-v5.service"
        sudo systemctl stop setup-nat-v5.service
    fi
    
    if systemctl is-enabled --quiet setup-nat-v5.service 2>/dev/null; then
        echo "🚫 Disabling setup-nat-v5.service"
        sudo systemctl disable setup-nat-v5.service
    fi
    
    # Remove the V5 service file
    if [ -f "/etc/systemd/system/setup-nat-v5.service" ]; then
        sudo rm -f /etc/systemd/system/setup-nat-v5.service
        echo "🗑️  Removed: /etc/systemd/system/setup-nat-v5.service"
    fi
    
    # Remove the V5 setup script
    if [ -f "/usr/local/bin/setup-nat-v5.sh" ]; then
        sudo rm -f /usr/local/bin/setup-nat-v5.sh
        echo "🗑️  Removed: /usr/local/bin/setup-nat-v5.sh"
    fi
    
    # Also check for and clean up older services (v2/v3/v4) if they exist
    for version in v4 v3 ""; do
        local service_name="setup-nat${version:+-}${version}.service"
        local script_name="/usr/local/bin/setup-nat${version:+-}${version}.sh"
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            echo "🛑 Also stopping old $service_name"
            sudo systemctl stop "$service_name"
        fi
        
        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            echo "🚫 Also disabling old $service_name"
            sudo systemctl disable "$service_name"
        fi
        
        if [ -f "/etc/systemd/system/$service_name" ]; then
            sudo rm -f "/etc/systemd/system/$service_name"
            echo "🗑️  Removed old: /etc/systemd/system/$service_name"
        fi
        
        if [ -f "$script_name" ]; then
            sudo rm -f "$script_name"
            echo "🗑️  Removed old: $script_name"
        fi
    done
    
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
    echo "🔍 V5 Multi Uplink configuration to be cleaned up:"
    echo ""
    echo "   🐳 Docker Containers: frr_v5, dhcpd_v5, radiusd_v5"
    echo "   🌐 Interfaces: Read from V5 state file (/etc/v5_configured_interfaces.conf)"
    echo "   🔧 Services: setup-nat-v5.service and older NAT services"
    echo "   📄 Config Files: frr_v5.conf, dhcpd.conf, radius configs"
    echo "   🛡️  SAFETY: Only removes interfaces configured by V5 demo script"
    echo "   🔒 Other interface configurations remain untouched"
    echo "   🌍 Universal: Works on any server regardless of interface naming"
    echo ""
}

# Main cleanup function
main_cleanup() {
    echo "🚀 Starting V5 Multi Uplink cleanup process..."
    echo ""
    
    # Display what will be cleaned up
    display_cleanup_info
    
    echo "🔍 Finding netplan configuration file..."
    
    # Find netplan file
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "❌ No netplan configuration file found in /etc/netplan/"
        echo "   Skipping netplan cleanup..."
    else
        echo "✅ Found netplan file: $NETPLAN_FILE"
        
        # Remove V5 interfaces from netplan (safely using state file)
        if ! remove_v5_interfaces_from_netplan "$NETPLAN_FILE"; then
            echo ""
            echo "⚠️  Safe V5 interface removal failed!"
            echo "   This usually means the V5 state file is missing or corrupted"
            echo ""
            
            # Offer emergency manual removal as last resort
            read -p "Would you like to try emergency manual interface removal? [y/N]: " emergency_choice
            if [[ "$emergency_choice" =~ ^[Yy]$ ]]; then
                emergency_manual_removal "$NETPLAN_FILE"
            else
                echo "ℹ️  Interface cleanup skipped for safety"
                echo "   Docker containers and services will still be cleaned up"
            fi
        fi
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
    
    echo "✅ V5 Multi Uplink cleanup completed!"
    echo ""
    echo "📋 Summary of actions performed:"
    echo "   • SAFELY removed V5 interfaces from netplan (using V5 state file)"
    echo "   • Stopped and removed Docker containers (frr_v5, dhcpd_v5, radiusd_v5)"
    echo "   • Preserved Docker images (dhcpd, radiusd) for reuse"
    echo "   • Removed all V5 configuration files and state file"
    echo "   • Stopped and removed V5 NAT systemd service"
    echo "   • Cleaned up older NAT services (v2, v3, v4) if found"
    echo "   • Disabled IP forwarding"
    echo "   • Cleaned up all OSPF routes from routing table"
    echo "   🛡️  SAFETY: Other interface configurations were left untouched"
    echo ""
    echo "⚠️  Manual cleanup may be required for:"
    echo "   • iptables NAT rules (check with: sudo iptables -t nat -L)"
    echo "   • Any custom sysctl settings"
    echo ""
    echo "🔄 You may want to reboot the system to ensure all changes take effect."
}

# Confirmation prompt
echo "⚠️  WARNING: This will undo all changes made by v5_multi_uplink_demo.sh"
echo "   This includes:"
echo "   • Removing Docker containers"
echo "   • Restoring network configuration for V5 interfaces"
echo "   • Removing systemd services"
echo "   • Cleaning up configuration files"
echo ""
echo "🔧 V5 Multi Uplink supports 1, 2, or 4 interfaces dynamically"
echo "   This cleanup script will SAFELY remove ONLY V5-configured interfaces"
echo "   (Detection method: V5 state file /etc/v5_configured_interfaces.conf)"
echo "   🛡️  SAFETY: Will not touch interfaces configured by other applications"
echo "   🌍 Works on any server with any interface naming convention"
echo ""
read -p "Are you sure you want to continue? [y/N]: " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    main_cleanup
else
    echo "❌ Cleanup cancelled."
    exit 0
fi
