# Mattermost Docker for Holo
The official Docker deployment solution for Mattermost adapted for Holo/chain.

This has meant the following changes/additions:
- Secrets in `.env` are being protected with [Agebox](https://github.com/slok/agebox), an Age based repository file encryption gitops tool.
- [Gitleaks](https://github.com/gitleaks/gitleaks) has been implemented as a pre-commit hook to prevent the accidental commitment of hardcoded secrets to the repo.
- Documentation of Hetzner Cloud host creation using `hcloud`.
- Restart policy is set to `always` and specified Postgres image is `14-alpine` for compatibility with existing MM database.
- Target [server release](https://docs.mattermost.com/about/mattermost-server-releases.html) is Mattermost Team Edition Extended Support Release(ESR) 9.5.13.  The intention is to migrate to the 10.5 ESR series in the next quarterly upgrade cycle.
- No auto-update for images. Have completely removed `watchtower` from `docker-compose.yml`.
- Run only rootless containers (check [dockerfile] for `USER` statement)
- Use proxies with simple ingress rules to prevent abuse and spam (rate limit, geo block).  Using nginx as the reverse proxy for Mattermost.
- Implemented Docker-specific audit rules for `auditd`.
- No `--privileged`
- No `--network host` and no `--id 0`
**Not yet implemented:**
- No WAN access to any container unless needed, if needed put in separate MACLVAN or IPVLAN on different VLAN
- Use `--internal`
- Use AppArmor profiles
- Document actions taken as a result of mitigating issues surfaced by docker-bench-security and am-i-isolated.

## Security Audits
### Manual
- Ensured Mattermost and Postgres containers do NOT run as root, by reviewing their respective `Dockerfile` definitions.
- The [default Nginx Docker image](https://hub.docker.com/_/nginx) does RUN as root, but drops privileges for the worker processes.  There is an [official unprivileged Nginx image](https://hub.docker.com/r/nginxinc/nginx-unprivileged) available but that could introduce maintenance overhead.  For now, I will consider the dropping of privileges sufficient.
### Automated
- Am I Isolated
- Docker Bench for Security
- Lynis
## Install & Usage
### Hetzner Cloud Host Creation
If you don't already have an existing host or need to create a new one for scaling or disaster recovery, take the following steps.  Otherwise you can skip to the next section.

1. Retrieve or generate a suitable Hetzner Cloud API token using the [Hetzner Cloud Console](https://console.hetzner.cloud/) if necessary.
2. Use the [`hcloud` cli](https://github.com/hetznercloud/cli) to set up a [Hetzner Cloud](https://www.hetzner.com/cloud/) server with pre-installed Docker & Compose on Ubuntu: e.g. `hcloud server create --name mm-docker --location hel1 --type ccx23 --image docker-ce`
3. The result will include an IP address and a root password, so that you can `ssh` into the server.  You should do so immediately and setup SSH Key Authentication and prohibit the use of a password for Root SSH login.

### Mattermost Backup and Restore: AWS Migration Edition
1. Obtain a `pg_dump` compatible backup of your Mattermost database.  The following script (adapted from [rds-s3-database-backup](https://github.com/bamf-health/rds-s3-database-backup)) will work with an existing AWS RDS hosted Mattermost database:
```
#!/bin/sh
# Set default connection parameters for pg_dump
PGHOST=${PROD}
PGUSER=${PGUSER:-mmuser}
PGDATABASE=${PGDATABASE:-mattermost}
S3_BUCKET=${S3_BUCKET:-db.dr1.chat.holo.host}

DATE=$(date "+%Y-%m-%d-%H%M")
TARGET=s3://${S3_BUCKET}/${PGDATABASE}-${DATE}.sql.gz

echo Backing up ${PGHOST}/${PGDATABASE} to ${TARGET}

# export PGPASSWORD=${DATABASE_PASSWORD}
pg_dump --clean -Z 9 -v -h ${PGHOST} -U ${PGUSER} -d ${PGDATABASE} | aws s3 cp --storage-class STANDARD_IA --sse aws:kms - ${TARGET}
```
2. The resulting dump is stored in AWS S3.  It can be restored thusly on the destination server, `aws s3 cp s3://db.dr1.chat.holo.host - | gunzip | psql`
3. Take a copy of `config/config.json`.  In our case, we also had to extract all the customizations in that file and replicate them in `docker-compose.yml` and `.env`.
4. No need to backup stored files, since we are using S3 for that.

### Mattermost deployment to Hetzner Cloud Host
Refer to the [Mattermost Docker deployment guide](https://docs.mattermost.com/install/install-docker.html) for detailed instructions on how to deploy Mattermost to the newly created server. The following are the abbreviated steps:

## Key Resources
- [Migrate Mattermost from one server to another](https://docs.mattermost.com/onboard/migrating-to-mattermost.html#migrate-mattermost-from-one-server-to-another): Migrate Mattermost from one server to another by backing up and restoring the Mattermost database and `config.json` file.
- [Mattermost backup and disaster recovery](https://docs.mattermost.com/deploy/backup-disaster-recovery.html)
- [PostgreSQL SQL Dump](https://www.postgresql.org/docs/14/backup-dump.html)
- [Mattermost Docker](https://github.com/mattermost/docker) is the official Docker deployment solution for Mattermost. It references [Deploy Mattermost via Docker](https://docs.mattermost.com/install/install-docker.html) using a Docker Compose deployment method that "is not recommended for production environments" out of the box.
- [Use Compose in Production](https://docs.docker.com/compose/how-tos/production/) provides advice on creating a production-ready app configuration using Docker Compose.
- [Docker CE](https://docs.hetzner.com/cloud/apps/list/docker-ce/): Hetzner Cloud App that contains a ready to use Docker with Compose installation.
- [Hetzner Cloud docs](https://docs.hetzner.com/cloud/): Information on Hetzer Cloud products; how to use the Cloud Console; functionality; billing; future plans and how to use the API
- [Run multiple Docker Compose services on Debian/Ubuntu](https://community.hetzner.com/tutorials/docker-compose-as-systemd-service): This tutorial will show you how you can run multiple Docker Compose services via a systemd service template.
- [How to use secrets in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [RDS PostgreSQL](https://pellepelster.github.io/solidblocks/rds/index.html): A containerized PostgreSQL database with an all batteries included backup solution powered by [pgBackRest](https://pgbackrest.org/).
- [Hetzner Cloud | Snapshot-as-Backup](https://github.com/fbrettnich/hcloud-snapshot-as-backup): This script automatically creates snapshots of your Hetzner Cloud Servers and deletes the old ones.


NB: Many of the official supported Mattermost deployment options install Enterprise Edition by default and often omit information on installing Team Edition instead.  For example, [Install Mattermost Omnibus](https://docs.mattermost.com/install/installing-mattermost-omnibus.html) does this.

A tarball of Mattermost Team Edition for Linux can always be obtained like so:
MM_VERSION=10.5.1 wget https://releases.mattermost.com/$MM_VERSION/mattermost-team-$MM_VERSION-linux-amd64.tar.gz
