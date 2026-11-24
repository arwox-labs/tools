#!/bin/bash
# PM2 Conductor — Self-Healing Process Orchestrator
# Monitors PM2 processes, detects errors, auto-fixes or escalates

set -o pipefail

# Configuration
CONDUCTOR_HOME="/root/workspaces/tools/acc1-scripts"
CONFIG_FILE="$CONDUCTOR_HOME/config/error-patterns.json"
LOG_FILE="$CONDUCTOR_HOME/logs/conductor.log"
DATA_FILE="$CONDUCTOR_HOME/data/conductor-state.json"
REDIS_DB="${CONDUCTOR_REDIS_DB:-3}"
POLL_INTERVAL="${CONDUCTOR_POLL_INTERVAL:-30}"
MODE="${CONDUCTOR_MODE:-production}"
EXCLUDE_LIST="${CONDUCTOR_EXCLUDE:-hr-bot-v2,hh-import,hh-refetch,pm2-conductor,backup-watcher}"

# Source helper functions
source "$CONDUCTOR_HOME/scripts/conductor-rate-limit.sh"
source "$CONDUCTOR_HOME/scripts/conductor-escalate.sh"
source "$CONDUCTOR_HOME/scripts/conductor-dedup.sh"

# Ensure directories exist
mkdir -p "$CONDUCTOR_HOME/logs" "$CONDUCTOR_HOME/data"

# Initialize log
log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
  [ "$MODE" = "debug" ] && echo "[CONDUCTOR] $1"
}

log "========== PM2 Conductor Starting =========="
log "Mode: $MODE, Poll interval: ${POLL_INTERVAL}s"

# Load error patterns
load_patterns() {
  if [ -f "$CONFIG_FILE" ]; then
    cat "$CONFIG_FILE"
  else
    log "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
  fi
}

# Match error against patterns
match_error_pattern() {
  local error_text=$1
  local patterns=$(load_patterns)

  # Check each pattern
  echo "$patterns" | jq -r '.patterns[] | "\(.regex)|\(.level)|\(.action)|\(.params | @json)"' | while IFS='|' read -r regex level action params; do
    if echo "$error_text" | grep -qiE "$regex"; then
      echo "$level|$action|$params"
      return 0
    fi
  done

  # Return default if no match
  echo "$patterns" | jq -r '"\(.default.level)|\(.default.action)|\(.default.params | @json)"'
}

# Controlled restart via wrapper (V101 compliant)
conductor_restart() {
  local app_name=$1
  local reason=$2
  bash "$CONDUCTOR_HOME/scripts/pm2-controlled-restart.sh" \
    "$app_name" "Error-Triage" \
    "Conductor auto-fix: $reason. Detected by pm2-conductor monitoring loop." \
    >/dev/null 2>&1
  return $?
}

# Execute Level 1 auto-fix
execute_level1_fix() {
  local app_name=$1
  local action=$2
  local params=$3

  log "Level 1 fix for $app_name: $action"

  case "$action" in
    restart_simple)
      conductor_restart "$app_name" "Simple restart triggered by error pattern match (action=$action)"
      ;;
    restart_delayed)
      local delay=$(echo "$params" | jq -r '.delay // 5000')
      sleep $((delay / 1000))
      conductor_restart "$app_name" "Delayed restart after ${delay}ms wait (action=$action)"
      ;;
    check_dependency)
      local check_cmd=$(echo "$params" | jq -r '.check')
      if eval "$check_cmd" >/dev/null 2>&1; then
        conductor_restart "$app_name" "Dependency check passed, restart needed (action=$action)"
      else
        log "Dependency check failed for $app_name"
        return 1
      fi
      ;;
    *)
      conductor_restart "$app_name" "Default restart action (action=$action)"
      ;;
  esac

  return $?
}

# Execute Level 2 Claude fix
execute_level2_fix() {
  local app_name=$1
  local error_text=$2
  local context=$3

  # Check rate limit
  if ! check_rate_limit >/dev/null; then
    log "Rate limit exceeded, skipping Claude fix"
    return 1
  fi

  # Dedup: skip if permanently broken
  if is_permanently_broken "$app_name"; then
      log "DEDUP: $app_name permanently broken, skipping"
      return 1
  fi
  # Dedup: skip if same error repeated >3 times
  local dedup_result=$(check_error_changed "$app_name" "$error_text")
  if [[ "$dedup_result" == "SKIP" ]]; then
      log "DEDUP: $app_name error unchanged (>3x same), skipping"
      return 1
  fi

  log "Level 2 fix for $app_name: invoking Timeweb AI"

  # Build prompt
  local prompt=$(cat <<EOF
## PM2 Process Error Analysis

**Process:** $app_name
**Context:** $context
**Error log:**
\`\`\`
$(echo "$error_text" | tail -50)
\`\`\`

Analyze and provide a fix. Output JSON:
{
  "root_cause": "brief explanation",
  "fix_command": "command to run" or null,
  "severity": 1-3,
  "needs_human": true/false
}
EOF
)

  # Call Timeweb AI (grok3-mini) instead of Claude
  local result=$("$CONDUCTOR_HOME/scripts/timeweb-agent.sh" chat grok3-mini "$prompt" 500 0.2 2>/dev/null)

  # Increment rate counter
  increment_calls

  # Parse result — timeweb returns plain text; try JSON, else wrap as fallback
  local parsed
  if echo "$result" | jq -r '.' >/dev/null 2>&1; then
    parsed="$result"
  else
    parsed="{\"root_cause\":\"$result\",\"fix_command\":\"\",\"severity\":1,\"needs_human\":true}"
  fi

  # Parse result
  local fix_cmd=$(echo "$parsed" | jq -r '.fix_command // empty' 2>/dev/null)
  local needs_human=$(echo "$parsed" | jq -r '.needs_human // false' 2>/dev/null)

  if [ "$needs_human" = "true" ]; then
    log "Timeweb AI says human intervention needed"
    # Check if same error count >= 5 and mark permanently broken
    local same_count=$(redis-cli -n $REDIS_DB GET "conductor:same-error-count:$app_name" 2>/dev/null)
    if [[ "${same_count:-0}" -ge 5 ]]; then
        mark_permanently_broken "$app_name"
        log "ESCALATE: $app_name marked permanently broken after 5+ same errors"
    fi
    return 1
  fi

  if [ -n "$fix_cmd" ] && [ "$fix_cmd" != "null" ]; then
    log "Executing Timeweb AI fix: $fix_cmd"

    if [ "$MODE" = "dry-run" ]; then
      log "[DRY-RUN] Would execute: $fix_cmd"
    else
      eval "$fix_cmd"
    fi

    # Record fix attempt
    redis-cli -n $REDIS_DB LPUSH "conductor:fixes:$app_name" "$(date -Iseconds): $fix_cmd" >/dev/null
    redis-cli -n $REDIS_DB LTRIM "conductor:fixes:$app_name" 0 9 >/dev/null

    return $?
  fi

  # No fix command: check if permanently broken threshold reached
  local same_count=$(redis-cli -n $REDIS_DB GET "conductor:same-error-count:$app_name" 2>/dev/null)
  if [[ "${same_count:-0}" -ge 5 ]]; then
      mark_permanently_broken "$app_name"
      log "ESCALATE: $app_name marked permanently broken after 5+ same errors"
  fi

  return 1
}

# Check circuit breaker
check_circuit_breaker() {
  local app_name=$1
  local failures=$(redis-cli -n $REDIS_DB GET "conductor:failures:$app_name" 2>/dev/null || echo "0")

  if [ "${failures:-0}" -ge 3 ]; then
    log "Circuit breaker OPEN for $app_name (failures: $failures)"
    return 1
  fi
  return 0
}

# Increment failure counter
record_failure() {
  local app_name=$1
  redis-cli -n $REDIS_DB INCR "conductor:failures:$app_name" >/dev/null
  redis-cli -n $REDIS_DB EXPIRE "conductor:failures:$app_name" 3600 >/dev/null  # 1h TTL
}

# Reset failure counter on success
reset_failures() {
  local app_name=$1
  redis-cli -n $REDIS_DB DEL "conductor:failures:$app_name" >/dev/null
}

# Process a single errored app
process_errored_app() {
  local app_name=$1
  local status=$2
  local restarts=$3

  log "Processing errored app: $app_name (status: $status, restarts: $restarts)"

  # Check circuit breaker — if OPEN, SKIP silently (already escalated once)
  if ! check_circuit_breaker "$app_name"; then
    # Only escalate on first circuit breaker trigger (failures == 3)
    local cb_failures=$(redis-cli -n $REDIS_DB GET "conductor:failures:$app_name" 2>/dev/null || echo "0")
    if [ "${cb_failures:-0}" -eq 3 ]; then
      escalate "$app_name" "Circuit breaker triggered after 3 failures" "$(pm2 logs "$app_name" --err --lines 50 --nostream 2>/dev/null)"
      # Increment to 4 so we don't escalate again
      redis-cli -n $REDIS_DB INCR "conductor:failures:$app_name" >/dev/null
    fi
    return 1
  fi

  # Get error log
  local error_log=$(pm2 logs "$app_name" --err --lines 100 --nostream 2>/dev/null)

  # Match pattern
  local match=$(match_error_pattern "$error_log")
  local level=$(echo "$match" | cut -d'|' -f1)
  local action=$(echo "$match" | cut -d'|' -f2)
  local params=$(echo "$match" | cut -d'|' -f3-)

  log "Matched: level=$level, action=$action"

  case "$level" in
    1)
      if execute_level1_fix "$app_name" "$action" "$params"; then
        log "Level 1 fix successful for $app_name"
        reset_failures "$app_name"
      else
        record_failure "$app_name"
      fi
      ;;
    2)
      local context=$(echo "$params" | jq -r '.context // "unknown"')
      if execute_level2_fix "$app_name" "$error_log" "$context"; then
        log "Level 2 fix successful for $app_name"
        reset_failures "$app_name"
      else
        record_failure "$app_name"
        # Retry as Level 3 if Claude fix failed
        if [ "$(redis-cli -n $REDIS_DB GET "conductor:failures:$app_name")" -ge 2 ]; then
          escalate "$app_name" "Level 2 fix failed twice" "$error_log"
        fi
      fi
      ;;
    3)
      log "Level 3: Escalating $app_name"
      escalate "$app_name" "Critical error detected" "$error_log"
      ;;
  esac
}

# Main monitoring loop
main_loop() {
  while true; do
    # Get list of errored or high-restart processes
    # Exclude list from CONDUCTOR_EXCLUDE env var (set in pm2-conductor.json config)
    local errored=$(pm2 jlist 2>/dev/null | jq -r --arg exclude "${EXCLUDE_LIST:-}" '.[] | select((.pm2_env.status == "errored" or .pm2_env.restart_time > 5) and (if ($exclude | length) > 0 then (.name | IN($exclude | split(",")[])) == false else true end)) | "\(.name)|\(.pm2_env.status)|\(.pm2_env.restart_time)"')

    if [ -n "$errored" ]; then
      echo "$errored" | while IFS='|' read -r name status restarts; do
        [ -n "$name" ] && process_errored_app "$name" "$status" "$restarts"
      done
    fi

    # Update state file
    cat > "$DATA_FILE" <<EOF
{
  "last_check": "$(date -Iseconds)",
  "mode": "$MODE",
  "rate": $(get_rate_stats)
}
EOF

    sleep "$POLL_INTERVAL"
  done
}

# Start
main_loop
