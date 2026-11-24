#!/bin/bash
# plan-lifecycle-manager.sh — PM2 cron job for plan lifecycle management
# Runs every 15 minutes via PM2
# Responsibilities:
#   - ABANDONED detection: session gone + file not modified 30+ min + status active
#   - STALE detection: CREATED_AT > TTL_HOURS + not completed
#   - AUTO-ARCHIVE: stale/abandoned plans not updated in 12+ hours
# Exit: always 0 (PM2 cron job)
set +e

PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"
ARCHIVE_DIR="$PLANS_DIR/archive"
STATUS_UPDATER="/root/workspaces/system/tools/scripts/lib/plan-status-update.sh"
NOW=$(date +%s)

mkdir -p "$ARCHIVE_DIR" 2>/dev/null

log() {
    echo "[plan-lifecycle] $(date '+%Y-%m-%dT%H:%M:%S') $*" >&2
}

# Parse ISO 8601 datetime to epoch seconds
parse_iso_epoch() {
    local dt="$1"
    [[ -z "$dt" ]] && echo 0 && return
    date -d "$dt" +%s 2>/dev/null || echo 0
}

# Process each plan file in plans/ (not archive/)
find "$PLANS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r plan_file; do
    PLAN_CONTENT=$(cat "$plan_file" 2>/dev/null)
    PLAN_BASENAME=$(basename "$plan_file")

    # Skip files without PLAN_META
    echo "$PLAN_CONTENT" | grep -q '<!--PLAN_META' 2>/dev/null || continue

    # Extract PLAN_META fields
    STATUS=$(echo "$PLAN_CONTENT" | grep -oP 'STATUS:\s*\K\w+' 2>/dev/null | head -1)
    SESSION_ID=$(echo "$PLAN_CONTENT" | grep -oP 'SESSION_ID:\s*\K\S+' 2>/dev/null | head -1)
    UPDATED_AT=$(echo "$PLAN_CONTENT" | grep -oP 'UPDATED_AT:\s*\K[^\s]+' 2>/dev/null | head -1)
    CREATED_AT=$(echo "$PLAN_CONTENT" | grep -oP 'CREATED_AT:\s*\K[^\s]+' 2>/dev/null | head -1)
    TTL_HOURS=$(echo "$PLAN_CONTENT" | grep -oP 'TTL_HOURS:\s*\K[0-9]+' 2>/dev/null | head -1)
    PROJECT=$(echo "$PLAN_CONTENT" | grep -oP 'PROJECT:\s*\K\S+' 2>/dev/null | head -1)

    # Defaults
    STATUS="${STATUS:-unknown}"
    TTL_HOURS="${TTL_HOURS:-24}"

    # Skip already terminal statuses
    case "$STATUS" in
        completed) continue ;;
    esac

    FILE_MTIME=$(stat -c %Y "$plan_file" 2>/dev/null || echo 0)
    FILE_AGE_MIN=$(( (NOW - FILE_MTIME) / 60 ))

    CREATED_EPOCH=$(parse_iso_epoch "$CREATED_AT")
    CREATED_AGE_HOURS=$(( (NOW - CREATED_EPOCH) / 3600 ))

    UPDATED_EPOCH=$(parse_iso_epoch "$UPDATED_AT")
    UPDATED_AGE_HOURS=$(( (NOW - UPDATED_EPOCH) / 3600 ))

    # ── ABANDONED detection ──
    # Conditions: (created or in_progress) + session gone + file not modified 30+ min
    if [[ "$STATUS" = "created" || "$STATUS" = "in_progress" ]]; then
        SESSION_GONE=0
        if [ -n "$SESSION_ID" ]; then
            SESSION_EXISTS=$(redis-cli EXISTS "session:active:${SESSION_ID}" 2>/dev/null)
            if [ "${SESSION_EXISTS:-0}" = "0" ]; then
                SESSION_GONE=1
            fi
        else
            # No session ID — treat session as gone
            SESSION_GONE=1
        fi

        if [ "$SESSION_GONE" = "1" ] && [ "$FILE_AGE_MIN" -gt 30 ]; then
            log "ABANDONED: ${PLAN_BASENAME} (session=${SESSION_ID:-none} gone, file age=${FILE_AGE_MIN}min)"
            bash "$STATUS_UPDATER" "$plan_file" "abandoned"
            STATUS="abandoned"
        fi
    fi

    # ── STALE detection ──
    # Conditions: CREATED_AT > TTL_HOURS + status not completed
    if [[ "$STATUS" != "completed" && "$STATUS" != "abandoned" ]]; then
        if [ "$CREATED_EPOCH" -gt 0 ] && [ "$CREATED_AGE_HOURS" -gt "$TTL_HOURS" ]; then
            log "STALE: ${PLAN_BASENAME} (created ${CREATED_AGE_HOURS}h ago, TTL=${TTL_HOURS}h)"
            bash "$STATUS_UPDATER" "$plan_file" "stale"
            STATUS="stale"
        fi
    fi

    # ── Set Redis stale-block marker for stale plans ──
    if [ "$STATUS" = "stale" ] && [ -n "$PROJECT" ]; then
        redis-cli SETEX "plan:stale-block:${PROJECT}" 7200 "$plan_file" >/dev/null 2>&1
        log "Redis stale-block set for project=${PROJECT}"
    fi

    # ── AUTO-ARCHIVE: stale or abandoned, not updated in 12+ hours ──
    if [[ "$STATUS" = "stale" || "$STATUS" = "abandoned" ]]; then
        if [ "$UPDATED_AGE_HOURS" -gt 12 ]; then
            ARCHIVE_DEST="$ARCHIVE_DIR/$PLAN_BASENAME"
            # Avoid overwrite — append timestamp if already exists
            if [ -f "$ARCHIVE_DEST" ]; then
                ARCHIVE_DEST="$ARCHIVE_DIR/$(date +%Y%m%d_%H%M%S)_${PLAN_BASENAME}"
            fi
            mv "$plan_file" "$ARCHIVE_DEST" 2>/dev/null
            if [ $? -eq 0 ]; then
                log "ARCHIVED: ${PLAN_BASENAME} → archive/ (status=${STATUS}, updated ${UPDATED_AGE_HOURS}h ago)"
                redis-cli LPUSH "plan:archived" "$(date -u '+%Y-%m-%dT%H:%M:%S')|${STATUS}|${PLAN_BASENAME}" >/dev/null 2>&1
                redis-cli LTRIM "plan:archived" 0 199 >/dev/null 2>&1
                # Remove stale-block marker since plan is now archived
                if [ -n "$PROJECT" ]; then
                    redis-cli DEL "plan:stale-block:${PROJECT}" >/dev/null 2>&1
                fi
            else
                log "ERROR: Failed to archive ${PLAN_BASENAME}"
            fi
        fi
    fi

done

log "Lifecycle scan complete."
exit 0
