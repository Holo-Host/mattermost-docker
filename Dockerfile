ARG MATTERMOST_IMAGE_TAG=latest

FROM mattermost/mattermost-team-edition:${MATTERMOST_IMAGE_TAG}

# Switch to root user to install iptables
USER root

# Install iptables and clean up afterwards
RUN mkdir -p /var/lib/apt/lists/partial && apt-get update && apt-get install -y --no-install-recommends iptables && rm -r /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Force iptables to use the legacy backend
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && update-alternatives --set arptables /usr/sbin/arptables-legacy && update-alternatives --set ebtables /usr/sbin/ebtables-legacy && chmod +x /usr/local/bin/entrypoint.sh

# Switch back to correct user
USER mattermost

