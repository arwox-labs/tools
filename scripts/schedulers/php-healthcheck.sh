#!/bin/bash

###############################################################################
# IMPROVED SERVER HEALTHCHECK WITH RESOURCE MONITORING
# Features:
#   - Timeout detection (>10s = blocked)
#   - Memory check (restart if >500MB)
#   - CPU check (restart if >90% for >30s)
#   - Timestamps in logging
#   - Lock file to prevent simultaneous restarts
###############################################################################

set -e

PORT=${1:-20080}
LOG_FILE="/tmp/php-server-healthcheck.log"
LOCK_FILE="/tmp/php-healthcheck-${PORT}.lock"
TIMEOUT=10
MEM_THRESHOLD=500  # MB
CPU_THRESHOLD=90   # %
CPU_DURATION=30    # seconds

# Initialize log file
touch "$LOG_FILE"

log_message() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${msg}" >> "$LOG_FILE"
    echo "[${timestamp}] [${level}] ${msg}"
}

# Clean up lock file on exit
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Check if another restart is already in progress
if [ -f "$LOCK_FILE" ]; then
    log_message "WARN" "Restart already in progress (lock: $LOCK_FILE), skipping..."
    exit 0
fi

log_message "INFO" "Starting healthcheck for port ${PORT}"

# === 1. HTTP Connectivity Check ===
if ! timeout $TIMEOUT curl -s --max-time $TIMEOUT http://localhost:${PORT}/ > /dev/null 2>&1; then
    log_message "ERROR" "HTTP check failed (timeout > ${TIMEOUT}s or no response)"
    echo 1 > "$LOCK_FILE"
    pm2 restart bitrix-sdk-php-server
    cleanup
    exit 0
fi

# === 2. Memory Check ===
php_mem=$(ps aux | grep "php.*${PORT}" | grep -v grep | awk '{print $6}' | head -1)

if [ -n "$php_mem" ] && [ "$php_mem" -gt $((MEM_THRESHOLD * 1024)) ]; then
    log_message "ERROR" "Memory usage critical: ${php_mem}KB (threshold: ${MEM_THRESHOLD}MB)"
    echo 1 > "$LOCK_FILE"
    pm2 restart bitrix-sdk-php-server
    cleanup
    exit 0
fi

# === 3. CPU Check (if process using >90% for >30 seconds) ===
php_pid=$(pgrep -f "php.*${PORT}" | head -1)

if [ -n "$php_pid" ]; then
    top_output=$(timeout 3 top -b -p $php_pid -n 1 2>/dev/null | tail -1)
    if [ -n "$top_output" ]; then
        cpu_usage=$(echo "$top_output" | awk '{print $9}' | cut -d'.' -f1)

        if [ -n "$cpu_usage" ] && [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
            log_message "WARN" "High CPU detected: ${cpu_usage}% (monitoring for ${CPU_DURATION}s)"

            # Monitor CPU for 30 seconds
            high_cpu_count=0
            for i in $(seq 1 6); do
                sleep 5
                top_check=$(timeout 3 top -b -p $php_pid -n 1 2>/dev/null | tail -1)
                cpu_check=$(echo "$top_check" | awk '{print $9}' | cut -d'.' -f1)

                if [ -n "$cpu_check" ] && [ "$cpu_check" -gt "$CPU_THRESHOLD" ]; then
                    ((high_cpu_count++))
                fi
            done

            if [ $high_cpu_count -ge 4 ]; then
                log_message "ERROR" "CPU remained >90% for >30s (${high_cpu_count}/6 checks), restarting..."
                echo 1 > "$LOCK_FILE"
                pm2 restart bitrix-sdk-php-server
                cleanup
                exit 0
            fi
        fi
    fi
fi

log_message "INFO" "Healthcheck passed - server is healthy"
exit 0
