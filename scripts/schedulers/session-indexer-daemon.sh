#!/bin/bash
# session-indexer-daemon.sh — PM2 daemon, every 60 seconds
# Indexes JSONL session files into Redis session:registry + topic:index
# K1 FIX: Uses find projects/ -name "*.jsonl" for deep nested paths
# Issue: #230 (Context System v2)

set +e

INTERVAL=60
LOGFILE="/root/workspaces/system/tools/scripts/logs/session-indexer.log"
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
BASE_DIR="/root/workspaces/system/tools/scripts"
PROJECTS_DIR="$BASE_DIR/projects"
TOPIC_EXTRACTOR="$BASE_DIR/scripts/topic-extractor.sh"
MAX_PER_CYCLE=10
PAUSE_BETWEEN=2

mkdir -p "$(dirname "$LOGFILE")"

. /root/workspaces/tools/bin/git-auto-lib
PROJ_GIT_DIR=$(ga_projects_gitdir)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

log "Session indexer daemon started (PID: $$, Interval: ${INTERVAL}s, Max/cycle: $MAX_PER_CYCLE)"

while true; do
    # Redis check
    if ! rcli PING >/dev/null 2>&1; then
        log "Redis unavailable, skip cycle"
        sleep "$INTERVAL"
        continue
    fi

    INDEXED=0
    SKIPPED=0

    # K1: Find all JSONL files recursively in projects/
    # Skip subagents/ for now (K4: speed up initial indexing)
    while IFS= read -r jsonl_path; do
        [ -z "$jsonl_path" ] && continue
        [ "$INDEXED" -ge "$MAX_PER_CYCLE" ] && break

        # Extract session ID from filename (without .jsonl)
        FILENAME=$(basename "$jsonl_path" .jsonl)

        # Skip non-UUID filenames (agent-*, subagent files)
        if [[ "$FILENAME" == agent-* ]] || [[ "$FILENAME" == subagent-* ]]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        # Check if already indexed by checking session:registry exists
        REG_EXISTS=$(rcli EXISTS "session:registry:${FILENAME}")
        if [ "$REG_EXISTS" = "1" ]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        # Also check fingerprint dedup
        MSG_COUNT=$(wc -l < "$jsonl_path" 2>/dev/null || echo "0")
        FINGERPRINT=$(echo -n "${FILENAME}:${MSG_COUNT}" | sha1sum | cut -d' ' -f1)
        IS_INDEXED=$(rcli SISMEMBER "session:indexed" "$FINGERPRINT")
        if [ "$IS_INDEXED" = "1" ]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        # Extract metadata
        TIMESTAMP=$(stat -c%Y "$jsonl_path" 2>/dev/null || echo "0")
        TS_ISO=$(date -d "@$TIMESTAMP" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)

        # Extract CWD from JSONL content
        SESSION_CWD=$(head -5 "$jsonl_path" 2>/dev/null | jq -r 'select(.cwd) | .cwd' 2>/dev/null | head -1)
        [ -z "$SESSION_CWD" ] && SESSION_CWD="unknown"

        # Extract git branch from CWD (not from JSONL — JSONL doesn't store branch)
        GIT_BRANCH="unknown"
        if [ -d "$SESSION_CWD/.git" ] 2>/dev/null; then
            GIT_BRANCH=$(git -C "$SESSION_CWD" branch --show-current 2>/dev/null || echo "unknown")
        elif [ "$SESSION_CWD" = "/root/workspaces/projects" ] || [[ "$SESSION_CWD" == /root/workspaces/projects/* ]]; then
            GIT_BRANCH=$(git --git-dir="$PROJ_GIT_DIR" --work-tree=/root/workspaces/projects branch --show-current 2>/dev/null || echo unknown)
            [ -z "$GIT_BRANCH" ] && GIT_BRANCH="unknown"
        fi

        # Extract active issue
        ACTIVE_ISSUE=$(tail -50 "$jsonl_path" 2>/dev/null | jq -r 'select(.type == "user") | .message.content // empty' 2>/dev/null | grep -oP '#\d+' | tail -1 | tr -d '#')
        [ -z "$ACTIVE_ISSUE" ] && ACTIVE_ISSUE="none"

        # Detect role from path
        ROLE="unknown"
        if echo "$jsonl_path" | grep -q "subagents/"; then
            ROLE="subagent"
        fi

        # Extract project name from JSONL path
        PROJECT_DIR=$(dirname "$jsonl_path")
        PROJECT_NAME=$(basename "$PROJECT_DIR" | sed 's/^-root-claude-projects-//; s/^-root-claude-projects$/main/; s/^-root-//')
        [ -z "$PROJECT_NAME" ] && PROJECT_NAME="unknown"

        # Extract topics (20 keywords with improved UTF-8 tokenizer)
        TOPICS=""
        if [ -x "$TOPIC_EXTRACTOR" ]; then
            TOPICS=$(bash "$TOPIC_EXTRACTOR" "$jsonl_path" 20 2>/dev/null)
        fi

        # Create registry entry (with project and cwd fields)
        rcli HSET "session:registry:${FILENAME}" \
            "timestamp" "$TS_ISO" \
            "message_count" "$MSG_COUNT" \
            "git_branch" "$GIT_BRANCH" \
            "cwd" "$SESSION_CWD" \
            "project" "$PROJECT_NAME" \
            "active_issue" "$ACTIVE_ISSUE" \
            "role" "$ROLE" \
            "agent_model" "unknown" \
            "topics" "$TOPICS" \
            "fingerprint" "$FINGERPRINT" \
            "session_file" "$jsonl_path" >/dev/null
        rcli EXPIRE "session:registry:${FILENAME}" 259200 >/dev/null

        # Add fingerprint to dedup set
        rcli SADD "session:indexed" "$FINGERPRINT" >/dev/null
        rcli EXPIRE "session:indexed" 259200 >/dev/null

        # Index topics
        if [ -n "$TOPICS" ]; then
            for keyword in $TOPICS; do
                rcli SADD "topic:index:${keyword}" "$FILENAME" >/dev/null
                rcli EXPIRE "topic:index:${keyword}" 259200 >/dev/null
            done
        fi

        # Index project
        if [ "$PROJECT_NAME" != "unknown" ]; then
            rcli SADD "project:index:${PROJECT_NAME}" "$FILENAME" >/dev/null
            rcli EXPIRE "project:index:${PROJECT_NAME}" 259200 >/dev/null
        fi

        INDEXED=$((INDEXED + 1))
        log "Indexed: ${FILENAME:0:12}... (${MSG_COUNT} msgs, topics: ${TOPICS:-none})"

        sleep "$PAUSE_BETWEEN"

    done < <(find "$PROJECTS_DIR" -name "*.jsonl" -not -path "*/subagents/*" -type f 2>/dev/null | sort -t/ -k1)

    if [ "$INDEXED" -gt 0 ] || [ "$SKIPPED" -gt 0 ]; then
        TOTAL_REG=$(rcli --scan --pattern "session:registry:*" | wc -l)
        log "Cycle: indexed=$INDEXED, skipped=$SKIPPED, total_registry=$TOTAL_REG"
    fi

    sleep "$INTERVAL"
done
