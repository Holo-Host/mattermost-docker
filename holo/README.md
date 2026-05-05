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

This guide covers three primary operations:
1.  **Initial Installation:** Setting up a new Mattermost instance from scratch.
2.  **Upgrading Mattermost:** The safe, test-first process for upgrading an existing production instance.
3.  **Secrets Management:** How to handle encrypted `.env` files with `agebox`.

---

### 1. Initial Installation on a New Host

Follow these steps to deploy Mattermost on a new server.

#### 1.1. Host Setup

1.  **Create Server:** Use the `hcloud` CLI to create a server. Ubuntu with the `docker-ce` image is recommended.
    ```bash
    hcloud server create --name mm-docker --location hel1 --type ccx23 --image docker-ce
    ```
2.  **Initial Login & Security:**
    - `[ ]` Immediately `ssh` to the server using the provided root password.
    - `[ ]` Set up SSH key authentication for your user.
    - `[ ]` **Disable root SSH login and password-based SSH authentication** in `/etc/ssh/sshd_config`.
3.  **Install Prerequisites:**
    - `[ ]` `sudo apt update && sudo apt install -y agebox git tmux pv iptables-persistent awscli`
    - `[ ]` Install Sysbox container runtime following the [official Sysbox installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install.md). Restart Docker after: `sudo systemctl restart docker`.
4.  **Configure Unattended Upgrades (scheduled reboot window):**
    - `[ ]` `sudo cp holo/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades`
    - `[ ]` Verify: `sudo unattended-upgrade --dry-run --debug 2>&1 | grep -i reboot`
4.  **Configure Host Firewall (`iptables`):**
    - `[ ]` Edit the `setup_firewall.sh` script to set your `<EXTERNAL_INTERFACE>` and SSH source IP.
    - `[ ]` Apply the rules: `sudo bash ./setup_firewall.sh`. **Have out-of-band console access ready.**
5.  **Enable IP Forwarding:**
    - `[ ]` `echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-docker-forward.conf`
    - `[ ]` `sudo sysctl -p /etc/sysctl.d/99-docker-forward.conf`
6.  **Clone Repository:**
    - `[ ]` `git clone <your-repo-url> ~/mattermost-docker`

#### 1.2. Application Deployment

1.  **Prepare `.env` file:**
    - `[ ]` `cd ~/mattermost-docker`
    - `[ ]` Decrypt your secrets file. See the **Secrets Management** section below. Example: `agebox cat .env.agebox > .env`.
    - `[ ]` Edit `.env` and fill in all required values (domain, passwords, S3 details, `MATTERMOST_IMAGE_TAG`, etc.).
2.  **Database Restore (if migrating):**
    - `[ ]` If migrating from an old system, obtain a `.sql.gz` backup and place it on this server or in S3.
    - `[ ]` Start the database service: `docker compose -f docker-compose.harden.yml up -d postgres`.
    - `[ ]` Run the `restore_mattermost_db.sh` script inside a `tmux` session, providing the path to your `.env` file and the backup filename.
3.  **Start the Full Stack:**
    - `[ ]` `docker compose -f docker-compose.harden.yml up -d`
    - `[ ]` Monitor logs (`docker compose -f ... logs -f mattermost`) for successful startup.
4.  **Generate TLS Certificate:**
    - `[ ]` Ensure DNS record points to the server's IP and has propagated globally (`dnschecker.org`).
    - `[ ]` Stop Nginx to free port 80: `docker compose -f ... stop nginx`.
    - `[ ]` Run the `scripts/issue-certificate.sh` script.
    - `[ ]` Update `CERT_PATH` and `KEY_PATH` in `.env` to point to the new certificate files. **Note:** Certbot may create a `-0001` suffixed directory; use the most recent one.
    - `[ ]` Restart Nginx: `docker compose -f ... up -d --force-recreate nginx`.
5.  **Final Verification:**
    - `[ ]` Access your Mattermost URL via HTTPS, log in, and perform smoke tests.

---

### 2. Upgrading Mattermost (e.g., 9.5.x -> 10.5.x)

This process follows a safe, two-phase approach: **test first, then upgrade production.**

#### 2.1. Phase 1: Test Upgrade on a Staging Server

**Objective:** Verify the upgrade process, database migrations, and application functionality on a non-production server (`mattermost-0`, domain `chat-ng.holochain.org`) before touching production.

1.  **Prepare Test Environment:**
    - `[ ]` Ensure you have a separate, fully configured test server (`mattermost-0`) set up as per the "Initial Host Setup" guide.
    - `[ ]` Take a fresh backup of the **production** database using the `backup_prod_db.sh` script on the production server.
    - `[ ]` On the test server, decrypt your test environment file: `agebox cat .env.test.agebox > .env.test`.
    - `[ ]` Edit `.env.test` and set `MATTERMOST_IMAGE_TAG` to the new target version (e.g., `10.5.8`).
2.  **Restore Production Data to Test Server:**
    - `[ ]` Start the test Postgres container: `docker compose --env-file .env.test -f docker-compose.harden.yml up -d postgres`.
    - `[ ]` Start a `tmux` session: `tmux new -s mm-test-restore`.
    - `[ ]` Inside `tmux`, run the restore script, pointing it to your test environment file and the production backup filename you just created:
        ```bash
        ./scripts/restore_mattermost_db.sh ../.env.test <production_backup_filename.sql.gz>
        ```
    - `[ ]` Detach (`Ctrl+b`, `d`) and wait for completion.
3.  **Run the Test Upgrade:**
    - `[ ]` Start the full test stack. This will trigger the database migrations.
        ```bash
        docker compose --env-file .env.test -f docker-compose.harden.yml up -d
        ```
    - `[ ]` **Crucial:** Monitor the logs closely (`docker compose --env-file .env.test -f ... logs -f mattermost`) until you see the "Server is listening" message. Note any errors.
4.  **Configure DNS & TLS for Test Domain:**
    - `[ ]` Ensure `chat-ng.holochain.org` DNS points to the test server's IP and has propagated.
    - `[ ]` Generate a TLS certificate for `chat-ng.holochain.org` using the same method as the initial install.
    - `[ ]` Update `.env.test` with the correct `CERT_PATH`/`KEY_PATH` and restart Nginx.
5.  **Verify Test Upgrade:**
    - `[ ]` Access `https://chat-ng.holochain.org`.
    - `[ ]` Log in and confirm the version in "About Mattermost" matches your target.
    - `[ ]` **Test for Safety Limit Warning:** If the `ERROR_SAFETY_LIMITS_EXCEEDED` banner appears, proceed with the deactivation steps below.
    - `[ ]` **Test for Threading Behavior:** Confirm the Collapsed Reply Threads behavior is as expected (Default Off).
    - `[ ]` Perform thorough smoke tests.

#### 2.2. Deactivating Inactive Users (If Required)

**Note:** Perform this on the **test server first**. The same steps will be used for production.

1.  `[ ]` Load the environment variables into your shell: `export $(grep -v '^#' .env.test | xargs)`.
2.  `[ ]` Connect to the database: `docker compose -f docker-compose.harden.yml --env-file .env.test exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}`.
3.  `[ ]` **Inside `psql`:**
    -   **Count users to deactivate** (e.g., last login before Jan 1, 2023):
        ```sql
        SELECT count(*) FROM users WHERE deleteat = 0 AND lastlogin < 1672531200000;
        ```
    -   **If the count is correct, run the deactivation:**
        ```sql
        UPDATE users SET deleteat = extract(epoch from now()) * 1000 WHERE deleteat = 0 AND lastlogin < 1672531200000;
        ```
    -   **Verify the new active user count:** `SELECT count(*) FROM users WHERE deleteat = 0;`
    -   Exit `psql`: `\q`.
4.  `[ ]` **Restart Mattermost** to apply the change: `docker compose -f ... --env-file .env.test restart mattermost`.
5.  `[ ]` Confirm the warning banner is gone on the test site.

#### 2.3. Phase 2: Production Upgrade

Once the test upgrade is successful and verified, proceed with the production upgrade during a scheduled maintenance window. The steps are identical to the test upgrade, but using the production `.env` file and **without** the `--env-file` flag.

---

### 3. Secrets Management with `agebox`

- **Key Storage:**
    - Your personal private key(s) should be managed in `~/.config/sops/age/keys.txt` to maintain compatibility with other `sops` projects.
    - Each server (production, test) should have only its own unique `age` private key in `/root/.config/age/keys.txt` or a similar standard location.
- **Recipient Management:**
    - Recipient **public keys** (`age1...`) are stored in files within the `./keys` directory of this repository. `agebox` uses all keys in this directory during encryption.
- **Workflow:**
    - **Encrypt:** `agebox encrypt <file>` (uses recipients from `./keys`).
    - **Decrypt for Deployment:** `agebox cat <file.agebox> > <file>` (non-destructive).
    - **Decrypt Locally:** Since your keys are in a non-default path for `agebox`, you must use the `-i` flag:
        ```bash
        agebox cat -i ~/.config/sops/age/keys.txt <file.agebox>
        ```

---

## FAQ & Gotchas

- **Why `iptables` instead of `ufw`?**
    - `ufw` often conflicts with Docker's dynamic networking rules. Managing rules directly with `iptables` and the `DOCKER-USER` chain is more robust.
- **Why is Nginx failing to start with a certificate error?**
    - **1. File doesn't exist:** Run Certbot first. **2. Wrong Path:** Your `.env` `CERT_PATH`/`KEY_PATH` doesn't match where Certbot saved the files (check for `-0001` directories). **3. Directory, not File:** Docker created a directory because the source file didn't exist during a previous `up` command. Delete the incorrect directory (`sudo rm -rf ...`) and re-generate the cert.
- **Why did `certbot` fail with `NXDOMAIN` or `Timeout/404`?**
    - **NXDOMAIN:** Your DNS record was incorrect or hadn't propagated globally. Use `dnschecker.org` to verify.
    - **Timeout/404:** A firewall was blocking port 80, OR a redirect rule at your DNS provider was forcing HTTP to HTTPS. Disable DNS-level forwarding.
- **Why are my `.env` variables not showing up in the container?**
    - For this Compose setup, we found that runtime `MM_...` variables must be explicitly listed in the `environment:` section of the `mattermost` service in `docker-compose.harden.yml` to be passed through reliably.
