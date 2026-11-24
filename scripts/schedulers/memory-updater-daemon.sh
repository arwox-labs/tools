#!/bin/bash
# memory-updater-daemon.sh — PM2 daemon, every 5 minutes
# Updates MEMORY.md with recent sessions list from session:registry
# Issue: #230 (Context System v2)

set +e

INTERVAL=300  # 5 minutes
LOGFILE="/root/workspaces/system/tools/scripts/logs/memory-updater.log"
MEMORY_FILE="/root/.claude/projects/-root-workspaces-projects/memory/MEMORY.md"
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
LOCK_FILE="/tmp/.memory-updater.lock"
MAX_SESSIONS=15
MAX_MEMORY_LINES=200

mkdir -p "$(dirname "$LOGFILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

log "Memory updater daemon started (PID: $$, Interval: ${INTERVAL}s)"

while true; do
    # Lock check
    if [ -f "$LOCK_FILE" ]; then
        LOCK_AGE=$(( $(date +%s) - $(stat -c%Y "$LOCK_FILE" 2>/dev/null || echo "0") ))
        if [ "$LOCK_AGE" -lt 60 ]; then
            sleep "$INTERVAL"
            continue
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"

    # Redis check
    if ! rcli PING >/dev/null 2>&1; then
        log "Redis unavailable, skip cycle"
        rm -f "$LOCK_FILE"
        sleep "$INTERVAL"
        continue
    fi

    # MEMORY.md check
    if [ ! -f "$MEMORY_FILE" ]; then
        log "MEMORY.md not found, skip cycle"
        rm -f "$LOCK_FILE"
        sleep "$INTERVAL"
        continue
    fi

    log "=== Starting memory update cycle ==="

    # Collect sessions from registry
    SESSIONS_DATA=""
    SESSION_COUNT=0

    while IFS= read -r key; do
        [ -z "$key" ] && continue
        sid="${key#session:registry:}"
        ts=$(rcli HGET "$key" "timestamp")
        msgs=$(rcli HGET "$key" "message_count")
        topics=$(rcli HGET "$key" "topics")
        issue=$(rcli HGET "$key" "active_issue")
        role=$(rcli HGET "$key" "role")

        [ -z "$ts" ] && continue

        # Format: timestamp|short_id|msgs|topics|issue|role
        SESSIONS_DATA="${SESSIONS_DATA}${ts}|${sid:0:8}|${msgs}|${topics}|${issue}|${role}\n"
        SESSION_COUNT=$((SESSION_COUNT + 1))
    done < <(rcli --scan --pattern "session:registry:*")

    if [ "$SESSION_COUNT" -eq 0 ]; then
        log "No sessions in registry, skip update"
        rm -f "$LOCK_FILE"
        sleep "$INTERVAL"
        continue
    fi

    # Sort by timestamp (newest first), limit to MAX_SESSIONS
    SORTED_SESSIONS=$(echo -e "$SESSIONS_DATA" | sort -t'|' -k1 -r | head -"$MAX_SESSIONS")

    # Build AUTO-UPDATE section
    UPDATE_LINES=""
    while IFS='|' read -r ts sid msgs topics issue role; do
        [ -z "$ts" ] && continue
        ts_short="${ts%%T*} ${ts#*T}"
        ts_short="${ts_short:0:16}"
        LINE="- ${ts_short} - Session ${sid} (${msgs} msgs"
        [ -n "$topics" ] && LINE="${LINE}, topics: ${topics}"
        [ -n "$issue" ] && [ "$issue" != "none" ] && LINE="${LINE}, issue: #${issue}"
        [ -n "$role" ] && LINE="${LINE}, ${role}"
        LINE="${LINE})"
        UPDATE_LINES="${UPDATE_LINES}${LINE}\n"
    done <<< "$SORTED_SESSIONS"

    # DISABLED: Writing Recent Sessions to MEMORY.md is disabled to prevent bloat.
    # Sessions are still tracked in Redis (session:registry:*) and can be queried directly.
    # To re-enable, remove this comment block and restore the original code below.

    # Update timestamp in Redis (retained for health checks)
    rcli SET "memory:last_update" "$(date '+%Y-%m-%dT%H:%M:%S')" >/dev/null

    log "Memory update skipped (Recent Sessions write disabled). Sessions in registry: $SESSION_COUNT"

    rm -f "$LOCK_FILE"
    sleep "$INTERVAL"
done
