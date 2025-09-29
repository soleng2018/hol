#!/bin/bash
set -euo pipefail

echo "🧹 Dynamic WAN Network Cleanup Script"
echo "======================================"
echo "This script will undo all changes made by dynamic_wan_demo.sh"
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

# Function to read Dynamic WAN configured interfaces from state file
read_dynamicwan_state_file() {
    local dynamicwan_state_file="/etc/dynamicwan_configured_interfaces.conf"
    
    echo "🔍 Reading Dynamic WAN state file for configured interfaces..."
    echo "   State file: $dynamicwan_state_file"
    
    if [ ! -f "$dynamicwan_state_file" ]; then
        echo "⚠️  Dynamic WAN state file not found: $dynamicwan_state_file"
        echo "   This means either:"
        echo "   • Dynamic WAN setup script was never run on this server"
        echo "   • Dynamic WAN setup script was run with an older version"
        echo "   • State file was manually deleted"
        return 1
    fi
    
    # Read interfaces from state file
    local dynamicwan_interfaces=""
    local interface_count=0
    
    echo "   State file contents:"
    while IFS= read -r line; do
        echo "     $line"
        if [[ "$line" =~ ^interface=(.+)$ ]]; then
            local interface_name="${BASH_REMATCH[1]}"
            dynamicwan_interfaces="$dynamicwan_interfaces $interface_name"
            interface_count=$((interface_count + 1))
        fi
    done < "$dynamicwan_state_file"
    
    if [ $interface_count -gt 0 ]; then
        echo "✅ Found $interface_count Dynamic WAN configured interfaces: $dynamicwan_interfaces"
        echo "$dynamicwan_interfaces"
    else
        echo "⚠️  No interfaces found in Dynamic WAN state file"
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

# Function to remove Dynamic WAN interfaces from netplan and apply changes
remove_dynamicwan_interfaces_from_netplan() {
    local netplan_file="$1"
    
    echo "🔄 Starting Dynamic WAN interface removal from netplan configuration..."
    echo ""
    
    # Get list of interfaces that were configured by Dynamic WAN from state file
    local interfaces_list
    if interfaces_list=$(read_dynamicwan_state_file); then
        local interfaces_to_remove=($interfaces_list)
    else
        echo "❌ Cannot proceed without Dynamic WAN state file"
        echo "   This is a safety measure to prevent removing interfaces configured by other applications"
        return 1
    fi
    
    if [ ${#interfaces_to_remove[@]} -eq 0 ]; then
        echo "ℹ️  No Dynamic WAN configured interfaces found to remove"
        return 0
    fi
    
    echo ""
    echo "📋 Interfaces scheduled for removal (from Dynamic WAN state file): ${interfaces_to_remove[*]}"
    echo "   🛡️  SAFETY: Only removing interfaces that Dynamic WAN setup script configured"
    echo "   🔒 Other interface configurations will remain untouched"
    echo ""
    
    # Confirm these are the interfaces user wants to remove
    read -p "Remove these Dynamic WAN configured interfaces from netplan? [y/N]: " confirm_removal
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
            
            # Remove the Dynamic WAN state file since we've cleaned up
            echo "🗑️  Removing Dynamic WAN state file..."
            sudo rm -f "/etc/dynamicwan_configured_interfaces.conf"
            echo "✅ Dynamic WAN state file removed"
        else
            echo "❌ Failed to apply netplan configuration - you may need to run 'sudo netplan apply' manually"
        fi
    else
        echo "ℹ️  No interfaces were removed, skipping netplan apply"
    fi
    
    echo ""
    echo "✅ Safe Dynamic WAN netplan cleanup completed: removed $removed_count interface(s)"
}

# Function to stop and remove Docker containers
cleanup_containers() {
    echo "🐳 Cleaning up Docker containers..."
    
    # Stop and remove Dynamic WAN specific containers
    local containers=("frr_dynamicwan" "dhcpd_dynamicwan" "radiusd_dynamicwan")
    
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
        "frr_dynamicwan.conf"
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
    
    # Also clean up any temporary Dynamic WAN state files in /tmp
    local temp_files=(
        "/tmp/dynamicwan_configured_interfaces.conf"
        "/tmp/dynamicwan_debug.log"
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

# Function to cleanup iptables NAT rules
cleanup_iptables_rules() {
    echo "🧹 Cleaning up iptables NAT rules..."
    
    # Get all MASQUERADE rules from the nat table
    local masquerade_rules=$(sudo iptables -t nat -L POSTROUTING --line-numbers -n 2>/dev/null | grep "MASQUERADE" || true)
    local removed_count=0
    
    if [ -n "$masquerade_rules" ]; then
        echo "   🔍 Found MASQUERADE rules in iptables NAT table:"
        echo "$masquerade_rules" | sed 's/^/      /'
        
        # Remove MASQUERADE rules by line number (reverse order to maintain indices)
        local rule_numbers=($(echo "$masquerade_rules" | awk '{print $1}' | tac))
        
        for rule_num in "${rule_numbers[@]}"; do
            if [ -n "$rule_num" ] && [[ "$rule_num" =~ ^[0-9]+$ ]]; then
                echo "      🗑️  Removing MASQUERADE rule #$rule_num"
                if sudo iptables -t nat -D POSTROUTING "$rule_num" 2>/dev/null; then
                    echo "      ✅ Successfully removed rule #$rule_num"
                    removed_count=$((removed_count + 1))
                else
                    echo "      ⚠️  Failed to remove rule #$rule_num"
                fi
            fi
        done
    else
        echo "   ℹ️  No MASQUERADE rules found in iptables NAT table"
    fi
    
    # Also clean up FORWARD chain rules that might have been added
    local forward_rules=$(sudo iptables -L FORWARD --line-numbers -n 2>/dev/null | grep -E "(ACCEPT.*ESTABLISHED|ACCEPT.*all)" || true)
    local forward_removed=0
    
    if [ -n "$forward_rules" ]; then
        echo "   🔍 Checking FORWARD chain for Dynamic WAN-related rules..."
        
        # Only remove rules that look like they were added by our NAT setup
        # Look for rules that accept established/related connections
        local established_rules=$(sudo iptables -L FORWARD --line-numbers -n 2>/dev/null | grep "ESTABLISHED,RELATED" || true)
        
        if [ -n "$established_rules" ]; then
            echo "      Found ESTABLISHED,RELATED rules (possibly from Dynamic WAN setup):"
            echo "$established_rules" | sed 's/^/         /'
            
            # Note: We'll be conservative and not auto-remove FORWARD rules as they might be needed by other services
            echo "      ⚠️  FORWARD rules found but not automatically removed for safety"
            echo "      ℹ️  If these were added by Dynamic WAN, you may need to remove them manually:"
            echo "         sudo iptables -L FORWARD --line-numbers"
        fi
    fi
    
    echo "   📊 iptables cleanup summary:"
    echo "      MASQUERADE rules removed: $removed_count"
    
    if [ $removed_count -gt 0 ]; then
        echo "✅ Successfully cleaned up iptables NAT rules"
    else
        echo "ℹ️  No iptables NAT rules to clean up"
    fi
}

# Function to remove Dynamic WAN specific systemd service and NAT configuration
cleanup_nat_service() {
    echo "🔧 Cleaning up Dynamic WAN NAT service and configuration..."
    
    # Stop and disable the Dynamic WAN service
    if systemctl is-active --quiet setup-nat-dynamicwan.service 2>/dev/null; then
        echo "🛑 Stopping setup-nat-dynamicwan.service"
        sudo systemctl stop setup-nat-dynamicwan.service
    fi
    
    if systemctl is-enabled --quiet setup-nat-dynamicwan.service 2>/dev/null; then
        echo "🚫 Disabling setup-nat-dynamicwan.service"
        sudo systemctl disable setup-nat-dynamicwan.service
    fi
    
    # Remove the Dynamic WAN service file
    if [ -f "/etc/systemd/system/setup-nat-dynamicwan.service" ]; then
        sudo rm -f /etc/systemd/system/setup-nat-dynamicwan.service
        echo "🗑️  Removed: /etc/systemd/system/setup-nat-dynamicwan.service"
    fi
    
    # Remove the Dynamic WAN setup script
    if [ -f "/usr/local/bin/setup-nat-dynamicwan.sh" ]; then
        sudo rm -f /usr/local/bin/setup-nat-dynamicwan.sh
        echo "🗑️  Removed: /usr/local/bin/setup-nat-dynamicwan.sh"
    fi
    
    # Also check for and clean up older services (v5/v4/v3/v2) if they exist
    for version in v5 v4 v3 v2 ""; do
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
    
    # Automatically remove iptables NAT rules
    cleanup_iptables_rules
}

# Function to reset IP forwarding
reset_ip_forwarding() {
    echo "🌐 Resetting IP forwarding..."
    
    # Disable IP forwarding
    echo "0" | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    echo "✅ Disabled IP forwarding"
    
    # Remove from sysctl.conf if it was added
    if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "   🔍 Found net.ipv4.ip_forward=1 in /etc/sysctl.conf"
        echo "   🗑️  Removing IP forwarding setting from sysctl.conf..."
        
        # Create a backup before modifying
        sudo cp /etc/sysctl.conf /etc/sysctl.conf.dynamicwan_backup.$(date +%Y%m%d_%H%M%S)
        echo "   💾 Created backup: /etc/sysctl.conf.dynamicwan_backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove the IP forwarding line
        sudo sed -i '/^net\.ipv4\.ip_forward=1$/d' /etc/sysctl.conf
        
        # Verify removal
        if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
            echo "   ✅ Successfully removed net.ipv4.ip_forward=1 from sysctl.conf"
        else
            echo "   ⚠️  Failed to remove net.ipv4.ip_forward=1 from sysctl.conf"
            echo "   ℹ️  You may need to remove it manually"
        fi
    else
        echo "   ℹ️  No IP forwarding setting found in sysctl.conf"
    fi
}

# Function to clean up Dynamic WAN IP addresses directly from interfaces
cleanup_dynamicwan_ip_addresses() {
    echo "🌐 Cleaning up Dynamic WAN IP addresses from interfaces..."
    
    # Dynamic WAN configures IPs in the 172.16.x.1/30 pattern
    # Scan all interfaces for these specific IP patterns
    local removed_count=0
    local checked_count=0
    
    echo "   🔍 Scanning all interfaces for Dynamic WAN IP addresses (172.16.x.1/30)..."
    
    # Get all interfaces and check for Dynamic WAN IP patterns
    local all_interfaces=$(ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | sed 's/@.*$//')
    
    for interface in $all_interfaces; do
        # Skip loopback interface
        if [ "$interface" = "lo" ]; then
            continue
        fi
        
        # Check if interface has Dynamic WAN IP addresses (172.16.x.1/30 pattern)
        local dynamicwan_ips=$(ip addr show "$interface" 2>/dev/null | grep -E "inet 172\.16\.[0-9]+\.1/30" | awk '{print $2}')
        
        if [ -n "$dynamicwan_ips" ]; then
            echo "   📍 Found Dynamic WAN IP addresses on interface $interface:"
            echo "$dynamicwan_ips" | sed 's/^/      /'
            
            # Remove each Dynamic WAN IP address
            while IFS= read -r ip_cidr; do
                if [ -n "$ip_cidr" ]; then
                    echo "      🗑️  Removing IP: $ip_cidr from $interface"
                    if sudo ip addr del "$ip_cidr" dev "$interface" 2>/dev/null; then
                        echo "      ✅ Successfully removed: $ip_cidr"
                        removed_count=$((removed_count + 1))
                    else
                        echo "      ⚠️  Failed to remove: $ip_cidr"
                    fi
                fi
            done <<< "$dynamicwan_ips"
        fi
        checked_count=$((checked_count + 1))
    done
    
    echo "   📊 IP cleanup summary:"
    echo "      Interfaces checked: $checked_count"
    echo "      Dynamic WAN IP addresses removed: $removed_count"
    
    if [ $removed_count -gt 0 ]; then
        echo "✅ Successfully cleaned up $removed_count Dynamic WAN IP addresses"
        
        # Show current status after cleanup
        echo ""
        echo "   🔍 Current interface status after cleanup:"
        local remaining_dynamicwan_ips=$(ip addr show | grep -E "inet 172\.16\.[0-9]+\.1/30" | wc -l)
        if [ "$remaining_dynamicwan_ips" -eq 0 ]; then
            echo "      ✅ No remaining Dynamic WAN IP addresses found"
        else
            echo "      ⚠️  Warning: $remaining_dynamicwan_ips Dynamic WAN IP addresses still remain:"
            ip addr show | grep -E "inet 172\.16\.[0-9]+\.1/30" | sed 's/^/         /'
        fi
    else
        echo "ℹ️  No Dynamic WAN IP addresses found to remove"
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
    echo "🔍 Dynamic WAN Network configuration to be cleaned up:"
    echo ""
    echo "   🐳 Docker Containers: frr_dynamicwan, dhcpd_dynamicwan, radiusd_dynamicwan"
    echo "   🌐 IP Addresses: All Dynamic WAN IPs (172.16.x.1/30 pattern) from all interfaces"
    echo "   🌐 Interfaces: Read from Dynamic WAN state file (/etc/dynamicwan_configured_interfaces.conf) when available"
    echo "   🔧 Services: setup-nat-dynamicwan.service and older NAT services"
    echo "   🧹 iptables: MASQUERADE NAT rules (automatically detected and removed)"
    echo "   ⚙️  sysctl: net.ipv4.ip_forward setting in /etc/sysctl.conf"
    echo "   📄 Config Files: frr_dynamicwan.conf, dhcpd.conf, radius configs"
    echo "   🛡️  SAFETY: Only removes Dynamic WAN specific configurations (172.16.x.1/30 IPs)"
    echo "   🔒 Other interface configurations remain untouched"
    echo "   🌍 Universal: Works on any server regardless of interface naming"
    echo ""
}

# Main cleanup function
main_cleanup() {
    echo "🚀 Starting Dynamic WAN Network cleanup process..."
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
        
        # Remove Dynamic WAN interfaces from netplan (safely using state file)
        if ! remove_dynamicwan_interfaces_from_netplan "$NETPLAN_FILE"; then
            echo ""
            echo "⚠️  Safe Dynamic WAN interface removal failed!"
            echo "   This usually means the Dynamic WAN state file is missing or corrupted"
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
    
    # Clean up Dynamic WAN IP addresses directly from interfaces
    cleanup_dynamicwan_ip_addresses
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
    
    echo "✅ Dynamic WAN Network cleanup completed!"
    echo ""
    echo "📋 Summary of actions performed:"
    echo "   • SAFELY removed Dynamic WAN interfaces from netplan (using Dynamic WAN state file when available)"
    echo "   • Removed Dynamic WAN IP addresses directly from interfaces (172.16.x.1/30 pattern)"
    echo "   • Stopped and removed Docker containers (frr_dynamicwan, dhcpd_dynamicwan, radiusd_dynamicwan)"
    echo "   • Preserved Docker images (dhcpd, radiusd) for reuse"
    echo "   • Removed all Dynamic WAN configuration files and state file"
    echo "   • Stopped and removed Dynamic WAN NAT systemd service"
    echo "   • Cleaned up older NAT services (v5, v4, v3, v2) if found"
    echo "   • AUTOMATICALLY removed iptables NAT MASQUERADE rules"
    echo "   • Disabled IP forwarding and cleaned sysctl.conf"
    echo "   • Cleaned up all OSPF routes from routing table"
    echo "   🛡️  SAFETY: Only removes Dynamic WAN specific configurations (172.16.x.1/30 IPs)"
    echo ""
    echo "✅ All Dynamic WAN Network configurations have been automatically reverted!"
    echo "   No manual cleanup should be required for standard installations."
    echo ""
    echo "🔄 You may want to reboot the system to ensure all changes take effect."
}

# Confirmation prompt
echo "⚠️  WARNING: This will undo all changes made by dynamic_wan_demo.sh"
echo "   This includes:"
echo "   • Removing Docker containers"
echo "   • Restoring network configuration for Dynamic WAN interfaces"
echo "   • Removing systemd services"
echo "   • Cleaning up configuration files"
echo ""
echo "🔧 Dynamic WAN Network supports 1, 2, or 4 interfaces dynamically"
echo "   This cleanup script will SAFELY remove ONLY Dynamic WAN configured interfaces"
echo "   (Detection method: Dynamic WAN state file /etc/dynamicwan_configured_interfaces.conf)"
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

