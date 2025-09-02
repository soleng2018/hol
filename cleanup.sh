#!/bin/bash

echo "Tearing down FRR lab setup..."

# Prompt for number of pods
echo -n "Enter number of pods to clean up: "
read numPods

# Prompt for host interface (used for VLAN)
echo -n "Enter host interface used for VLANs (e.g., eth0): "
read interface

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

    # Delete VLAN subinterface
    vlanID=$((10 + i))
    sudo ip link delete "$interface.$vlanID" &>/dev/null && echo "  🚫 Removed VLAN subinterface $interface.$vlanID"

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
