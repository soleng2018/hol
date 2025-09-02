#!/bin/bash
set -e

echo "Tue Sep  2 09:29:21 PM UTC 2025: Starting DHCP service startup script" >> /var/log/startup.log
echo "Tue Sep  2 09:29:21 PM UTC 2025: Starting DHCP service startup script"

# Start the DHCP server
echo "Tue Sep  2 09:29:21 PM UTC 2025: Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid enx5c857e391ef3

echo "Tue Sep  2 09:29:21 PM UTC 2025: DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
