#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Ensure pipeline failures are reported
set -o pipefail

# --- Configuration ---
# Path to the production .env file (assumed to be in ../ relative to a scripts/ dir)
# Adjust if your script is in a different location.
ENV_FILE="../.env"

# S3 bucket for storing the backup
S3_BUCKET="db.dr1.chat.holo.host" # Or use a variable from .env if you prefer

# --- Load Environment Variables ---
if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: Production environment file '${ENV_FILE}' not found."
  exit 1
fi

echo "Loading production database configuration from ${ENV_FILE}..."
# Source the .env file - Use 'set -a' to export all sourced variables temporarily
set -a
source "${ENV_FILE}"
set +a

# --- Validate Required Variables ---
: "${POSTGRES_USER?Error: POSTGRES_USER not set in ${ENV_FILE}}"
: "${POSTGRES_DB?Error: POSTGRES_DB not set in ${ENV_FILE}}"
# PGPASSWORD is handled by docker compose exec's environment

# --- Check Prerequisites ---
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI ('aws') could not be found. Please install and configure it."
    exit 1
fi
if ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose V2 ('docker compose') could not be found."
    exit 1
fi

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
# We use 'docker compose exec' to run pg_dump *inside* the postgres container.
# The output is piped from the container's stdout to the host's stdout,
# then piped to 'aws s3 cp' to stream it directly to S3.
#
# -T flag for 'exec' is crucial to disable pseudo-tty and allow clean piping.
# PGPASSWORD is passed into the exec environment directly.

time docker compose exec -T \
    -e PGPASSWORD="${POSTGRES_PASSWORD}" \
    postgres \
    pg_dump --clean -Z 9 -v -h localhost -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    | aws s3 cp --storage-class STANDARD_IA --sse aws:kms - "${S3_TARGET}"

# Capture the exit status of the pipeline
BACKUP_STATUS=$?

# --- Report Result ---
if [ $BACKUP_STATUS -eq 0 ]; then
  echo "------------------------------------------------------------"
  echo "Backup completed successfully and uploaded to:"
  echo "${S3_TARGET}"
  echo "------------------------------------------------------------"
else
  echo "------------------------------------------------------------"
  echo "Error: Backup process failed with status ${BACKUP_STATUS}."
  echo "Check the output above for error messages from 'pg_dump' or 'aws'."
  echo "------------------------------------------------------------"
  exit $BACKUP_STATUS
fi

exit 0