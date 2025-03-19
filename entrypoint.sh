#!/bin/bash

# Add iptables rule to forward DNS traffic to the gateway
sudo iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 172.19.0.1:53
sudo iptables -t nat -A POSTROUTING -j MASQUERADE
sudo iptables -A INPUT -j ACCEPT
sudo iptables -A FORWARD -j ACCEPT

# Execute the ORIGINAL Mattermost entrypoint (VERY IMPORTANT!)
exec /entrypoint.sh "$@"
