# Mattermost Docker for Holo
The official Docker deployment solution for Mattermost adapted for Holo/chain.

This has meant the following changes/additions:
- Secrets in `.env` are being protected with [Agebox](https://github.com/slok/agebox), an Age based repository file encryption gitops tool.
- [Gitleaks](https://github.com/gitleaks/gitleaks) has been implemented as a pre-commit hook to prevent the accidental commitment of hardcoded secrets to the repo.
- Documentation of Hetzner Cloud host creation using `hcloud`.

## Install & Usage
### Hetzner Cloud Host Creation
If you don't already have an existing host or need to create a new one for scaling or disaster recovery, take the following steps.  Otherwise you can skip to the next section.

1. Retrieve or generate a suitable Hetzner Cloud API token using the [Hetzner Cloud Console](https://console.hetzner.cloud/) if necessary.
2. Use the [`hcloud` cli](https://github.com/hetznercloud/cli) to set up a [Hetzner Cloud](https://www.hetzner.com/cloud/) server with pre-installed Docker & Compose on Ubuntu: e.g. `hcloud server create --name mm-docker --location hel1 --type ccx23 --image docker-ce`
3. The result will include an IP address and a root password, so that you can `ssh` into the server.  You should do so immediately and setup SSH Key Authentication and prohibit the use of a password for Root SSH login.

### Mattermost deployment to Hetzner Cloud Host
Refer to the [Mattermost Docker deployment guide](https://docs.mattermost.com/install/install-docker.html) for detailed instructions on how to deploy Mattermost to the newly created server. The following are the abbreviated steps:

## Key Resources
- [Mattermost Docker](https://github.com/mattermost/docker) is the official Docker deployment solution for Mattermost. It references [Deploy Mattermost via Docker](https://docs.mattermost.com/install/install-docker.html) using a Docker Compose deployment method that "is not recommended for production environments" out of the box.
- [Use Compose in Production](https://docs.docker.com/compose/how-tos/production/) provides advice on creating a production-ready app configuration using Docker Compose.
- [Docker CE](https://docs.hetzner.com/cloud/apps/list/docker-ce/): Hetzner Cloud App that contains a ready to use Docker with Compose installation.
- [Hetzner Cloud docs](https://docs.hetzner.com/cloud/): Information on Hetzer Cloud products; how to use the Cloud Console; functionality; billing; future plans and how to use the API
- [Run multiple Docker Compose services on Debian/Ubuntu](https://community.hetzner.com/tutorials/docker-compose-as-systemd-service): This tutorial will show you how you can run multiple Docker Compose services via a systemd service template.
- [How to use secrets in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/)

NB: Many of the official supported Mattermost deployment options install Enterprise Edition by default and often omit information on installing Team Edition instead.  For example, [Install Mattermost Omnibus](https://docs.mattermost.com/install/installing-mattermost-omnibus.html) does this.

A tarball of Mattermost Team Edition for Linux can always be obtained like so:
MM_VERSION=10.5.1 wget https://releases.mattermost.com/$MM_VERSION/mattermost-team-$MM_VERSION-linux-amd64.tar.gz
