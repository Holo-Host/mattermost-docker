#!/bin/bash

# --- Wrapper Script for Nightly Mattermost Backup ---

# Define the log file path with a timestamp
LOG_DIR="/home/shoot/mattermost_backups/logs"
LOG_FILE="${LOG_DIR}/backup-$(date "+%Y-%m-%d-%H%M").log"

# Define the path to the main backup script
# Use an absolute path to avoid any ambiguity when cron runs it
BACKUP_SCRIPT_PATH="/home/shoot/mattermost-docker/holo/backup_prod_db.sh"

echo "--- Starting Nightly Backup: $(date) ---" > "${LOG_FILE}"
echo "" >> "${LOG_FILE}"

# Execute the main backup script, redirecting all output (stdout and stderr)
# to the log file. The '2>&1' part redirects stderr to the same place as stdout.
bash "${BACKUP_SCRIPT_PATH}" >> "${LOG_FILE}" 2>&1

# Check the exit code of the backup script
if [ $? -eq 0 ]; then
    echo "" >> "${LOG_FILE}"
    echo "--- Backup Script Completed Successfully: $(date) ---" >> "${LOG_FILE}"
else
    echo "" >> "${LOG_FILE}"
    echo "--- !!! BACKUP SCRIPT FAILED: $(date) !!! ---" >> "${LOG_FILE}"
    # Optional: Add a notification here (e.g., send an email or a webhook)
fi
