ARG MATTERMOST_IMAGE_TAG=latest

FROM mattermost/mattermost-team-edition:${MATTERMOST_IMAGE_TAG}

# Install iptables
RUN apt update && apt install -y --no-install-recommends iptables

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
