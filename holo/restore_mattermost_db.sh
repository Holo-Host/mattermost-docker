#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Ensure pipeline failures are reported
set -o pipefail

# --- Configuration ---
# Define the default Compose file name
COMPOSE_FILE="docker-compose.harden.yml"
# Define the S3 bucket (consider making this an argument or env var if it changes often)
S3_BUCKET="db.dr1.chat.holo.host"
# Path to the .env file (assumed to be in the same directory as the script)
ENV_FILE=".env"

# --- Helper Functions ---
usage() {
  echo "Usage: $0 <backup_filename.sql.gz>"
  echo "  Restores a PostgreSQL backup from an S3 bucket to the Docker Compose postgres service."
  echo "  Reads database credentials (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB)"
  echo "  from the ${ENV_FILE} file in the current directory."
  exit 1
}

# Function to format duration in seconds to minutes and seconds
format_duration() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  if (( minutes > 0 )); then
    echo "${minutes} minute(s) and ${remaining_seconds} second(s)"
  else
    echo "${remaining_seconds} second(s)"
  fi
}


# --- Argument Parsing ---
if [ "$#" -ne 1 ]; then
  echo "Error: Incorrect number of arguments."
  usage
fi
BACKUP_FILENAME="$1"

# Validate filename format (basic check)
if [[ ! "$BACKUP_FILENAME" =~ \.sql\.gz$ ]]; then
  echo "Error: Backup filename must end with .sql.gz"
  usage
fi

# --- Load Environment Variables ---
if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: Environment file '${ENV_FILE}' not found in the current directory."
  exit 1
fi

echo "Loading database configuration from ${ENV_FILE}..."
# Source the .env file - Use 'set -a' to export all sourced variables temporarily
set -a
source "${ENV_FILE}"
set +a

# --- Validate Required Variables ---
: "${POSTGRES_USER?Error: POSTGRES_USER not set in ${ENV_FILE}}"
: "${POSTGRES_PASSWORD?Error: POSTGRES_PASSWORD not set in ${ENV_FILE}}"
: "${POSTGRES_DB?Error: POSTGRES_DB not set in ${ENV_FILE}}"

# --- Check Prerequisites ---
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI ('aws') could not be found. Please install and configure it."
    exit 1
fi
if ! command -v docker &> /dev/null; then
    echo "Error: Docker ('docker') could not be found."
    exit 1
fi
# Check if docker compose is v2 syntax
if ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose V2 syntax ('docker compose') could not be found."
    exit 1
fi

# --- Check S3 Backup File Existence ---
S3_PATH="s3://${S3_BUCKET}/${BACKUP_FILENAME}"
echo "Checking if backup file '${S3_PATH}' exists in S3..."
if ! aws s3api head-object --bucket "${S3_BUCKET}" --key "${BACKUP_FILENAME}" >/dev/null 2>&1; then
  echo "Error: Backup file '${S3_PATH}' not found or not accessible."
  echo "Please check the filename and your AWS credentials/permissions."
  exit 1
fi
echo "Backup file found."

# --- Check Docker Compose Service Status ---
echo "Checking status of postgres service in ${COMPOSE_FILE}..."
# Use --format to get the raw state. Redirect stderr to /dev/null and use || to handle cases where the service isn't found at all.
POSTGRES_STATE=$(docker compose -f "${COMPOSE_FILE}" ps --status=running --format '{{.State}}' postgres 2>/dev/null || echo "not found")

# Check if the state *starts with* 'running' to correctly handle 'running' or 'running (healthy)'
if [[ "$POSTGRES_STATE" != running* ]]; then
    echo "Error: The 'postgres' service defined in '${COMPOSE_FILE}' is not running or could not be found by Docker Compose."
    # Provide more context if a state was found but wasn't 'running'
    if [[ "$POSTGRES_STATE" != "not found" ]]; then
      echo "Detected state: '${POSTGRES_STATE}'"
    fi
    echo "Please ensure the service is running and associated with the project (check 'docker ps' and 'docker compose -f ${COMPOSE_FILE} ps')."
    echo "You might need to run: 'docker compose -f ${COMPOSE_FILE} up -d postgres'"
    exit 1
fi
echo "'postgres' service is running (State: ${POSTGRES_STATE})."

# --- Execute Restore ---
echo "------------------------------------------------------------"
echo "WARNING: This script will restore the database '${POSTGRES_DB}'"
echo "         in the 'postgres' container using backup:"
echo "         ${S3_PATH}"
echo "         Existing data in tables targeted by the backup's"
echo "         'DROP' statements (due to --clean) WILL BE DELETED."
echo "------------------------------------------------------------"
read -p "Proceed with restore? (y/N): " -n 1 -r
echo # Move to a new line

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled by user."
    exit 0
fi

echo "Starting restore process..."

# Record start time
start_time=$(date +%s)

# Export password for psql within the exec command's environment
export PGPASSWORD="${POSTGRES_PASSWORD}"

# Perform the streaming restore
# We need to handle the pipeline exit status carefully
set +e # Temporarily disable exit on error to capture the pipeline status
aws s3 cp "${S3_PATH}" - | gunzip -c | docker compose -f "${COMPOSE_FILE}" exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
RESTORE_STATUS=$? # Capture the exit status of the *last* command in the pipeline (psql)
set -e # Re-enable exit on error

# Record end time
end_time=$(date +%s)

# Calculate duration
duration=$((end_time - start_time))
formatted_duration=$(format_duration $duration)

# Unset the password from the environment
unset PGPASSWORD

# --- Report Result ---
if [ $RESTORE_STATUS -eq 0 ]; then
  echo "------------------------------------------------------------"
  echo "Restore process completed successfully."
  echo "Duration: ${formatted_duration}."
  echo "------------------------------------------------------------"
else
  echo "------------------------------------------------------------"
  echo "Error: Restore process failed with status ${RESTORE_STATUS}."
  echo "Duration: ${formatted_duration}."
  echo "Check the output above for error messages from 'aws', 'gunzip', or 'psql'."
  echo "------------------------------------------------------------"
  exit $RESTORE_STATUS
fi

exit 0
