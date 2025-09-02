#!/bin/bash
set -euo pipefail
# Function to check if the interface exists
check_interface() {
    if ! ip link show "$1" &> /dev/null; then
        echo "Error: Interface $1 does not exist on the host."
        exit 1
    fi
}

# Function to run FRR container
create_frr_container() {
    local podID=0
    local containerName="frr$podID"
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
    -v ./frr${podID}.conf:/etc/frr/frr.conf:Z \
    -v ./daemons:/etc/frr/daemons:Z  \
     docker.io/frrouting/frr

    echo "Started container $containerName"
    echo "--------------------------------------------------------------"
}

# Function to run DHCPD container
create_dhcpd_container() {
    local podID=0
    local containerName="dhcpd$podID"
    docker run -dt --name "$containerName" --network=host --privileged --restart=always \
     dhcpd

    echo "Started container $containerName"
    echo "--------------------------------------------------------------"
}

create_radiusd_container() {
    local podID=0
    local containerName="radiusd$podID"
    docker run -dt --name $containerName --network=host --privileged --restart=always \
     radiusd
    
    echo "Started container $containerName"
    echo "---------------------------------------"
}

# Function to generate FRR config file
generate_frr_config() {
    local podID=0
    local config_file="frr${podID}.conf"

    cat <<EOF > "$config_file"
frr version 8.4_git
frr defaults traditional
hostname frr
log stdout
ip forwarding
no ipv6 forwarding
!
interface $interface
 ip address $lan_ip
!
router ospf
 ospf router-id 1.1.1.1
 network $lan_subnet area 0
 default-information originate always
!
line vty
!
EOF

    echo "FRR config written to $config_file"
    echo "--------------------------------------------------------------"
}

# --- MAIN SCRIPT ---

# Prompt for inputs
read -p "Enter host interface name (e.g., eth0) [eth0]: " interface
interface=${interface:-eth0}
check_interface "$interface"

read -p "Enter LAN IP (e.g., 172.16.0.1/30) [172.16.0.1/30]: " lan_ip
lan_ip=${lan_ip:-172.16.0.1/30}

read -p "Enter LAN subnet (e.g., 172.16.0.0/30) [172.16.0.0/30]: " lan_subnet
lan_subnet=${lan_subnet:-172.16.0.0/30}
lan_net_addr=$(echo "$lan_subnet" | cut -d'/' -f1)

# Check if interface exists and get current configuration
if ! ip link show "$interface" &> /dev/null; then
    echo "❌ Interface $interface does not exist"
    exit 1
fi

echo "✅ Found interface: $interface"

# Find the netplan configuration file
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
if [ -z "$NETPLAN_FILE" ]; then
    echo "❌ No netplan configuration file found in /etc/netplan/"
    exit 1
fi

echo "✅ Using netplan file: $NETPLAN_FILE"

# Create backup of original netplan file
sudo cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Extract IP address and prefix from lan_ip (e.g., 172.16.0.1/30)
IP_ADDR=$(echo "$lan_ip" | cut -d'/' -f1)
PREFIX=$(echo "$lan_ip" | cut -d'/' -f2)

# Check if the interface already exists in the netplan file
if sudo grep -q "^\s*$interface:" "$NETPLAN_FILE"; then
    echo "⚠️  Interface $interface already exists in netplan configuration"
    echo "   The existing configuration will be updated"
    
    # Update the interface configuration
    sudo python3 -c "
import yaml
import sys

try:
    # Read the existing netplan file
    with open('$NETPLAN_FILE', 'r') as f:
        config = yaml.safe_load(f)
    
    # Ensure network section exists
    if 'network' not in config:
        config['network'] = {}
    
    # Update or add the interface configuration
    if 'ethernets' not in config['network']:
        config['network']['ethernets'] = {}
    
    config['network']['ethernets']['$interface'] = {
        'dhcp4': False,
        'addresses': ['$IP_ADDR/$PREFIX']
        # No gateway or DNS configured as per original script
    }
    
    # Write the updated configuration
    with open('$NETPLAN_FILE', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    print('Configuration updated successfully')
    
except Exception as e:
    print(f'Error updating netplan: {e}')
    sys.exit(1)
" || {
    echo "❌ Failed to update netplan configuration. Python3 or PyYAML not available."
    echo "   Please install: sudo apt install python3-yaml"
    exit 1
}
else
    echo "✅ Adding new interface $interface to netplan configuration"
    
    # Add the new interface to the existing configuration
    sudo python3 -c "
import yaml
import sys

try:
    # Read the existing netplan file
    with open('$NETPLAN_FILE', 'r') as f:
        config = yaml.safe_load(f)
    
    # Ensure network section exists
    if 'network' not in config:
        config['network'] = {}
    
    # Add the new interface configuration
    if 'ethernets' not in config['network']:
        config['network']['ethernets'] = {}
    
    config['network']['ethernets']['$interface'] = {
        'dhcp4': False,
        'addresses': ['$IP_ADDR/$PREFIX']
        # No gateway or DNS configured as per original script
    }
    
    # Write the updated configuration
    with open('$NETPLAN_FILE', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    print('Configuration added successfully')
    
except Exception as e:
    print(f'Error adding to netplan: {e}')
    sys.exit(1)
" || {
    echo "❌ Failed to update netplan configuration. Python3 or PyYAML not available."
    echo "   Please install: sudo apt install python3-yaml"
    exit 1
}
fi

# Apply the netplan configuration
sudo netplan apply

echo "✅ $interface is now configured with static IP $lan_ip (no gateway, no DNS)"

# Enable NAT and ip_forward on host
# Get the interface used for the default route (internet access)
INTERNET_IFACE=$(ip route | awk '/^default/ {print $5; exit}')

if [ -n "$INTERNET_IFACE" ]; then
    echo "Internet-facing interface: $INTERNET_IFACE"
else
    echo "No default internet interface found." >&2
    exit 1
fi

# Create setup-nat.sh dynamically
sudo tee /usr/local/bin/setup-nat.sh > /dev/null <<EOF
#!/bin/bash

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Add iptables rules
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE
iptables -A FORWARD -i $interface -o $INTERNET_IFACE -j ACCEPT
iptables -A FORWARD -i $INTERNET_IFACE -o $interface -m state --state ESTABLISHED,RELATED -j ACCEPT
EOF

# Make it executable
sudo chmod +x /usr/local/bin/setup-nat.sh

sudo tee /etc/systemd/system/setup-nat.service > /dev/null <<EOF
[Unit]
Description=Custom NAT and IP Forwarding Rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-nat.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable/start the service
sudo systemctl daemon-reexec
sudo systemctl enable setup-nat.service
sudo systemctl start setup-nat.service

# Install bridge-utils
#sudo apt-get update
#sudo apt-get install bridge-utils -y

# Create shared FRR daemons file
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

echo "Created FRR daemons file"
echo "--------------------------------------------------------------"

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

echo "Created dhcpdContainerfile file"
echo "--------------------------------------------------------------"

# Create DHCP Startup script dhcpdStartup.sh
cat <<EOF > dhcpdStartup.sh
#!/bin/bash
set -e

echo "$(date): Starting DHCP service startup script" >> /var/log/startup.log
echo "$(date): Starting DHCP service startup script"

# Start the DHCP server
echo "$(date): Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid $interface

echo "$(date): DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
EOF

echo "Created dhcpdStartup.sh file"
echo "--------------------------------------------------------------"

#Create dhcpd.conf
cat <<EOF > dhcpd.conf
# dhcpd.conf
#
# Sample configuration file for ISC dhcpd
#
# Attention: If /etc/ltsp/dhcpd.conf exists, that will be used as
# configuration file instead of this file.
#

# option definitions common to all supported networks...
option domain-name "example.org";
option domain-name-servers ns1.example.org, ns2.example.org;

default-lease-time 600;
max-lease-time 7200;

# The ddns-updates-style parameter controls whether or not the server will
# attempt to do a DNS update when a lease is confirmed. We default to the
# behavior of the version 2 packages ('none', since DHCP v2 didn't
# have support for DDNS.)
ddns-update-style none;

# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
#authoritative;

# Use this to send dhcp log messages to a different log file (you also
# have to hack syslog.conf to complete the redirection).
#log-facility local7;

# No service will be given on this subnet, but declaring it helps the
# DHCP server to understand the network topology.

subnet $lan_net_addr netmask 255.255.255.252 {
}
#
subnet 192.168.18.0 netmask 255.255.255.0 {
}
#
subnet 192.168.19.0 netmask 255.255.255.0 {
}

subnet 192.168.18.0 netmask 255.255.255.0 {
  range 192.168.18.11 192.168.18.11;
  option domain-name-servers 8.8.8.8;
  option domain-name "selab.net";
  option subnet-mask 255.255.255.0;
  option routers 192.168.18.1;
  option broadcast-address 192.168.18.255;
  default-lease-time 600;
  max-lease-time 7200;
}
#
subnet 192.168.19.0 netmask 255.255.255.0 {
  range 192.168.19.11 192.168.19.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "selab.net";
  option subnet-mask 255.255.255.0;
  option routers 192.168.19.1;
  option broadcast-address 192.168.19.255;
  default-lease-time 600;
  max-lease-time 7200;
}
subnet 192.168.20.0 netmask 255.255.255.0 {
  range 192.168.20.11 192.168.20.254;
  option domain-name-servers 8.8.8.8;
  option domain-name "selab.net";
  option subnet-mask 255.255.255.0;
  option routers 192.168.20.1;
  option broadcast-address 192.168.20.255;
  default-lease-time 600;
  max-lease-time 7200;
}

EOF

echo "Created dhcpd.conf file"
echo "--------------------------------------------------------------"

# Create DHCPD Image
docker build -t dhcpd -f dhcpdContainerfile .
echo "DHCPD Image has been created"
echo "--------------------------------------------------------------"

# Create RADIUS clients.conf
cat <<EOF > clients.conf
client local1 {
 ipaddr = 127.0.0.1
 proto = *
 secret = nile123
}
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
echo "Created clients.conf file"
echo "--------------------------------------------------------------"

# Create Nile dictionary.nile
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

echo "Created Nile Dictionary file"
echo "--------------------------------------------------------------"

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
EOF

# Create RADIUS default file
cat <<EOF > default
######################################################################
#
#       As of 2.0.0, FreeRADIUS supports virtual hosts using the
#       "server" section, and configuration directives.
#
#       Virtual hosts should be put into the "sites-available"
#       directory.  Soft links should be created in the "sites-enabled"
#       directory to these files.  This is done in a normal installation.
#
#       If you are using 802.1X (EAP) authentication, please see also
#       the "inner-tunnel" virtual server.  You will likely have to edit
#       that, too, for authentication to work.
#
#
######################################################################
#
#       Read "man radiusd" before editing this file.  See the section
#       titled DEBUGGING.  It outlines a method where you can quickly
#       obtain the configuration you want, without running into
#       trouble.  See also "man unlang", which documents the format
#       of this file.
#
#       This configuration is designed to work in the widest possible
#       set of circumstances, with the widest possible number of
#       authentication methods.  This means that in general, you should
#       need to make very few changes to this file.
#
#       The best way to configure the server for your local system
#       is to CAREFULLY edit this file.  Most attempts to make large
#       edits to this file will BREAK THE SERVER.  Any edits should
#       be small, and tested by running the server with "radiusd -X".
#       Once the edits have been verified to work, save a copy of these
#       configuration files somewhere.  (e.g. as a "tar" file).  Then,
#       make more edits, and test, as above.
#
#       There are many "commented out" references to modules such
#       as ldap, sql, etc.  These references serve as place-holders.
#       If you need the functionality of that module, then configure
#       it in radiusd.conf, and un-comment the references to it in
#       this file.  In most cases, those small changes will result
#       in the server being able to connect to the DB, and to
#       authenticate users.
#
######################################################################

server default {
#
#  If you want the server to listen on additional addresses, or on
#  additional ports, you can use multiple "listen" sections.
#
#  Each section make the server listen for only one type of packet,
#  therefore authentication and accounting have to be configured in
#  different sections.
#
#  The server ignore all "listen" section if you are using '-i' and '-p'
#  on the command line.
#
listen {
        #  Type of packets to listen for.
        #  Allowed values are:
        #       auth    listen for authentication packets
        #       acct    listen for accounting packets
        #       auth+acct listen for both authentication and accounting packets
        #       proxy   IP to use for sending proxied packets
        #       detail  Read from the detail file.  For examples, see
        #               raddb/sites-available/copy-acct-to-home-server
        #       status  listen for Status-Server packets.  For examples,
        #               see raddb/sites-available/status
        #       coa     listen for CoA-Request and Disconnect-Request
        #               packets.  For examples, see the file
        #               raddb/sites-available/coa
        #
        type = auth

        #  Note: "type = proxy" lets you control the source IP used for
        #        proxying packets, with some limitations:
        #
        #    * A proxy listener CANNOT be used in a virtual server section.
        #    * You should probably set "port = 0".
        #    * Any "clients" configuration will be ignored.
        #
        #  See also proxy.conf, and the "src_ipaddr" configuration entry
        #  in the sample "home_server" section.  When you specify the
        #  source IP address for packets sent to a home server, the
        #  proxy listeners are automatically created.

        #  ipaddr/ipv4addr/ipv6addr - IP address on which to listen.
        #  If multiple ones are listed, only the first one will
        #  be used, and the others will be ignored.
        #
        #  The configuration options accept the following syntax:
        #
        #  ipv4addr - IPv4 address (e.g.192.0.2.3)
        #           - wildcard (i.e. *)
        #           - hostname (radius.example.com)
        #             Only the A record for the host name is used.
        #             If there is no A record, an error is returned,
        #             and the server fails to start.
        #
        #  ipv6addr - IPv6 address (e.g. 2001:db8::1)
        #           - wildcard (i.e. *)
        #           - hostname (radius.example.com)
        #             Only the AAAA record for the host name is used.
        #             If there is no AAAA record, an error is returned,
        #             and the server fails to start.
        #
        #  ipaddr   - IPv4 address as above
        #           - IPv6 address as above
        #           - wildcard (i.e. *), which means IPv4 wildcard.
        #           - hostname
        #             If there is only one A or AAAA record returned
        #             for the host name, it is used.
        #             If multiple A or AAAA records are returned
        #             for the host name, only the first one is used.
        #             If both A and AAAA records are returned
        #             for the host name, only the A record is used.
        #
        # ipv4addr = *
        # ipv6addr = *
        ipaddr = *

        #  Port on which to listen.
        #  Allowed values are:
        #       integer port number (1812)
        #       0 means "use /etc/services for the proper port"
        port = 0

        #  Some systems support binding to an interface, in addition
        #  to the IP address.  This feature isn't strictly necessary,
        #  but for sites with many IP addresses on one interface,
        #  it's useful to say "listen on all addresses for eth0".
        #
        #  If your system does not support this feature, you will
        #  get an error if you try to use it.
        #
#       interface = eth0

        #  Per-socket lists of clients.  This is a very useful feature.
        #
        #  The name here is a reference to a section elsewhere in
        #  radiusd.conf, or clients.conf.  Having the name as
        #  a reference allows multiple sockets to use the same
        #  set of clients.
        #
        #  If this configuration is used, then the global list of clients
        #  is IGNORED for this "listen" section.  Take care configuring
        #  this feature, to ensure you don't accidentally disable a
        #  client you need.
        #
        #  See clients.conf for the configuration of "per_socket_clients".
        #
#       clients = per_socket_clients

        #
        #  Set the default UDP receive buffer size.  In most cases,
        #  the default values set by the kernel are fine.  However, in
        #  some cases the NASes will send large packets, and many of
        #  them at a time.  It is then possible to overflow the
        #  buffer, causing the kernel to drop packets before they
        #  reach FreeRADIUS.  Increasing the size of the buffer will
        #  avoid these packet drops.
        #
#       recv_buff = 65536

        #
        #  Connection limiting for sockets with "proto = tcp".
        #
        #  This section is ignored for other kinds of sockets.
        #
        limit {
              #
              #  Limit the number of simultaneous TCP connections to the socket
              #
              #  The default is 16.
              #  Setting this to 0 means "no limit"
              max_connections = 16

              #  The per-socket "max_requests" option does not exist.

              #
              #  The lifetime, in seconds, of a TCP connection.  After
              #  this lifetime, the connection will be closed.
              #
              #  Setting this to 0 means "forever".
              lifetime = 0

              #
              #  The idle timeout, in seconds, of a TCP connection.
              #  If no packets have been received over the connection for
              #  this time, the connection will be closed.
              #
              #  In general, the client should close connections when
              #  they are idle.  This setting is here just to make
              #  sure that bad clients do not leave connections open
              #  for days.
              #
              #  If an idle timeout is set for only a "client" or a
              #  "listen" section, that timeout is used.
              #
              #  If an idle timeout is set for both a "client" and a
              #  "listen" section, then the smaller timeout is used.
              #
              #  Setting this to 0 means "no timeout".
              #
              #  We STRONGLY RECOMMEND that you set an idle timeout.
              #
              #  Systems with many incoming connections (500+) should
              #  set this value to a lower number.  There are only a
              #  limited number of usable file descriptors (usually
              #  1024) due to Posix API issues.  If many sockets are
              #  idle, it can prevent the server from opening new
              #  connections.
              #
              idle_timeout = 900
        }
}

#
#  This second "listen" section is for listening on the accounting
#  port, too.
#
listen {
        ipaddr = *
#       ipv6addr = ::
        port = 0
        type = acct
#       interface = eth0
#       clients = per_socket_clients

        limit {
                #  The number of packets received can be rate limited via the
                #  "max_pps" configuration item.  When it is set, the server
                #  tracks the total number of packets received in the previous
                #  second.  If the count is greater than "max_pps", then the
                #  new packet is silently discarded.  This helps the server
                #  deal with overload situations.
                #
                #  The packets/s counter is tracked in a sliding window.  This
                #  means that the pps calculation is done for the second
                #  before the current packet was received.  NOT for the current
                #  wall-clock second, and NOT for the previous wall-clock second.
                #
                #  Useful values are 0 (no limit), or 100 to 10000.
                #  Values lower than 100 will likely cause the server to ignore
                #  normal traffic.  Few systems are capable of handling more than
                #  10K packets/s.
                #
                #  It is most useful for accounting systems.  Set it to 50%
                #  more than the normal accounting load, and you can be sure that
                #  the server will never get overloaded
                #
#               max_pps = 0

                # Only for "proto = tcp". These are ignored for "udp" sockets.
                #
#               idle_timeout = 0
#               lifetime = 0
#               max_connections = 0
        }
}

# IPv6 versions of the above - read their full config to understand options
listen {
        type = auth
        ipv6addr = ::   # any.  ::1 == localhost
        port = 0
#       interface = eth0
#       clients = per_socket_clients
        limit {
              max_connections = 16
              lifetime = 0
              idle_timeout = 30
        }
}

listen {
        ipv6addr = ::
        port = 0
        type = acct
#       interface = eth0
#       clients = per_socket_clients

        limit {
#               max_pps = 0
#               idle_timeout = 0
#               lifetime = 0
#               max_connections = 0
        }
}

#  Authorization. First preprocess (hints and huntgroups files),
#  then realms, and finally look in the "users" file.
#
#  Any changes made here should also be made to the "inner-tunnel"
#  virtual server.
#
#  The order of the realm modules will determine the order that
#  we try to find a matching realm.
#
#  Make *sure* that 'preprocess' comes before any realm if you
#  need to setup hints for the remote radius server
authorize {
        #
        #  Take a User-Name, and perform some checks on it, for spaces and other
        #  invalid characters.  If the User-Name appears invalid, reject the
        #  request.
        #
        #  See policy.d/filter for the definition of the filter_username policy.
        #
        filter_username

        #
        #  Some broken equipment sends passwords with embedded zeros.
        #  i.e. the debug output will show
        #
        #       User-Password = "password\000\000"
        #
        #  This policy will fix it to just be "password".
        #
#       filter_password

        #
        #  The preprocess module takes care of sanitizing some bizarre
        #  attributes in the request, and turning them into attributes
        #  which are more standard.
        #
        #  It takes care of processing the 'raddb/mods-config/preprocess/hints'
        #  and the 'raddb/mods-config/preprocess/huntgroups' files.
        preprocess

        #  If you intend to use CUI and you require that the Operator-Name
        #  be set for CUI generation and you want to generate CUI also
        #  for your local clients then uncomment the operator-name
        #  below and set the operator-name for your clients in clients.conf
#       operator-name

        #
        #  If you want to generate CUI for some clients that do not
        #  send proper CUI requests, then uncomment the
        #  cui below and set "add_cui = yes" for these clients in clients.conf
#       cui

        #
        #  If you want to have a log of authentication requests,
        #  un-comment the following line.
#       auth_log

        #
        #  The chap module will set 'Auth-Type := CHAP' if we are
        #  handling a CHAP request and Auth-Type has not already been set
        chap

        #
        #  If the users are logging in with an MS-CHAP-Challenge
        #  attribute for authentication, the mschap module will find
        #  the MS-CHAP-Challenge attribute, and add 'Auth-Type := MS-CHAP'
        #  to the request, which will cause the server to then use
        #  the mschap module for authentication.
        mschap

        #
        #  If you have a Cisco SIP server authenticating against
        #  FreeRADIUS, uncomment the following line, and the 'digest'
        #  line in the 'authenticate' section.
        digest

        #
        #  The dpsk module implements dynamic PSK.
        #
        #  If the request contains FreeRADIUS-802.1X-Anonce
        #  and FreeRADIUS-802.1X-EAPoL-Key-Msg, then it will set
        #       &control:Auth-Type := dpsk
        #
        #  The "rewrite_called_station_id" policy creates the
        #  Called-Station-MAC attribute, which is needed by
        #  the dpsk module.
        #
#       rewrite_called_station_id
#       dpsk

        #
        #  The WiMAX specification says that the Calling-Station-Id
        #  is 6 octets of the MAC.  This definition conflicts with
        #  RFC 3580, and all common RADIUS practices.  If you are using
        #  old style WiMAX (non LTE) the un-commenting the "wimax" module
        #  here means that it will fix the Calling-Station-Id attribute to
        #  the normal format as specified in RFC 3580 Section 3.21.
        #
        #  If you are using WiMAX 2.1 (LTE) then un-commenting will allow
        #  the module to handle SQN resyncronisation. Prior to calling the
        #  module it is necessary to populate the following attributes
        #  with the relevant keys:
        #    control:WiMAX-SIM-Ki
        #    control:WiMAX-SIM-OPc
        #
        #  If WiMAX-Re-synchronization-Info is found in the request then
        #  the module will attempt to extract SQN and store it in
        #  control:WiMAX-SIM-SQN. Also a copy of RAND is extracted to
        #  control:WiMAX-SIM-RAND.
        #
        #  If the SIM cannot be authenticated using Ki and OPc then reject
        #  will be returned.
#       wimax

        #
        #  Look for IPASS style 'realm/', and if not found, look for
        #  '@realm', and decide whether or not to proxy, based on
        #  that.
#       IPASS

        #
        # Look for realms in user@domain format
        suffix
#       ntdomain

        #
        #  This module takes care of EAP-MD5, EAP-TLS, and EAP-LEAP
        #  authentication.
        #
        #  It also sets the EAP-Type attribute in the request
        #  attribute list to the EAP type from the packet.
        #
        #  The EAP module returns "ok" or "updated" if it is not yet ready
        #  to authenticate the user.  The configuration below checks for
        #  "ok", and stops processing the "authorize" section if so.
        #
        #  Any LDAP and/or SQL servers will not be queried for the
        #  initial set of packets that go back and forth to set up
        #  TTLS or PEAP.
        #
        #  The "updated" check is commented out for compatibility with
        #  previous versions of this configuration, but you may wish to
        #  uncomment it as well; this will further reduce the number of
        #  LDAP and/or SQL queries for TTLS or PEAP.
        #
        files
        eap {
                ok = return
#               updated = return
        }

        #
        #  Pull crypt'd passwords from /etc/passwd or /etc/shadow,
        #  using the system API's to get the password.  If you want
        #  to read /etc/passwd or /etc/shadow directly, see the
        #  mods-available/passwd module.
        #
#       unix

        #
        #  Read the 'users' file.  In v3, this is located in
        #  raddb/mods-config/files/authorize
        

        #
        #  Look in an SQL database.  The schema of the database
        #  is meant to mirror the "users" file.
        #
        #  See "Authorization Queries" in mods-available/sql
        -sql

        #
        #  If you are using /etc/smbpasswd, and are also doing
        #  mschap authentication, the un-comment this line, and
        #  configure the 'smbpasswd' module.
#       smbpasswd

        #
        #  The ldap module reads passwords from the LDAP database.
        -ldap

        #
        #  If you're using Active Directory and PAP, then uncomment
        #  the following lines, and the "Auth-Type LDAP" section below.
        #
        #  This will let you do PAP authentication to AD.
        #
#       if ((ok || updated) && User-Password && !control:Auth-Type) {
#               update control {
#                       &Auth-Type := ldap
#               }
#       }

        #
        #  Enforce daily limits on time spent logged in.
#       daily

        #
        expiration
        logintime

        #
        #  If no other module has claimed responsibility for
        #  authentication, then try to use PAP.  This allows the
        #  other modules listed above to add a "known good" password
        #  to the request, and to do nothing else.  The PAP module
        #  will then see that password, and use it to do PAP
        #  authentication.
        #
        #  This module should be listed last, so that the other modules
        #  get a chance to set Auth-Type for themselves.
        #
        pap

        #
        #  If "status_server = yes", then Status-Server messages are passed
        #  through the following section, and ONLY the following section.
        #  This permits you to do DB queries, for example.  If the modules
        #  listed here return "fail", then NO response is sent.
        #
#       Autz-Type Status-Server {
#
#       }

        #
        #  RADIUS/TLS (or RadSec) connections are processed through
        #  this section.  See sites-available/tls, and the configuration
        #  item "check_client_connections" for more information.
        #
        #  The request contains TLS client certificate attributes,
        #  and nothing else.  The debug output will print which
        #  attributes are available on your system.
        #
        #  If the section returns "ok" or "updated", then the
        #  connection is accepted.  Otherwise the connection is
        #  terminated.
        #
        Autz-Type New-TLS-Connection {
                  ok
        }
}


#  Authentication.
#
#
#  This section lists which modules are available for authentication.
#  Note that it does NOT mean 'try each module in order'.  It means
#  that a module from the 'authorize' section adds a configuration
#  attribute 'Auth-Type := FOO'.  That authentication type is then
#  used to pick the appropriate module from the list below.
#

#  In general, you SHOULD NOT set the Auth-Type attribute.  The server
#  will figure it out on its own, and will do the right thing.  The
#  most common side effect of erroneously setting the Auth-Type
#  attribute is that one authentication method will work, but the
#  others will not.
#
#  The common reasons to set the Auth-Type attribute by hand
#  is to either forcibly reject the user (Auth-Type := Reject),
#  or to or forcibly accept the user (Auth-Type := Accept).
#
#  Note that Auth-Type := Accept will NOT work with EAP.
#
#  Please do not put "unlang" configurations into the "authenticate"
#  section.  Put them in the "post-auth" section instead.  That's what
#  the post-auth section is for.
#
authenticate {
        #
        #  PAP authentication, when a back-end database listed
        #  in the 'authorize' section supplies a password.  The
        #  password can be clear-text, or encrypted.
        Auth-Type PAP {
                pap
        }

#       dpsk

        #
        #  Most people want CHAP authentication
        #  A back-end database listed in the 'authorize' section
        #  MUST supply a CLEAR TEXT password.  Encrypted passwords
        #  won't work.
        Auth-Type CHAP {
                chap
        }

        #
        #  MSCHAP authentication.
        Auth-Type MS-CHAP {
                mschap
        }

        #
        #  For old names, too.
        #
        mschap

        #
        #  If you have a Cisco SIP server authenticating against
        #  FreeRADIUS, uncomment the following line, and the 'digest'
        #  line in the 'authorize' section.
        digest

        #
        #  Pluggable Authentication Modules.
#       pam

        #  Uncomment it if you want to use ldap for authentication
        #
        #  Note that this means "check plain-text password against
        #  the ldap database", which means that EAP won't work,
        #  as it does not supply a plain-text password.
        #
        #  We do NOT recommend using this.  LDAP servers are databases.
        #  They are NOT authentication servers.  FreeRADIUS is an
        #  authentication server, and knows what to do with authentication.
        #  LDAP servers do not.
        #
        #  However, it is necessary for Active Directory, because
        #  Active Directory won't give the passwords to FreeRADIUS.
        #
#       Auth-Type LDAP {
#               ldap
#       }

        #
        #  Allow EAP authentication.
        eap

        #
        #  The older configurations sent a number of attributes in
        #  Access-Challenge packets, which wasn't strictly correct.
        #  If you want to filter out these attributes, uncomment
        #  the following lines.
        #
#       Auth-Type eap {
#               eap {
#                       handled = 1
#               }
#               if (handled && (Response-Packet-Type == Access-Challenge)) {
#                       attr_filter.access_challenge.post-auth
#                       handled  # override the "updated" code from attr_filter
#               }
#       }
}


#
#  Pre-accounting.  Decide which accounting type to use.
#
preacct {
        preprocess

        #
        #  Merge Acct-[Input|Output]-Gigawords and Acct-[Input-Output]-Octets
        #  into a single 64bit counter Acct-[Input|Output]-Octets64.
        #
#       acct_counters64

        #
        #  Session start times are *implied* in RADIUS.
        #  The NAS never sends a "start time".  Instead, it sends
        #  a start packet, *possibly* with an Acct-Delay-Time.
        #  The server is supposed to conclude that the start time
        #  was "Acct-Delay-Time" seconds in the past.
        #
        #  The code below creates an explicit start time, which can
        #  then be used in other modules.  It will be *mostly* correct.
        #  Any errors are due to the 1-second resolution of RADIUS,
        #  and the possibility that the time on the NAS may be off.
        #
        #  The start time is: NOW - delay - session_length
        #

#       update request {
#               &FreeRADIUS-Acct-Session-Start-Time = "%{expr: %l - %{%{Acct-Session-Time}:-0} - %{%{Acct-Delay-Time}:-0}}"
#       }


        #
        #  Ensure that we have a semi-unique identifier for every
        #  request, and many NAS boxes are broken.
        acct_unique

        #
        #  Look for IPASS-style 'realm/', and if not found, look for
        #  '@realm', and decide whether or not to proxy, based on
        #  that.
        #
        #  Accounting requests are generally proxied to the same
        #  home server as authentication requests.
#       IPASS
        suffix
#       ntdomain

        #
        #  Read the 'acct_users' file
        files
}

#
#  Accounting.  Log the accounting data.
#
accounting {
        #  Update accounting packet by adding the CUI attribute
        #  recorded from the corresponding Access-Accept
        #  use it only if your NAS boxes do not support CUI themselves
#       cui

        #
        #  Create a 'detail'ed log of the packets.
        #  Note that accounting requests which are proxied
        #  are also logged in the detail file.
        detail
#       daily

        #  Update the wtmp file
        #
        #  If you don't use "radlast" (becoming obsolete and no longer
        #  available on all systems), you can delete this line.
#       unix

        #
        #  For Simultaneous-Use tracking.
        #
        #  Due to packet losses in the network, the data here
        #  may be incorrect.  There is little we can do about it.
#       radutmp
#       sradutmp

        #
        #  Return an address to the IP Pool when we see a stop record.
        #
        #  Ensure that &control:Pool-Name is set to determine which
        #  pool of IPs are used.
#       sqlippool

        #
        #  Log traffic to an SQL database.
        #
        #  See "Accounting queries" in mods-available/sql
        -sql

        #
        #  If you receive stop packets with zero session length,
        #  they will NOT be logged in the database.  The SQL module
        #  will print a message (only in debugging mode), and will
        #  return "noop".
        #
        #  You can ignore these packets by uncommenting the following
        #  three lines.  Otherwise, the server will not respond to the
        #  accounting request, and the NAS will retransmit.
        #
#       if (noop) {
#               ok
#       }

        #  Cisco VoIP specific bulk accounting
#       pgsql-voip

        # For Exec-Program and Exec-Program-Wait
        exec

        #  Filter attributes from the accounting response.
        attr_filter.accounting_response

        #
        #  See "Autz-Type Status-Server" for how this works.
        #
#       Acct-Type Status-Server {
#
#       }
}


#  Session database, used for checking Simultaneous-Use. Either the radutmp
#  or rlm_sql module can handle this.
#  The rlm_sql module is *much* faster
session {
#       radutmp

        #
        #  See "Simultaneous Use Checking Queries" in mods-available/sql
#       sql
}


#  Post-Authentication
#  Once we KNOW that the user has been authenticated, there are
#  additional steps we can take.
post-auth {
        #
        #  If you need to have a State attribute, you can
        #  add it here.  e.g. for later CoA-Request with
        #  State, and Service-Type = Authorize-Only.
        #
#       if (!&reply:State) {
#               update reply {
#                       State := "0x%{randstr:16h}"
#               }
#       }

        #
        #  Reject packets where User-Name != TLS-Client-Cert-Common-Name
        #  There is no reason for users to lie about their names.
        #
        #  In general, User-Name == EAP Identity == TLS-Client-Cert-Common-Name
        #
#       verify_tls_client_common_name

        #
        #  If there is no Stripped-User-Name in the request, AND we have a client cert,
        #  then create a Stripped-User-Name from the TLS client certificate information.
        #
        #  Note that this policy MUST be edited for your local system!
        #  We do not know which fields exist in which certificate, as
        #  there is no standard here.  There is no way for us to have
        #  a default configuration which "just works" everywhere.  We
        #  can only make recommendations.
        #
        #  The Stripped-User-Name is updated so that it is logged in
        #  the various "username" fields.  This logging means that you
        #  can associate a particular session with a particular client
        #  certificate.
        #
#       if (&EAP-Message && !&Stripped-User-Name && &TLS-Client-Cert-Serial) {
#               update request {
#                       &Stripped-User-Name := "%{%{TLS-Client-Cert-Subject-Alt-Name-Email}:-%{%{TLS-Client-Cert-Common-Name}:-%{TLS-Client-Cert-Serial}}}"
#               }
#
                #
                #  Create a Class attribute which is a hash of a bunch
                #  of information which we hope exists.  This
                #  attribute should be echoed back in
                #  Accounting-Request packets, which will let the
                #  administrator correlate authentication and
                #  accounting.
                #
#               update reply {
#                       Class += "%{md5:%{Calling-Station-Id}%{Called-Station-Id}%{TLS-Client-Cert-Subject-Alt-Name-Email}%{TLS-Client-Cert-Common-Name}%{TLS-Client-Cert-Serial}%{NAS-IPv6-Address}%{NAS-IP-Address}%{NAS-Identifier}%{NAS-Port}"
#               }
#
#       }

        #
        #  For EAP-TTLS and PEAP, add the cached attributes to the reply.
        #  The "session-state" attributes are automatically cached when
        #  an Access-Challenge is sent, and automatically retrieved
        #  when an Access-Request is received.
        #
        #  The session-state attributes are automatically deleted after
        #  an Access-Reject or Access-Accept is sent.
        #
        #  If both session-state and reply contain a User-Name attribute, remove
        #  the one in the reply if it is just a copy of the one in the request, so
        #  we don't end up with two User-Name attributes.

        if (session-state:User-Name && reply:User-Name && request:User-Name && (reply:User-Name == request:User-Name)) {
                update reply {
                        &User-Name !* ANY
                }
        }
        update {
                &reply: += &session-state:
        }

        #
        #  Refresh leases when we see a start or alive. Return an address to
        #  the IP Pool when we see a stop record.
        #
        #  Ensure that &control:Pool-Name is set to determine which
        #  pool of IPs are used.
#       sqlippool


        #  Create the CUI value and add the attribute to Access-Accept.
        #  Uncomment the line below if *returning* the CUI.
#       cui

        #  Create empty accounting session to make simultaneous check
        #  more robust. See the accounting queries configuration in
        #  raddb/mods-config/sql/main/*/queries.conf for details.
        #
        #  The "sql_session_start" policy is defined in
        #  raddb/policy.d/accounting.  See that file for more details.
#       sql_session_start

        #
        #  If you want to have a log of authentication replies,
        #  un-comment the following line, and enable the
        #  'detail reply_log' module.
#       reply_log

        #
        #  After authenticating the user, do another SQL query.
        #
        #  See "Authentication Logging Queries" in mods-available/sql
        -sql

        #
        #  Un-comment the following if you want to modify the user's object
        #  in LDAP after a successful login.
        #
#       ldap

        # For Exec-Program and Exec-Program-Wait
        exec

        #
        #  In order to calcualate the various keys for old style WiMAX
        #  (non LTE) you will need to define the WiMAX NAI, usually via
        #
        #       update request {
        #              &WiMAX-MN-NAI = "%{User-Name}"
        #       }
        #
        #  If you want various keys to be calculated, you will need to
        #  update the reply with "template" values.  The module will see
        #  this, and replace the template values with the correct ones
        #  taken from the cryptographic calculations.  e.g.
        #
        #       update reply {
        #               &WiMAX-FA-RK-Key = 0x00
        #               &WiMAX-MSK = "%{reply:EAP-MSK}"
        #       }
        #
        #  You may want to delete the MS-MPPE-*-Keys from the reply,
        #  as some WiMAX clients behave badly when those attributes
        #  are included.  See "raddb/modules/wimax", configuration
        #  entry "delete_mppe_keys" for more information.
        #
        #  For LTE style WiMAX you need to populate the following with the
        #  relevant values:
        #    control:WiMAX-SIM-Ki
        #    control:WiMAX-SIM-OPc
        #    control:WiMAX-SIM-AMF
        #    control:WiMAX-SIM-SQN
        #
#       wimax

        #  If there is a client certificate (EAP-TLS, sometimes PEAP
        #  and TTLS), then some attributes are filled out after the
        #  certificate verification has been performed.  These fields
        #  MAY be available during the authentication, or they may be
        #  available only in the "post-auth" section.
        #
        #  The first set of attributes contains information about the
        #  issuing certificate which is being used.  The second
        #  contains information about the client certificate (if
        #  available).
#
#       update reply {
#              Reply-Message += "%{TLS-Cert-Serial}"
#              Reply-Message += "%{TLS-Cert-Expiration}"
#              Reply-Message += "%{TLS-Cert-Subject}"
#              Reply-Message += "%{TLS-Cert-Issuer}"
#              Reply-Message += "%{TLS-Cert-Common-Name}"
#              Reply-Message += "%{TLS-Cert-Subject-Alt-Name-Email}"
#
#              Reply-Message += "%{TLS-Client-Cert-Serial}"
#              Reply-Message += "%{TLS-Client-Cert-Expiration}"
#              Reply-Message += "%{TLS-Client-Cert-Subject}"
#              Reply-Message += "%{TLS-Client-Cert-Issuer}"
#              Reply-Message += "%{TLS-Client-Cert-Common-Name}"
#              Reply-Message += "%{TLS-Client-Cert-Subject-Alt-Name-Email}"
#       }

        #  Insert class attribute (with unique value) into response,
        #  aids matching auth and acct records, and protects against duplicate
        #  Acct-Session-Id. Note: Only works if the NAS has implemented
        #  RFC 2865 behaviour for the class attribute, AND if the NAS
        #  supports long Class attributes.  Many older or cheap NASes
        #  only support 16-octet Class attributes.
#       insert_acct_class

        #  MacSEC requires the use of EAP-Key-Name.  However, we don't
        #  want to send it for all EAP sessions.  Therefore, the EAP
        #  modules put required data into the EAP-Session-Id attribute.
        #  This attribute is never put into a request or reply packet.
        #
        #  Uncomment the next few lines to copy the required data into
        #  the EAP-Key-Name attribute
#       if (&reply:EAP-Session-Id) {
#               update reply {
#                       EAP-Key-Name := &reply:EAP-Session-Id
#               }
#       }

        #  Remove reply message if the response contains an EAP-Message
        remove_reply_message_if_eap

        #
        #  Access-Reject packets are sent through the REJECT sub-section of the
        #  post-auth section.
        #
        #  Add the ldap module name (or instance) if you have set
        #  'edir = yes' in the ldap module configuration
        #
        #  The "session-state" attributes are not available here.
        #
        Post-Auth-Type REJECT {
                # log failed authentications in SQL, too.
                -sql
                attr_filter.access_reject

                # Insert EAP-Failure message if the request was
                # rejected by policy instead of because of an
                # authentication failure
                eap

                #  Remove reply message if the response contains an EAP-Message
                remove_reply_message_if_eap
        }

        #
        #  Filter access challenges.
        #
        Post-Auth-Type Challenge {
#               remove_reply_message_if_eap
#               attr_filter.access_challenge.post-auth
        }

        #
        #  The Client-Lost section will be run for a request when
        #  FreeRADIUS has given up waiting for an end-users client to
        #  respond. This is most useful for logging EAP sessions where
        #  the client stopped responding (likely because the
        #  certificate was not acceptable.)  i.e. this is not for
        #  RADIUS clients, but for end-user systems.
        #
        #  This will only be triggered by new packets arriving,
        #  and will be run at some point in the future *after* the
        #  original request has been discarded.
        #
        #  Therefore the *ONLY* attributes that are available here
        #  are those in the session-state list. If you want data
        #  to log, make sure it is copied to &session-state:
        #  before the client stops responding. NONE of the other
        #  original attributes (request, reply, etc) will be
        #  available.
        #
        #  This section will only be run if postauth_client_lost
        #  is enabled in the main configuration in radiusd.conf.
        #
        #  Note that there are MANY reasons why an end users system
        #  might not respond:
        #
        #    * it could not get the packet due to firewall issues
        #    * it could not get the packet due to a lossy network
        #    * the users system might not like the servers cert
        #    * the users system might not like something else...
        #
        #  In some cases, the client is helpful enough to send us a
        #  TLS Alert message, saying what it doesn't like about the
        #  certificate.  In other cases, no such message is available.
        #
        #  All that we can know on the FreeRADIUS side is that we sent
        #  an Access-Challenge, and the client never sent anything
        #  else.  The reasons WHY this happens are buried inside of
        #  the logs on the client system.  No amount of looking at the
        #  FreeRADIUS logs, or poking the FreeRADIUS configuration
        #  will tell you why the client gave up.  The answers are in
        #  the logs on the client side.  And no, the FreeRADIUS team
        #  didn't write the client, so we don't know where those logs
        #  are, or how to get at them.
        #
        #  Information about the TLS state changes is in the
        #  &session-state:TLS-Session-Information attribute.
        #
        Post-Auth-Type Client-Lost {
                #
                #  Debug ALL of the TLS state changes done during the
                #  EAP negotiation.
                #
#               %{debug_attr:&session-state:TLS-Session-Information[*]}

                #
                #  Debug the LAST TLS state change done during the EAP
                #  negotiation.  For errors, this is usually a TLS
                #  alert from the client saying something like
                #  "unknown CA".
                #
#               %{debug_attr:&session-state:TLS-Session-Information[n]}

                #
                #  Debug the last module failure message.  This may be
                #  useful, or it may refer to a server-side failure
                #  which did not cause the client to stop talking to the server.
                #
#               %{debug_attr:&session-state:Module-Failure-Message}
        }

        #
        #  If the client sends EAP-Key-Name in the request,
        #  then echo the real value back in the reply.
        #
        if (EAP-Key-Name && &reply:EAP-Session-Id) {
                update reply {
                        &EAP-Key-Name := &reply:EAP-Session-Id
                }
        }
}

#
#  When the server decides to proxy a request to a home server,
#  the proxied request is first passed through the pre-proxy
#  stage.  This stage can re-write the request, or decide to
#  cancel the proxy.
#
#  Before this section is run, the request list is copied to the
#  proxy list.  The proxied packet can be edited by examining
#  or changing attributes in the proxy list.
#
#  Only a few modules currently have this method.
#
pre-proxy {
        #  Some supplicants will aggressively retry after an Access-Reject,
        #  contrary to standards. You can avoid sending excessive load to home
        #  servers that based on recent history is likely to only result in
        #  further authentication failures by calling the proxy_rate_limit
        #  module here and in the post-proxy section.
        #
        #  If a request is send too soon after a home server returned an
        #  Access-Reject, then instead of proxying a request a Access-Reject
        #  will be returned.
        #
        #  The principle is to expend a small amount of resources at the edge
        #  (an in-memory cache of recent rejects for calling stations) to
        #  defend the limited processing and network resources at the core.
        #
        #  The strategy can be tuned in the module configuration.
        #
#       proxy_rate_limit

        # Before proxing the request add an Operator-Name attribute identifying
        # if the operator-name is found for this client.
        # No need to uncomment this if you have already enabled this in
        # the authorize section.
#       operator-name

        #  The client requests the CUI by sending a CUI attribute
        #  containing one zero byte.
        #  Uncomment the line below if *requesting* the CUI.
#       cui

        #  Uncomment the following line if you want to change attributes
        #  as defined in the preproxy_users file.
#       files

        #  Uncomment the following line if you want to filter requests
        #  sent to remote servers based on the rules defined in the
        #  'attrs.pre-proxy' file.
#       attr_filter.pre-proxy

        #  If you want to have a log of packets proxied to a home
        #  server, un-comment the following line, and the
        #  'detail pre_proxy_log' section, above.
#       pre_proxy_log
}

#
#  When the server receives a reply to a request it proxied
#  to a home server, the request may be massaged here, in the
#  post-proxy stage.
#
#  Before this section is run, all attributes in the reply list
#  are deleted.  This section can then examine or edit the
#  proxy_reply list.  Once this section is finished, the attributes
#  in the proxy_reply list are copied to the reply list.
#
post-proxy {

        #  If you want to have a log of replies from a home server,
        #  un-comment the following line, and the 'detail post_proxy_log'
        #  section, above.
#       post_proxy_log

        #  Uncomment the following line if you want to filter replies from
        #  remote proxies based on the rules defined in the 'attrs' file.
#       attr_filter.post-proxy

        #
        #  The EAP module will perform some validation of proxied EAP
        #  packets.  Malformed EAP packets will be rejected, and will
        #  not be proxied.
        #
        #  This configuration is most useful to prevent bad
        #  supplicants or APs from attacking the proxies and home
        #  servers.
        #
#       eap

        #  If proxied requests are to be rate limited, then the
        #  proxy_rate_limit module must be called here to maintain a
        #  record of proxy responses.
        #
#       proxy_rate_limit

        #
        #  If the server tries to proxy a request and fails, then the
        #  request is processed through the modules in this section.
        #
        #  The main use of this section is to permit robust proxying
        #  of accounting packets.  The server can be configured to
        #  proxy accounting packets as part of normal processing.
        #  Then, if the home server goes down, accounting packets can
        #  be logged to a local "detail" file, for processing with
        #  radrelay.  When the home server comes back up, radrelay
        #  will read the detail file, and send the packets to the
        #  home server.
        #
        #  See the "mods-available/detail.example.com" file for more
        #  details on writing a detail file specifically for one
        #  destination.
        #
        #  See the "sites-available/robust-proxy-accounting" virtual
        #  server for more details on reading this "detail" file.
        #
        #  With this configuration, the server always responds to
        #  Accounting-Requests from the NAS, but only writes
        #  accounting packets to disk if the home server is down.
        #
#       Post-Proxy-Type Fail-Accounting {
#               detail.example.com

                #
                #  Ensure a response is sent to the NAS now that the
                #  packet has been written to a detail file.
                #
#               acct_response
#       }
}
}
EOF
# Create RADIUS Containerfile
cat <<EOF > radiusdContainerfile
FROM docker.io/freeradius/freeradius-server:latest
RUN apt-get update && apt-get install -y iproute2 freeradius-utils
COPY ./clients.conf /etc/raddb/clients.conf
COPY ./authorize /etc/raddb/mods-config/files/authorize
COPY ./dictionary.nile /usr/share/freeradius/dictionary.nile
COPY ./default /etc/freeradius/sites-available/default 
RUN cd /etc/raddb/certs && rm *.pem *.key *.crt *.p12 *.txt *.crl *.der *.old *.csr *.mk && ./bootstrap
EOF

#check pem file openssl x509 -in certificate.pem -text -noout

# Create RADIUSD Image
docker build -t radiusd -f radiusdContainerfile .
echo "RADIUSD Image has been created"
echo "--------------------------------------------------------------"

# Loop through all pods
echo "Creating Pod"
generate_frr_config
create_frr_container
create_dhcpd_container
create_radiusd_container
echo "=========================================================="

echo "✅ Setup complete for pods."
echo ""
echo "______________________________________________________________"
echo "| NSB's Default Gateway: $lan_ip                             |"
echo "|          NSB's Subnet: $lan_subnet                         |"
echo "|        DHCP Server IP: $lan_ip                             |"
echo "|      RADIUS Server IP: $lan_ip                             |"
echo "|____________________________________________________________|"