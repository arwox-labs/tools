#!/bin/bash
# Auto-commit daemon for pm2
# Runs auto-commit.sh every 3 minutes

INTERVAL=600  # 10 minutes (was 180s — caused CPU spikes)
SCRIPT="/root/workspaces/system/tools/scripts/pm2/auto-commit.sh"

echo "[$(date)] Auto-commit daemon started (interval: ${INTERVAL}s)"

while true; do
    "$SCRIPT" 2>&1 || true
    sleep $INTERVAL
done
