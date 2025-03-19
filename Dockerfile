ARG MATTERMOST_IMAGE_TAG=latest

FROM mattermost/mattermost-team-edition:${MATTERMOST_IMAGE_TAG}

# Switch to root user to install iptables
USER root

# Install iptables and clean up afterwards
RUN mkdir -p /var/lib/apt/lists/partial && apt-get update && apt-get install -y --no-install-recommends iptables && rm -r /var/lib/apt/lists/*

# Switch back to correct user
USER mattermost

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
