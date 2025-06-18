#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Ensure pipeline failures are reported
set -o pipefail

# --- Configuration ---
# Get the directory where the script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Path to the .env file and Compose file, relative to the script's location
ENV_FILE="${SCRIPT_DIR}/../.env"
COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.harden.yml"

# S3 bucket for storing the backup
S3_BUCKET="db.dr1.chat.holo.host"

# --- Load Environment Variables ---
if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: Production environment file '${ENV_FILE}' not found."
  exit 1
fi
if [ ! -f "${COMPOSE_FILE}" ]; then
  echo "Error: Compose file '${COMPOSE_FILE}' not found."
  exit 1
fi

echo "Loading production database configuration from ${ENV_FILE}..."
set -a
source "${ENV_FILE}"
set +a

# --- Validate Required Variables ---
: "${POSTGRES_USER?Error: POSTGRES_USER not set in ${ENV_FILE}}"
: "${POSTGRES_DB?Error: POSTGRES_DB not set in ${ENV_FILE}}"

# --- Check Prerequisites ---
# ... (aws, docker compose checks would go here) ...

# --- Verify Service is Running (ROBUST METHOD) ---
echo "Verifying 'postgres' service is running..."
# Use --format to get the raw state. Redirect stderr to /dev/null and use || to handle cases where the service isn't found at all.
POSTGRES_STATE=$(docker compose -f "${COMPOSE_FILE}" ps --format '{{.State}}' postgres 2>/dev/null || echo "not found")

# Check if the state *starts with* 'running' to correctly handle 'running' or 'running (healthy)'
if [[ "$POSTGRES_STATE" != running* ]]; then
    echo "Error: The 'postgres' service is not in a running state or could not be found by Docker Compose."
    if [[ "$POSTGRES_STATE" != "not found" ]]; then
      echo "Detected state: '${POSTGRES_STATE}'"
    fi
    echo "Please ensure the service is running and associated with the project (check 'docker ps' and 'docker compose -f ${COMPOSE_FILE} ps')."
    exit 1
fi
echo "'postgres' service is running (State: ${POSTGRES_STATE})."


# --- Define Backup Target ---
DATE=$(date "+%Y-%m-%d-%H%M")
BACKUP_FILENAME="${POSTGRES_DB}-prod-backup-${DATE}.sql.gz"
S3_TARGET="s3://${S3_BUCKET}/${BACKUP_FILENAME}"

echo ""
echo "Starting production Mattermost database backup..."
echo "  Database: ${POSTGRES_DB}"
echo "  User:     ${POSTGRES_USER}"
echo "  Target:   ${S3_TARGET}"
echo ""

# --- Execute Backup ---
time docker compose -f "${COMPOSE_FILE}" exec -T \
    -e PGPASSWORD="${POSTGRES_PASSWORD}" \
    postgres \
    pg_dump --clean -Z 9 -v -h localhost -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    | aws s3 cp --storage-class STANDARD_IA --sse aws:kms - "${S3_TARGET}"

# ... (Rest of script remains the same) ...