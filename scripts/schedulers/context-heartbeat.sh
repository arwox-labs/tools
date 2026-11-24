#!/bin/bash
# ============================================================================
# Scheduler: context-heartbeat.sh
# Purpose: Background context save every 60 seconds
# Trigger: PM2 cron or manual
# Level: 3 (Tertiary protection - crash recovery)
# Issue: #221
# ============================================================================

set +e

# Load centralized PE detection library
PE_LIB="$(dirname "$0")/../hooks/lib/pe-detect.sh"
[[ -f "$PE_LIB" ]] && source "$PE_LIB"

REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
CONTEXT_DIR="/root/workspaces/tools/acc1-scripts/context"
PROJECTS_DIR="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/context-heartbeat.log"
HEARTBEAT_FILE="/root/workspaces/tools/acc1-scripts/data/context-heartbeat.txt"

mkdir -p "$CONTEXT_DIR" "$(dirname "$LOG_FILE")" "$(dirname "$HEARTBEAT_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Find latest active session
SESSION_FILE=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1)
if [ -z "$SESSION_FILE" ]; then
    log "No active session"
    exit 0
fi

# Check if session is active (modified in last 5 minutes)
SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
NOW=$(date +%s)
DIFF=$((NOW - SESSION_MTIME))

if [ "$DIFF" -gt 300 ]; then
    # Session inactive for >5 min, skip
    log "Session inactive ($DIFF seconds)"
    exit 0
fi

SESSION_ID=$(basename "$SESSION_FILE" .jsonl)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Extract recent messages for heartbeat
LAST_MESSAGES=$(tail -100 "$SESSION_FILE" 2>/dev/null | \
    jq -r 'select(.type == "user" and (.message.content | type == "string")) | .message.content' 2>/dev/null | \
    grep -v "task-notification" | grep -v "tool_result" | grep -v "system-reminder" | \
    tail -10 | head -c 3000)

# Get state
CWD=$(pwd 2>/dev/null || echo "/root/workspaces/projects")
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ACTIVE_ISSUE=$(cat "/root/workspaces/tools/acc1-scripts/data/active-issue.txt" 2>/dev/null || echo "none")
MSG_COUNT=$(wc -l < "$SESSION_FILE" 2>/dev/null || echo "0")

# Detect role
if type is_pe_session &>/dev/null && is_pe_session; then
    ROLE="prompt-engineer"
elif [ -f /tmp/.prompt-engineer-session ]; then
    ROLE="prompt-engineer"
else
    ROLE="senior-dev"
fi
AGENT_MODEL="${CLAUDE_MODEL:-opus}"

# Create heartbeat JSON
HEARTBEAT_JSON=$(cat <<EOF
{
    "session_id": "$SESSION_ID",
    "timestamp": "$TIMESTAMP",
    "cwd": "$CWD",
    "git_branch": "$GIT_BRANCH",
    "active_issue": "$ACTIVE_ISSUE",
    "role": "$ROLE",
    "agent_model": "$AGENT_MODEL",
    "message_count": $MSG_COUNT,
    "session_file": "$SESSION_FILE",
    "last_messages": $(echo "$LAST_MESSAGES" | jq -Rs .),
    "saved_by": "context-heartbeat.sh",
    "level": 3,
    "session_age_seconds": $DIFF
}
EOF
)

# Save heartbeat to Redis (medium TTL - 6 hours)
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "context:heartbeat" "$HEARTBEAT_JSON" EX 21600 >/dev/null 2>&1

# Also update latest if Stop hook hasn't run recently
LATEST_TIME=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "context:latest" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null)
if [ -z "$LATEST_TIME" ]; then
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "context:latest" "$HEARTBEAT_JSON" EX 259200 >/dev/null 2>&1
    log "Heartbeat promoted to latest"
fi

# Update heartbeat timestamp
echo "$NOW" > "$HEARTBEAT_FILE"

log "Heartbeat: session=$SESSION_ID, msgs=$MSG_COUNT, age=${DIFF}s"

exit 0
