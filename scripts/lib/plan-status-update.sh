#!/bin/bash
# plan-status-update.sh — Atomic STATUS updater for PLAN_META blocks
# Usage: plan-status-update.sh <filepath> <new_status>
# Valid statuses: created, in_progress, completed, accepted, fix_needed, abandoned, stale
# Uses flock for race condition protection
# V255: Added accepted, fix_needed statuses with transition validation
set +e

FILEPATH="$1"
NEW_STATUS="$2"

# Validate arguments
[[ -z "$FILEPATH" || -z "$NEW_STATUS" ]] && exit 0
[[ ! -f "$FILEPATH" ]] && exit 0

# Validate status value
case "$NEW_STATUS" in
    created|in_progress|completed|accepted|fix_needed|abandoned|stale) ;;
    *) exit 0 ;;
esac

# Check if PLAN_META block exists in file
grep -q '<!--PLAN_META' "$FILEPATH" 2>/dev/null || exit 0

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%S')
BASENAME=$(basename "$FILEPATH")

# Perform atomic update using flock to prevent race conditions
(
    flock -x 200

    # Extract old status before update
    OLD_STATUS=$(grep -oE 'STATUS:\s*[a-z_]+' "$FILEPATH" | head -1 | sed 's/STATUS:\s*//')
    OLD_STATUS="${OLD_STATUS:-unknown}"

    # ── V255: State transition validation ──
    # Allow same-status updates (callers use this to refresh UPDATED_AT)
    # Block invalid transitions to protect plan lifecycle integrity
    TRANSITION_VALID=1
    if [[ "$OLD_STATUS" != "$NEW_STATUS" && "$OLD_STATUS" != "unknown" ]]; then
        case "${OLD_STATUS}→${NEW_STATUS}" in
            # Valid forward transitions
            created→in_progress)       ;;
            in_progress→completed)     ;;
            completed→accepted)        ;;
            completed→fix_needed)      ;;
            fix_needed→in_progress)    ;;
            created→abandoned)         ;;
            in_progress→abandoned)     ;;
            # Resume: abandoned/stale plans can be reopened
            abandoned→in_progress)     ;;
            stale→in_progress)         ;;
            # Any status can go stale
            *→stale)                   ;;
            # Same status (no-op transition) — always valid
            *)
                TRANSITION_VALID=0
                ;;
        esac
    fi

    if [[ "$TRANSITION_VALID" -eq 0 ]]; then
        echo "[plan-status-update] INVALID TRANSITION: ${OLD_STATUS} → ${NEW_STATUS} for ${BASENAME}" >&2
        exit 0
    fi

    # Update STATUS field inside PLAN_META block
    sed -i "s/^STATUS: .*/STATUS: ${NEW_STATUS}/" "$FILEPATH"

    # Update UPDATED_AT field inside PLAN_META block
    sed -i "s/^UPDATED_AT: .*/UPDATED_AT: ${TIMESTAMP}/" "$FILEPATH"

    # ── V255: Handle accepted transition ──
    # Set Redis key plan:accepted:{PROJECT} with plan path (TTL 7 days)
    if [[ "$NEW_STATUS" = "accepted" ]]; then
        PROJECT=$(grep -m1 '^PROJECT: ' "$FILEPATH" 2>/dev/null | sed 's/^PROJECT: //' | tr -d '[:space:]')
        [[ -z "$PROJECT" ]] && PROJECT="unknown"
        redis-cli SET "plan:accepted:${PROJECT}" "$FILEPATH" EX 604800 >/dev/null 2>&1
        echo "[plan-status-update] Plan ACCEPTED: ${BASENAME} (project=${PROJECT})" >&2
    fi

    # ── V255: Handle fix_needed transition ──
    # Keep the plan file, status updated above; log with extra marker
    if [[ "$NEW_STATUS" = "fix_needed" ]]; then
        PROJECT=$(grep -m1 '^PROJECT: ' "$FILEPATH" 2>/dev/null | sed 's/^PROJECT: //' | tr -d '[:space:]')
        [[ -z "$PROJECT" ]] && PROJECT="unknown"
        redis-cli SET "plan:fix-needed:${PROJECT}" "$FILEPATH" EX 86400 >/dev/null 2>&1
        echo "[plan-status-update] Plan needs FIX: ${BASENAME} (project=${PROJECT})" >&2
    fi

    # Log transition to Redis
    redis-cli LPUSH "plan:status:history" "${TIMESTAMP}|${OLD_STATUS}→${NEW_STATUS}|${BASENAME}" >/dev/null 2>&1
    redis-cli LTRIM "plan:status:history" 0 499 >/dev/null 2>&1

) 200>"${FILEPATH}.lock"

# Cleanup lock file
rm -f "${FILEPATH}.lock" 2>/dev/null

exit 0
