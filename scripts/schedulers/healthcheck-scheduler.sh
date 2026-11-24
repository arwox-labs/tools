#!/bin/bash
# PM2 Scheduler: PHP Healthcheck (every minute)
SCRIPT="/root/workspaces/tools/scripts/schedulers/php-healthcheck.sh"
PORT=20080
INTERVAL=60

while true; do
    if [ -f "$SCRIPT" ]; then
        echo "[$(date -Iseconds)] Running healthcheck"
        "$SCRIPT" $PORT 2>&1
    else
        echo "[$(date -Iseconds)] Script not found: $SCRIPT"
    fi
    sleep $INTERVAL
done
