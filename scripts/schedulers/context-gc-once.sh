#!/bin/bash
# ============================================================================
# Scheduler: context-gc-once.sh
# Purpose: One-shot context GC run (extracted from context-gc-daemon.sh)
# Trigger: PM2 cron_restart every 30 min
# ADR-001: Converted from daemon to scheduled execution
# ============================================================================
set +e

LOGFILE="/root/workspaces/system/tools/scripts/logs/context-gc.log"
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"

mkdir -p "$(dirname "$LOGFILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

log "=== Starting garbage collection cycle ==="

total_deleted=0

# 1. Delete context:* keys with TTL -1, except whitelisted patterns
log "Scanning context:* keys..."
context_deleted=0

while read -r key; do
    [ -z "$key" ] && continue
    case "$key" in
        context:latest|context:checkpoint|context:heartbeat|context:history)
            continue ;;
        context:daily:*)
            continue ;;
        context:archive:*)
            continue ;;
    esac

    ttl=$(rcli TTL "$key")
    if [ "$ttl" = "-1" ]; then
        rcli DEL "$key" >/dev/null
        context_deleted=$((context_deleted + 1))
    fi
done < <(rcli --scan --pattern "context:*")

total_deleted=$((total_deleted + context_deleted))
log "Deleted $context_deleted context:* keys with no expiration"

# 2. Delete session:2026-* timestamp spam (NOT session:registry:* or session:indexed)
log "Scanning session:2026-* keys..."
session_deleted=0
while read -r key; do
    [ -z "$key" ] && continue
    case "$key" in
        session:registry:*|session:indexed)
            continue ;;
    esac
    rcli DEL "$key" >/dev/null
    session_deleted=$((session_deleted + 1))
done < <(rcli --scan --pattern "session:2026-*")

total_deleted=$((total_deleted + session_deleted))
log "Deleted $session_deleted session:2026-* spam keys"

# 3. Delete file:* keys with TTL -1
log "Scanning file:* keys..."
file_deleted=0

for pattern in "file:edit:*" "file:hash:*" "file:lock:*" "file:editing:*"; do
    while read -r key; do
        [ -z "$key" ] && continue
        ttl=$(rcli TTL "$key")
        if [ "$ttl" = "-1" ]; then
            rcli DEL "$key" >/dev/null
            file_deleted=$((file_deleted + 1))
        fi
    done < <(rcli --scan --pattern "$pattern")
done

total_deleted=$((total_deleted + file_deleted))
log "Deleted $file_deleted file:* keys with no expiration"

# 4. Trim context:history to max 20 entries
log "Trimming context:history..."
rcli LTRIM context:history 0 19 >/dev/null
history_count=$(rcli LLEN context:history)
log "context:history trimmed to $history_count entries"

# 5. Cleanup stale task:current
log "Checking task:current..."
task_ttl=$(rcli TTL task:current)
if [ "$task_ttl" = "-1" ]; then
    task_data=$(rcli GET task:current)
    task_status=$(echo "$task_data" | jq -r '.status // empty' 2>/dev/null)
    if [ "$task_status" = "completed" ] || [ "$task_status" = "deleted" ]; then
        rcli DEL task:current >/dev/null
        log "Deleted stale task:current (status=$task_status)"
    else
        rcli EXPIRE task:current 86400 >/dev/null
        log "Set TTL 86400 on task:current (was -1)"
    fi
elif [ "$task_ttl" != "-2" ]; then
    log "task:current OK (TTL=${task_ttl}s)"
fi

# 6. V2: Ensure TTL on new key types (set 3d if TTL -1)
log "Checking v2 key TTLs..."
ttl_fixed=0

for pattern in "session:registry:*" "topic:index:*" "context:archive:*"; do
    while read -r key; do
        [ -z "$key" ] && continue
        ttl=$(rcli TTL "$key")
        if [ "$ttl" = "-1" ]; then
            rcli EXPIRE "$key" 259200 >/dev/null
            ttl_fixed=$((ttl_fixed + 1))
        fi
    done < <(rcli --scan --pattern "$pattern")
done

# session:indexed SET should also have TTL
si_ttl=$(rcli TTL "session:indexed")
if [ "$si_ttl" = "-1" ]; then
    rcli EXPIRE "session:indexed" 259200 >/dev/null
    ttl_fixed=$((ttl_fixed + 1))
fi

log "Fixed TTL on $ttl_fixed v2 keys"

# Count remaining keys
total_keys=$(rcli DBSIZE | grep -oP '\d+')

log "=== GC cycle complete: deleted $total_deleted keys, fixed $ttl_fixed TTLs, $total_keys keys remaining ==="

exit 0
