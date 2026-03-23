#!/bin/bash
set -e

# Start the DHCP server
/usr/sbin/dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid eth2
