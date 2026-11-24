#!/bin/bash
#
# PM2 Extended Metrics Generator for Prometheus
# Generates pm2_status_info, pm2_health_score, pm2_is_scheduled, pm2_cron_schedule
# Runs in a loop with 15s sleep
#

set +e

OUTPUT_FILE="/var/lib/node_exporter/textfile/pm2_extended.prom"
TEMP_FILE="${OUTPUT_FILE}.tmp"
PARSER="/root/workspaces/system/tools/scripts/lib/pm2-metrics-parser.py"

while true; do
    # Load guard: skip if system is under heavy load
    LOAD_NOW=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    LOAD_INT=$(echo "$LOAD_NOW" | awk '{printf "%d", $1 * 10}')
    if [ "${LOAD_INT:-0}" -gt 60 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOAD GUARD: load=${LOAD_NOW} > 6.0 — skipping metrics"
        sleep 15
        continue
    fi

    pm2 jlist 2>/dev/null | timeout 30 python3 "$PARSER" /dev/stdin > "$TEMP_FILE" 2>&1
    if [ $? -eq 0 ] && [ -s "$TEMP_FILE" ]; then
        mv -f "$TEMP_FILE" "$OUTPUT_FILE"
    else
        echo "$(date): metrics generation failed" >&2
        rm -f "$TEMP_FILE"
    fi
    sleep 15
done
