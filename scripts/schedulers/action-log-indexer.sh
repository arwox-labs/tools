#!/bin/bash
# Action Log Indexer - PM2 Scheduler
# Runs action-log-index.py every 10 minutes to keep semantic search current

set +e
set -o pipefail

# Configuration
INTERVAL=600  # 10 minutes (was 300)
VENV_PYTHON="/root/workspaces/tools/acc1-scripts/mcp-servers/code-search/venv/bin/python"
SCRIPT="/root/workspaces/system/tools/scripts/lib/action-log-index.py"
LOG="/root/workspaces/system/tools/scripts/logs/action-log-indexer.log"
LOCK_FILE="/tmp/action-log-indexer.lock"
MAX_LOG_SIZE=5242880  # 5MB in bytes

# Load API keys from bashrc
source ~/.bashrc

# Continuous indexing loop
while true; do
    # Log rotation: if log > 5MB, truncate to last 1000 lines
    if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
        TMPLOG=$(mktemp)
        tail -n 1000 "$LOG" > "$TMPLOG"
        mv "$TMPLOG" "$LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log rotated (exceeded 5MB)" >> "$LOG"
    fi

    # Load guard: skip cycle if system is under heavy load
    LOAD_NOW=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    LOAD_INT=$(echo "$LOAD_NOW" | awk '{printf "%d", $1 * 10}')
    if [ "${LOAD_INT:-0}" -gt 60 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOAD GUARD: load=${LOAD_NOW} > 6.0 — skipping cycle" >> "$LOG"
        sleep "$INTERVAL"
        continue
    fi

    # flock: if another instance is running, skip this cycle silently
    if ! flock -n "$LOCK_FILE" true 2>/dev/null; then
        sleep "$INTERVAL"
        continue
    fi

    # Acquire lock and run indexer (released automatically when subshell exits)
    (
        flock -n 9 || exit 0
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting index cycle" >> "$LOG"
        timeout 240 nice -n 19 ionice -c 3 "$VENV_PYTHON" "$SCRIPT" >> "$LOG" 2>&1
        EXITCODE=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cycle complete (exit: $EXITCODE)" >> "$LOG"

        # DB maintenance with size check (every 6h)
        MAINT_LAST="/root/workspaces/system/tools/scripts/data/db-maintenance-last.txt"
        MAINT_INTERVAL=21600  # 6 hours
        NOW_EPOCH=$(date +%s)
        LAST_MAINT=$(cat "$MAINT_LAST" 2>/dev/null || echo "0")
        if [ $((NOW_EPOCH - LAST_MAINT)) -ge $MAINT_INTERVAL ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running DB maintenance" >> "$LOG"
            timeout 120 "$VENV_PYTHON" /root/workspaces/system/tools/scripts/lib/db-maintenance.py >> "$LOG" 2>&1
            echo "$NOW_EPOCH" > "$MAINT_LAST"
        fi

        # On non-zero exit code, add extra backoff sleep
        if [ "$EXITCODE" -ne 0 ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Non-zero exit ($EXITCODE), sleeping extra 300s (backoff)" >> "$LOG"
            sleep 300
        fi
    ) 9>"$LOCK_FILE"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sleeping ${INTERVAL}s" >> "$LOG"
    sleep "$INTERVAL"
done
