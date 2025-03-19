#!/bin/bash

# Add iptables rule to forward DNS traffic to the gateway
iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 172.19.0.1:53
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A INPUT -j ACCEPT
iptables -A FORWARD -j ACCEPT

# Execute the ORIGINAL Mattermost entrypoint (VERY IMPORTANT!)
exec /entrypoint.sh "$@"
