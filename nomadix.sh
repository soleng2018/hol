# Create a new route table
echo "200 to_pc" | sudo tee -a /etc/iproute2/rt_tables

#Add a default route in this table
sudo ip route add default via 10.11.11.2 dev enp3s0 table to_pc

# Match all traffic from 192.168.20.0/24 and send it to 10.11.11.2
sudo ip rule add from 192.168.20.0/24 lookup to_pc priority 100
ip rule list

# Ensure traffic is allowed between interfaces and the reverse path
sudo iptables -A FORWARD -i enp2s0 -o enp3s0 -s 192.168.20.0/24 -j ACCEPT
sudo iptables -A FORWARD -i enp3s0 -o enp2s0 -d 192.168.20.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Need to add a static arp entry for Nomadix's mac address
sudo arp -i enp3s0 -s 10.11.11.2 00:50:E8:10:13:DC
