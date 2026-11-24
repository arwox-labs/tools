#!/bin/bash
# Docker container log rotation via PM2
# Checks every 30 minutes, truncates logs if >50MB
# NO CRON — PM2 only (user rule V101)
# Targets: stroy-php container Apache logs

set -uo pipefail

CONTAINER="stroy-php"
LOG_DIR="/var/log/apache2"
MAX_SIZE_BYTES=$((50 * 1048576))  # 50 MB

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [docker-log-rotation] $1"
}

rotate_log() {
    local logfile="$1"
    local size="$2"
    local size_mb=$((size / 1048576))

    log "INFO ${CONTAINER}:${logfile} = ${size_mb}MB — exceeds limit, rotating..."

    # Try logrotate first
    docker exec "$CONTAINER" logrotate -f /etc/logrotate.d/apache2 2>/dev/null || true
    sleep 2

    # Check if still too big — truncate as fallback
    local new_size
    new_size=$(docker exec "$CONTAINER" stat -c%s "${LOG_DIR}/${logfile}" 2>/dev/null || echo "0")
    local new_size_mb=$((new_size / 1048576))

    if [ "$new_size" -gt "$MAX_SIZE_BYTES" ]; then
        docker exec "$CONTAINER" bash -c "cp -a '${LOG_DIR}/${logfile}' '${LOG_DIR}/${logfile}.1' && truncate -s 0 '${LOG_DIR}/${logfile}'" || true
        log "TRUNCATED ${CONTAINER}:${LOG_DIR}/${logfile} (was ${size_mb}MB, logrotate failed, kept .1 copy)"
    else
        log "ROTATED ${CONTAINER}:${LOG_DIR}/${logfile} (was ${size_mb}MB → ${new_size_mb}MB)"
    fi
}

check_logs() {
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
        log "SKIP ${CONTAINER} not running"
        return
    fi

    # Get all log files with their sizes
    local log_files
    log_files=$(docker exec "$CONTAINER" bash -c "find ${LOG_DIR} -maxdepth 1 -name '*.log' -type f 2>/dev/null" 2>/dev/null || echo "")

    if [ -z "$log_files" ]; then
        log "WARN no log files found in ${CONTAINER}:${LOG_DIR}"
        return
    fi

    local any_oversized=0
    while IFS= read -r logpath; do
        local filename
        filename=$(basename "$logpath")
        local size
        size=$(docker exec "$CONTAINER" stat -c%s "$logpath" 2>/dev/null || echo "0")
        local size_mb=$((size / 1048576))

        if [ "$size" -gt "$MAX_SIZE_BYTES" ]; then
            rotate_log "$filename" "$size"
            any_oversized=1
        else
            log "OK ${CONTAINER}:${logpath} = ${size_mb}MB"
        fi
    done <<< "$log_files"

    if [ "$any_oversized" -eq 0 ]; then
        log "ALL_OK all logs within limit in ${CONTAINER}"
    fi
}

check_docker_json_logs() {
    local docker_containers_dir="/var/lib/docker/containers"

    if [ ! -d "$docker_containers_dir" ]; then
        log "SKIP docker containers dir not found: ${docker_containers_dir}"
        return
    fi

    local any_oversized=0
    while IFS= read -r logfile; do
        local size
        size=$(stat -c%s "$logfile" 2>/dev/null || echo "0")
        local size_mb=$((size / 1048576))

        if [ "$size" -gt "$MAX_SIZE_BYTES" ]; then
            cp -a "$logfile" "$logfile.1" 2>/dev/null && truncate -s 0 "$logfile" 2>/dev/null || true
            log "TRUNCATED docker-json-log ${logfile} (was ${size_mb}MB, kept .1 copy)"
            any_oversized=1
        else
            log "OK docker-json-log ${logfile} = ${size_mb}MB"
        fi
    done < <(find "$docker_containers_dir" -maxdepth 2 -name '*-json.log' -type f 2>/dev/null)

    if [ "$any_oversized" -eq 0 ]; then
        log "ALL_OK all docker json-logs within limit"
    fi
}

log "START docker-log-rotation scheduler (interval=30m, max=${MAX_SIZE_BYTES} bytes)"

while true; do
    check_logs
    check_docker_json_logs
    sleep 1800  # 30 minutes
done
