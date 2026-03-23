#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.txt"

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: $CONFIG_FILE not found. Create it next to this script (see comments inside config.txt)."
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"
      v="${BASH_REMATCH[2]}"
      v="${v%"${v##*[![:space:]]}"}"
      case "$k" in
        mode) mode="$v" ;;
        interface) interface="$v" ;;
        numPods) numPods="$v" ;;
        router_ip) router_ip="$v" ;;
        nsb_uplink_ip) nsb_uplink_ip="$v" ;;
      esac
    fi
  done < "$CONFIG_FILE"
}

load_config

interface="${interface:-eth0}"
numPods="${numPods:-3}"

# Must match setup.sh: Linux ifname max 15 chars, so long parents use hol-vlan-<vid>.
vlan_ifname() {
  local parent="$1"
  local vid="$2"
  local cand="${parent}.${vid}"
  if (( ${#cand} <= 15 )); then
    printf '%s' "$cand"
  else
    printf 'hol-vlan-%s' "$vid"
  fi
}

echo "Tearing down FRR lab setup (interface=$interface, numPods=$numPods)..."
echo "---------------------------------------"

# WAN network bridge
wan_net="docker0"

# Loop through each pod and clean up
for ((i=1; i<=numPods; i++)); do
    echo "➡️  Cleaning up pod $i..."

    # Stop and remove container
    docker rm -f frr$i &>/dev/null && echo "  🗑️  Removed container frr$i"
    docker rm -f dhcpd$i &>/dev/null && echo "  🗑️  Removed container dhcpd$i"
    docker rm -f radiusd$i &>/dev/null && echo "  🗑️  Removed container radiusd$i"

    # Delete veth interfaces if they exist
    sudo ip link delete veth-wan$i &>/dev/null && echo "  🔌 Deleted veth-wan$i"
    sudo ip link delete veth-lan$i &>/dev/null && echo "  🔌 Deleted veth-lan$i"
    sudo ip link delete frr-dhcpd-$i &>/dev/null && echo "  🔌 Deleted frr-dhcpd-$i"
    sudo ip link delete frr-radiusd-$i &>/dev/null && echo "  🔌 Deleted frr-radiusd-$i"

    # Delete LAN bridge
    sudo ip link delete br-lan-$i type bridge &>/dev/null && echo "  🔧 Deleted bridge br-lan-$i"

    # Delete VLAN subinterface (name matches setup.sh vlan_ifname)
    vlanID=$((10 + i))
    vlan_iface=$(vlan_ifname "$interface" "$vlanID")
    sudo ip link delete "$vlan_iface" &>/dev/null && echo "  🚫 Removed VLAN subinterface $vlan_iface"

    # Remove FRR config file
    rm -f frr$i.conf && echo "  🗃️  Deleted frr$i.conf"
    echo "---------------------------------------"
done

# Remove shared daemons file
rm -f daemons && echo "🗃️  Deleted daemons file"
# Remove DHCPD files
rm -f dhcpdContainerfile && echo "🗃️  Deleted dhcpdContainerfile file"
rm -f dhcpdStartup.sh && echo "🗃️  Deleted dhcpdStartup.sh file"
rm -f dhcpd.conf && echo "🗃️  Deleted dhcpd.conf file"

# Remove RADIUS files
rm -f clients.conf && echo "🗃️  Deleted clients.cong file"
rm -f authorize && echo "🗃️  Deleted authorize file"
rm -f dictionary.nile && echo "🗃️  Deleted dictionary.nile file"
rm -f radiusdContainerfile && echo "🗃️  Deleted radiusdContainerfile file"
rm -f default && echo "🗃️  Deleted default file"

#Remove nginx-hol
sudo docker rm -f nginx-hol
echo "Removed nginx-hol"

# Remove wan_net
docker network  rm -f wan_net
echo "Removed wan_net"
echo "✅ Teardown complete."
