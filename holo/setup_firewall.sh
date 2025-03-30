#!/bin/bash

# --- Configuration Placeholders ---
TRUSTED_SSH_SOURCE="103.7.206.76/32" # Example: "1.2.3.4/32" for a single IP, "1.2.3.0/24" for a subnet
EXTERNAL_INTERFACE="eth0"            # Example: "eth0"
CALLS_PORT="8443"                                   # Example: Get this from your .env file (ensure it's just the number)
# !!! END OF VALUES TO REPLACE !!!


echo ">>> Applying iptables rules..."

# Flush existing rules and chains to ensure a clean state
# WARNING: This will drop existing connections if not handled carefully.
# Best run when no critical connections are active besides your SSH session.
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
echo " flushed existing rules and chains."

# Set default policies: Drop incoming/forwarding, Allow outgoing
iptables -P INPUT DROP
iptables -P FORWARD DROP # Default drop for traffic passing through (incl. Docker unless allowed)
iptables -P OUTPUT ACCEPT # Allow all outgoing connections from the host
echo " default policies set (INPUT/FORWARD DROP, OUTPUT ACCEPT)."

# Allow loopback traffic (essential for many services)
iptables -A INPUT -i lo -j ACCEPT
echo " loopback traffic allowed."

# Allow already established and related connections (essential for return traffic)
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT # Needed for Docker forwarded traffic return
echo " established/related connections allowed (INPUT/FORWARD)."

# --- Application Specific Rules ---

# Allow SSH access
# **IMPORTANT**: Restrict source IP if possible!
iptables -A INPUT -p tcp --dport 22 -s ${TRUSTED_SSH_SOURCE} -j ACCEPT
echo " SSH allowed from ${TRUSTED_SSH_SOURCE}."
# Fallback (less secure) - Allow SSH from anywhere:
# iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# echo " WARNING: SSH allowed from ANY source."

# Allow ICMP (Ping requests) - Optional, uncomment if needed
# iptables -A INPUT -p icmp --icmp-type 8 -j ACCEPT
# echo " ICMP Echo Requests (Ping) allowed."

# --- Docker Integration using DOCKER-USER Chain ---
# Rules inserted here are processed *before* Docker's automatic rules.
# Assumes the DOCKER-USER chain exists (Docker creates it).

echo " inserting rules into DOCKER-USER chain for external access..."

# Allow incoming HTTP (Port 80) - Needed for Let's Encrypt HTTP-01 and redirects
# Use -I to insert at the beginning of the chain
iptables -I DOCKER-USER -i ${EXTERNAL_INTERFACE} -p tcp -m conntrack --ctstate NEW --dport 80 -j ACCEPT
echo "  - Allowed HTTP (80/tcp) via DOCKER-USER."

# Allow incoming HTTPS (Port 443) - For Mattermost web access
iptables -I DOCKER-USER -i ${EXTERNAL_INTERFACE} -p tcp -m conntrack --ctstate NEW --dport 443 -j ACCEPT
echo "  - Allowed HTTPS (443/tcp) via DOCKER-USER."

# Allow incoming Mattermost Calls Port (TCP & UDP)
if [[ -n "${CALLS_PORT}" ]]; then
	  iptables -I DOCKER-USER -i ${EXTERNAL_INTERFACE} -p tcp -m conntrack --ctstate NEW --dport ${CALLS_PORT} -j ACCEPT
	    iptables -I DOCKER-USER -i ${EXTERNAL_INTERFACE} -p udp -m conntrack --ctstate NEW --dport ${CALLS_PORT} -j ACCEPT
	      echo "  - Allowed Calls Port (${CALLS_PORT}/tcp+udp) via DOCKER-USER."
      else
	        echo "  - WARNING: CALLS_PORT not set, skipping calls port rule."
fi

# --- Inter-Container Communication (Basic) ---
# Allow traffic between containers on the default 'docker0' bridge.
# Add rules for custom Docker networks if necessary, potentially by interface name (br-xxxx)
# This is often implicitly handled by Docker's rules if FORWARD default policy was ACCEPT,
# but with FORWARD DROP, we need to be more explicit or rely on Docker's rules after DOCKER-USER.
# Allowing established/related in FORWARD helps significantly.
# You might need more specific rules depending on your docker network setup if containers
# across different custom networks need to communicate directly.
iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT
echo " communication allowed within default docker0 bridge."

# --- Logging (Optional - can be very noisy) ---
# Uncomment to log dropped packets to syslog (check /var/log/syslog or journalctl)
# iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "IPTABLES INPUT Denied: " --log-level 7
# iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "IPTABLES FORWARD Denied: " --log-level 7

echo ""
echo ">>> IPTables rules applied."
echo ">>> Use 'sudo iptables -L -v -n' to review rules."
echo ""

# --- Persist Rules ---
echo ">>> Saving rules for persistence (using iptables-persistent)..."
# Create directory if it doesn't exist
sudo mkdir -p /etc/iptables
# Save IPv4 rules
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
# If you configured IPv6 rules with ip6tables, save them too:
# sudo sh -c 'ip6tables-save > /etc/iptables/rules.v6'
echo ">>> Rules saved to /etc/iptables/rules.v4."
echo ">>> Reboot the system to ensure rules persist correctly!"
