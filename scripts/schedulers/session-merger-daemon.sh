#!/bin/bash
# PM2 Scheduler: Session History Merger (daily at 2:00 AM)
# Issue: #230 (Context System v2)
# Fixes: Bug #3 (timestamp format), Bug #4 (sessions_count)
# Rewritten to use session:registry HASH instead of parsing history LIST
set +e

TARGET_HOUR=2
TARGET_MIN=0
LOG_FILE="/root/workspaces/system/tools/scripts/logs/session-merger.log"
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
DAILY_DIR="/root/workspaces/system/tools/scripts/context/daily"

mkdir -p "$DAILY_DIR"

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

log() {
    echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
}

log "Session merger daemon started (PID: $$)"

while true; do
    current_hour=$(date +%H)
    current_min=$(date +%M)

    now_sec=$((10#$current_hour * 3600 + 10#$current_min * 60))
    target_sec=$((TARGET_HOUR * 3600 + TARGET_MIN * 60))

    if [ $now_sec -ge $target_sec ]; then
        sleep_sec=$((86400 - now_sec + target_sec))
    else
        sleep_sec=$((target_sec - now_sec))
    fi

    log "Next run in ${sleep_sec}s (at 02:00)"
    sleep $sleep_sec

    log "Running session history merger v2"

    # Redis check
    if ! rcli PING >/dev/null 2>&1; then
        log "ERROR: Redis unavailable"
        sleep 60
        continue
    fi

    # === V2: Use session:registry instead of parsing history LIST ===
    # Collect all sessions from registry, group by date+branch
    declare -A date_branch_sessions
    declare -A date_branch_msgs
    declare -A date_branch_issues
    declare -A date_branch_roles
    declare -A date_branch_models
    declare -A date_branch_first
    declare -A date_branch_last
    declare -A date_branch_cwd

    session_count=0

    while IFS= read -r key; do
        [ -z "$key" ] && continue
        sid="${key#session:registry:}"

        # BUG #3 FIX: Support both ISO (T separator) and space-separated timestamps
        ts=$(rcli HGET "$key" "timestamp")
        [ -z "$ts" ] && continue

        # Normalize: extract date part (works for both "2026-02-07T12:30:00" and "2026-02-07 12:30:00")
        date="${ts%%T*}"
        date="${date%% *}"
        [ -z "$date" ] && continue

        # Extract time part
        time_part="${ts#*T}"
        time_part="${time_part#* }"
        time_hm="${time_part:0:5}"

        branch=$(rcli HGET "$key" "git_branch")
        [ -z "$branch" ] && branch="unknown"

        db_key="${date}:${branch}"

        # BUG #4 FIX: Count sessions correctly
        prev_count="${date_branch_sessions[$db_key]:-0}"
        date_branch_sessions[$db_key]=$((prev_count + 1))

        # Aggregate messages
        msgs=$(rcli HGET "$key" "message_count")
        prev_msgs="${date_branch_msgs[$db_key]:-0}"
        date_branch_msgs[$db_key]=$((prev_msgs + ${msgs:-0}))

        # Aggregate issues
        issue=$(rcli HGET "$key" "active_issue")
        if [ -n "$issue" ] && [ "$issue" != "none" ] && [ "$issue" != "null" ]; then
            prev_issues="${date_branch_issues[$db_key]:-}"
            if ! echo "$prev_issues" | grep -q "$issue"; then
                date_branch_issues[$db_key]="${prev_issues:+$prev_issues,}$issue"
            fi
        fi

        # Aggregate roles
        role=$(rcli HGET "$key" "role")
        if [ -n "$role" ]; then
            prev_roles="${date_branch_roles[$db_key]:-}"
            case "$role" in
                prompt-engineer) date_branch_roles[$db_key]=$(echo "$prev_roles" | awk -F: -v r="$role" '
                    BEGIN{found=0} {for(i=1;i<=NF;i++){split($i,a,"=");if(a[1]==r){a[2]++;found=1;printf "%s=%s",a[1],a[2];if(i<NF)printf ":"}else{printf "%s",$i;if(i<NF)printf ":"}}} END{if(!found){if(NR>0)printf ":";printf "%s=1",r}}' 2>/dev/null)
                ;;
                *) # Simple counter approach
                ;;
            esac
            # Simplified: just track which roles were used
            if ! echo "$prev_roles" | grep -q "$role"; then
                date_branch_roles[$db_key]="${prev_roles:+$prev_roles,}$role"
            fi
        fi

        # Aggregate models
        model=$(rcli HGET "$key" "agent_model")
        if [ -n "$model" ]; then
            prev_models="${date_branch_models[$db_key]:-}"
            if ! echo "$prev_models" | grep -q "$model"; then
                date_branch_models[$db_key]="${prev_models:+$prev_models,}$model"
            fi
        fi

        # Track first/last session time
        first="${date_branch_first[$db_key]:-}"
        if [ -z "$first" ] || [[ "$time_hm" < "$first" ]]; then
            date_branch_first[$db_key]="$time_hm"
        fi
        last="${date_branch_last[$db_key]:-}"
        if [ -z "$last" ] || [[ "$time_hm" > "$last" ]]; then
            date_branch_last[$db_key]="$time_hm"
        fi

        session_count=$((session_count + 1))
    done < <(rcli --scan --pattern "session:registry:*")

    if [ "$session_count" -eq 0 ]; then
        # Fallback: also check context:history for backward compatibility
        history_count=$(rcli LLEN "context:history")
        if [ "${history_count:-0}" -eq 0 ]; then
            log "No sessions in registry or history, skip"
            sleep 60
            continue
        fi
        log "No registry entries but $history_count history entries — registry not yet populated"
    fi

    # Create daily summaries
    summaries_created=0

    for db_key in "${!date_branch_sessions[@]}"; do
        date="${db_key%%:*}"
        branch="${db_key#*:}"

        sessions="${date_branch_sessions[$db_key]}"
        total_msgs="${date_branch_msgs[$db_key]}"
        issues_str="${date_branch_issues[$db_key]:-}"
        roles_str="${date_branch_roles[$db_key]:-}"
        models_str="${date_branch_models[$db_key]:-}"
        first_t="${date_branch_first[$db_key]:-}"
        last_t="${date_branch_last[$db_key]:-}"

        # Build issues JSON array
        issues_json=$(echo "$issues_str" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -s '.')

        # Build roles JSON object (count occurrences)
        roles_json="{}"
        for r in $(echo "$roles_str" | tr ',' '\n' | grep -v '^$'); do
            roles_json=$(echo "$roles_json" | jq --arg k "$r" '.[$k] = ((.[$k] // 0) + 1)')
        done

        # Build models JSON object
        models_json="{}"
        for m in $(echo "$models_str" | tr ',' '\n' | grep -v '^$'); do
            models_json=$(echo "$models_json" | jq --arg k "$m" '.[$k] = ((.[$k] // 0) + 1)')
        done

        summary=$(jq -n \
            --arg type "daily_summary" \
            --arg date "$date" \
            --arg branch "$branch" \
            --argjson sessions "$sessions" \
            --argjson total_msgs "$total_msgs" \
            --argjson issues "$issues_json" \
            --argjson roles "$roles_json" \
            --argjson models "$models_json" \
            --arg first "$first_t" \
            --arg last "$last_t" \
            '{
                type: $type,
                date: $date,
                branch: $branch,
                sessions_count: $sessions,
                total_messages: $total_msgs,
                issues_worked: $issues,
                roles_used: $roles,
                models_used: $models,
                first_session: $first,
                last_session: $last
            }')

        # Save to Redis (3 days TTL)
        echo "$summary" | rcli -x SET "context:daily:${date}:${branch}" EX 259200 >/dev/null

        # Save to file
        echo "$summary" | jq . > "${DAILY_DIR}/${date}.json" 2>/dev/null

        log "Summary: $date ($branch) — $sessions sessions, $total_msgs msgs"
        summaries_created=$((summaries_created + 1))
    done

    # Trim history to keep last 20 entries (v2: increased from 5)
    rcli LTRIM context:history 0 19 >/dev/null

    log "Completed: $session_count sessions processed, $summaries_created summaries created"

    sleep 60
done
