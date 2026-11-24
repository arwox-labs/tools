#!/bin/bash
# Setup cron job for docker-clean-rotation on remote server
# This script runs ON THE REMOTE SERVER

SCRIPT_PATH="/root/scripts/docker-clean-rotation.sh"
CRON_ENTRY="0 4 * * * $SCRIPT_PATH"

# Check if already exists
if crontab -l 2>/dev/null | grep -q "docker-clean-rotation"; then
    echo "CRON_ALREADY_EXISTS"
    crontab -l | grep "docker-clean-rotation"
else
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "CRON_ADDED: $CRON_ENTRY"
fi

echo "--- Current crontab ---"
crontab -l
