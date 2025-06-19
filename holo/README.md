# Mattermost Docker for Holo

This repository contains a hardened, production-ready Docker deployment solution for Mattermost Team Edition, adapted for Holo/chain's self-hosting on Hetzner Cloud. It is a fork of the official Mattermost Docker setup, with significant additions for security, operational management, and a clear deployment/upgrade path.

## Key Features & Hardening Measures

*   **Secrets Management:** Secrets in `.env` files are protected with [Agebox](https://github.com/slok/agebox), an `age`-based repository file encryption tool.
*   **Leak Prevention:** [Gitleaks](https://github.com/gitleaks/gitleaks) is implemented as a pre-commit hook to prevent accidental commitment of secrets.
*   **Container Sandboxing:** Uses [Sysbox](https://github.com/nestybox/sysbox) (`sysbox-runc`) as the container runtime for enhanced isolation and security.
*   **Intrusion Prevention:** Implements [CrowdSec](https://crowdsec.net/) to monitor Nginx logs and ban malicious IPs at the firewall level.
*   **Network Segmentation:** Utilizes separate Docker networks (`frontend`, `backend`, `monitoring`) to isolate services.
*   **Image Update Management:** Automatic updates are disabled (no `watchtower`). Image versions are explicitly defined in the `.env` file for controlled upgrades.
*   **System Hardening:**
    *   Host-level hardening via `sysctl` (`holo/99-hardening.conf`).
    *   Hardening-specific audit rules for `auditd` (`holo/hardening.rules`).
    *   Host firewall configured with `iptables` to be Docker-compatible, using the `DOCKER-USER` chain.
*   **Least Privilege:**
    *   Containers do not run as root where official images are available.
    *   Unnecessary kernel capabilities (`NET_RAW`, `SYS_CHROOT`) are dropped from services.
    *   Does not use `--privileged` or `--network host`.
*   **Operational Tooling:** Includes `Diun` for Docker image update notifications and custom backup/restore scripts.

---

## Deployment & Operation

This section covers the installation of a new Mattermost instance from scratch and the process for performing version upgrades.

### 1. Initial Host Setup

These steps are for creating a new server. If you have an existing host with Docker, Docker Compose, and your preferred firewall (`iptables`), you can skip to the next section.

1.  **Create Hetzner Cloud Server:**
    - `[ ]` Use the `hcloud` CLI to create a server. Ubuntu with the `docker-ce` image is recommended.
        ```bash
        hcloud server create --name mm-docker --location hel1 --type ccx23 --image docker-ce
        ```
2.  **Initial Server Login & Security:**
    - `[ ]` Immediately `ssh` to the server using the provided root password.
    - `[ ]` Set up SSH key authentication for your user.
    - `[ ]` **Disable root SSH login and password-based SSH authentication** in `/etc/ssh/sshd_config`.
3.  **Install Prerequisites:**
    - `[ ]` Install `agebox`, `git`, `tmux` (or `screen`), `aws-cli`, `pv`, and `iptables-persistent`.
        ```bash
        sudo apt update
        sudo apt install -y agebox git tmux pv iptables-persistent awscli
        ```
    - `[ ]` Install Sysbox container runtime by following the [official Sysbox installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install.md). After installation, restart the Docker daemon: `sudo systemctl restart docker`.
4.  **Configure Host Firewall (`iptables`):**
    - `[ ]` **Gotcha:** `ufw` conflicts with Docker's `iptables` rules. Use `iptables` directly.
    - `[ ]` Use the `setup_firewall.sh` script from this repository to configure your firewall rules. **You must edit the script first** to set your `<EXTERNAL_INTERFACE>` and SSH source IP. Always have out-of-band console access ready when applying firewall rules.
    - `[ ]` The script should use the `DOCKER-USER` chain to allow inbound traffic for `HTTP` (80), `HTTPS` (443), and the Mattermost Calls port (`8443`), and should persist the rules using `iptables-persistent`.
5.  **Enable IP Forwarding:**
    - `[ ]` Docker networking requires IP forwarding. Ensure it's enabled persistently.
        ```bash
        # Create a conf file to ensure the setting persists after reboot
        echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-docker-forward.conf
        # Apply immediately
        sudo sysctl -p /etc/sysctl.d/99-docker-forward.conf
        ```
6.  **Clone Repository:**
    - `[ ]` `git clone <your-repo-url> ~/mattermost-docker`

### 2. Secrets Management (`agebox`)

This project uses `agebox` with `age` keys. The intended workflow uses a `./keys` directory in the repository for recipient public keys.

- **Local Setup (Your Machine):**
    - `[ ]` Your personal `age` private key should be in `~/.config/sops/age/keys.txt` to align with `sops` conventions.
- **Server Setup:**
    - `[ ]` Each server (production, test) should have **only its own unique private key** in `/root/.config/age/keys.txt` (or a user's home directory if not running as root).
- **Usage:**
    - `[ ]` **Encrypting:** Create a `./keys` directory in the repo root. Add recipient public key files (`.pub`). Run `agebox encrypt <file>` to encrypt for all recipients.
    - `[ ]` **Decrypting (Deployment):** Use `agebox cat <file.agebox> > <file>`. This is non-destructive to the source `.agebox` file. On your local machine, you may need to specify your key with `-i`: `agebox cat -i ~/.config/sops/age/keys.txt <file.agebox> > <file>`.

### 3. Deploying a New Mattermost Instance

1.  **Prepare `.env` file:**
    - `[ ]` In the `mattermost-docker` directory, decrypt the `.env.agebox` template: `agebox cat .env.agebox > .env`.
    - `[ ]` Edit `.env` and fill in all required values (domain, passwords, S3 details, etc.). Set the desired `MATTERMOST_IMAGE_TAG` (e.g., `10.5.8`).
    - `[ ]` **Gotcha:** Your `docker-compose.harden.yml` requires runtime environment variables (like `MM_SQLSETTINGS_DATASOURCE` and `MM_SERVICESETTINGS_COLLAPSEDTHREADS`) to be explicitly passed. Ensure they are listed in the `environment:` section for the `mattermost` service.
2.  **Take a Database Backup (if migrating from existing system):**
    - `[ ]` Use the `backup_prod_db.sh` script to get a `.sql.gz` dump of your existing database and upload it to S3.
3.  **Start PostgreSQL & Restore Database:**
    - `[ ]` `docker compose -f docker-compose.harden.yml up -d postgres`
    - `[ ]` Use `tmux` or `screen` for the restore.
    - `[ ]` Run the `restore_mattermost_db.sh` script, providing the backup filename. It will download from S3 and pipe into the Postgres container.
4.  **Start the Full Stack:**
    - `[ ]` `docker compose -f docker-compose.harden.yml up -d`
    - `[ ]` Monitor logs (`docker compose -f ... logs -f mattermost`) for successful startup.
5.  **Generate TLS Certificate:**
    - `[ ]` Ensure your domain's DNS record points to the new server's IP and has propagated.
    - `[ ]` **Gotcha:** If a DNS-level redirect from HTTP->HTTPS is active, Certbot's `standalone` challenge will fail. Disable it at your DNS provider.
    - `[ ]` Stop Nginx to free port 80: `docker compose -f ... stop nginx`.
    - `[ ]` Run the `scripts/issue-certificate.sh` script.
    - `[ ]` Update `CERT_PATH` and `KEY_PATH` in `.env` to point to the newly generated certificate files. **Gotcha:** Certbot may create a `-0001` suffixed directory; use the most recent one.
    - `[ ]` Restart Nginx: `docker compose -f ... up -d --force-recreate nginx`.
6.  **Final Verification:**
    - `[ ]` Access your Mattermost URL via HTTPS.
    - `[ ]` Log in and perform smoke tests.

### 4. Upgrading an Existing Mattermost Instance

The process is much simpler for an in-place upgrade.

1.  **Announce Maintenance:**
    - `[ ]` Inform users of a brief (~30 min) maintenance window.
2.  **Take Production Backup:**
    - `[ ]` Run the `backup_prod_db.sh` script inside a `tmux` session to create a pre-upgrade recovery point.
3.  **Update `.env` file:**
    - `[ ]` Edit the production `.env` file. Change `MATTERMOST_IMAGE_TAG` to the new target ESR version (e.g., `10.5.8`).
4.  **Perform the Upgrade:**
    - `[ ]` `docker compose -f docker-compose.harden.yml stop mattermost`
    - `[ ]` `docker compose -f docker-compose.harden.yml pull mattermost`
    - `[ ]` `docker compose -f docker-compose.harden.yml up -d mattermost`
5.  **Monitor Logs:**
    - `[ ]` **Crucial:** Watch the logs (`docker compose -f ... logs -f mattermost`) to see the database schema migrations being applied. Wait for the "Server is listening" message.
6.  **Verification & Deactivation (if needed):**
    - `[ ]` **Gotcha:** Upgrading to v10+ may trigger a safety limit warning if you have >2,500 users. If so, `exec` into the `postgres` container and run the `UPDATE` query (tested previously) to deactivate inactive users based on `lastlogin`.
    - `[ ]` Restart Mattermost after deactivation: `docker compose -f ... restart mattermost`.
    - `[ ]` Log in, check the version in "About Mattermost," and verify functionality.
7.  **Announce Completion:**
    - `[ ]` Inform users that maintenance is complete.

---

## FAQ & Lessons Learned

- **Why `iptables` instead of `ufw`?**
    - `ufw` often conflicts with the `iptables` rules that Docker dynamically creates for networking and port mapping. Managing rules directly with `iptables` and adding custom rules to the `DOCKER-USER` chain is the most reliable way to create a secure host firewall that coexists with Docker.
- **Why did my `docker compose` command fail with `service "postgres" is not running`?**
    - `docker compose` is context-aware. If you run it from a subdirectory, it may not find the project's running containers. **Solution:** Always run `docker compose` commands with the `-f docker-compose.harden.yml` flag to explicitly define the project context.
- **Why did Nginx fail to start with a certificate error?**
    - **Reason 1 (Most Common):** The certificate file doesn't exist yet. You must generate it with Certbot *after* your DNS points to the server.
    - **Reason 2 (File vs. Directory):** If a volume mount's *source* path doesn't exist, Docker creates it as a directory. Your `.env`'s `CERT_PATH` might have pointed to a non-existent file, causing Docker to create a `fullchain.pem` **directory**, which Nginx cannot read as a certificate. **Solution:** Delete the incorrect directory (`sudo rm -rf ...`) and generate the cert correctly.
    - **Reason 3 (Path Mismatch):** Certbot created the certificate in one location (e.g., in a `-0001` suffixed directory), but your `.env` `CERT_PATH` pointed to another. **Solution:** Always update `.env` to the exact, absolute path of the *most recently generated* certificate.
- **Why did `certbot` fail with `NXDOMAIN`?**
    - The DNS record for your domain (`A` or the target of your `CNAME`) had not propagated globally, or was configured incorrectly. **Solution:** Use an external tool like `dnschecker.org` and wait until the correct IP is visible worldwide before running Certbot.
- **Why did `certbot` fail with a `404` or `Timeout` on port 80?**
    - **Timeout:** A firewall (host-level `iptables` or network-level like Hetzner's) was blocking port 80.
    - **404:** A DNS-level redirect was forcing `http://` traffic to `https://`. Certbot's `standalone` authenticator only works on HTTP. **Solution:** Disable DNS-level forwarding/redirects.
- **Why did my variables from `.env.test` not appear in the container?**
    - For this specific Docker Compose setup, we found that runtime variables for the Mattermost application (`MM_...` variables) needed to be explicitly passed through. **Solution:** Add the variable name (e.g., `MM_SQLSETTINGS_DATASOURCE`) to the `environment:` list for the `mattermost` service in `docker-compose.harden.yml`.
