#!/bin/bash
set -e

echo "Wed Sep  3 05:16:44 PM UTC 2025: Starting DHCP service startup script" >> /var/log/startup.log
echo "Wed Sep  3 05:16:44 PM UTC 2025: Starting DHCP service startup script"

# Start the DHCP server
echo "Wed Sep  3 05:16:44 PM UTC 2025: Executing dhcpd command" >> /var/log/startup.log
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid enx5c857e391ef3

echo "Wed Sep  3 05:16:44 PM UTC 2025: DHCP server started, keeping container alive" >> /var/log/startup.log

# Keep container running
tail -f /var/log/startup.log
