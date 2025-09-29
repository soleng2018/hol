#!/bin/bash
set -e

echo "$(date): Starting V5 Multi Uplink DHCP service startup script" >> /var/log/startup.log
echo "$(date): Starting V5 Multi Uplink DHCP service startup script"

# Start the DHCP server on first interface
echo "$(date): Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid enp3s0

echo "$(date): DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
