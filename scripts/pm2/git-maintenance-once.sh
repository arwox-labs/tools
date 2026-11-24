#!/bin/bash
# ============================================================================
# Scheduler: git-maintenance-once.sh
# Purpose: One-shot git maintenance run (extracted from git-maintenance-pm2.sh)
# Trigger: PM2 cron_restart every 2 hours
# ADR-001: Converted from daemon to scheduled execution
# SAFE for 8GB RAM: no --aggressive, window=10, nice/ionice, memory cap
# ============================================================================
set +e

# Memory safety
ulimit -v 1048576  # 1GB address-space cap: prune of agent-contour fails mmap under 512MB (dcfg-9xqv1)
GIT_MEM=(-c core.packedGitLimit=128m -c core.packedGitWindowSize=32m -c pack.threads=1)  # keep pack mmap under ulimit -v (dcfg-9xqv1)

LOG_FILE="/root/workspaces/system/tools/scripts/logs/git-maintenance.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Limit git memory usage
export GIT_PACK_WINDOW_MEMORY=128m

REPOS=(
    "/root/workspaces/projects"
    "/root/workspaces/projects/claude-state"
    "/root/workspaces/projects/b24-arwox"
"/root/workspaces/projects/telegram-ai-bot"
    "/root/workspaces/projects/photo_downloader_dist"
    "/root/workspaces/projects/voice-transcriber"
    "/root/workspaces/projects/voiceflow-app"
    "/root/workspaces/projects/win10-assistant-setup"
    "/root/workspaces/projects/yubikey-v1"
    "/root/workspaces/projects/yubikey-v2"
    "/root/workspaces/projects/scripts_others"
)

. /root/workspaces/tools/bin/git-auto-lib
PROJ_GIT_DIR=$(ga_projects_gitdir)

log "=== GIT MAINTENANCE START ==="

TOTAL_BEFORE=0
TOTAL_AFTER=0

for REPO in "${REPOS[@]}"; do
    GD="$REPO/.git"
    if [ "$REPO" = "/root/workspaces/projects" ]; then
        GD="$PROJ_GIT_DIR"
    fi

    if [ ! -e "$GD" ]; then
        log "skip $REPO (no git dir)"
        continue
    fi

    cd "$REPO" || continue

    if [ "$REPO" = "/root/workspaces/projects" ]; then
        export GIT_DIR="$GD"
    fi

    # Skip repos with .git < 50MB (not worth optimizing)
    GIT_SIZE=$(du -sm "$GD" 2>/dev/null | cut -f1)
    if [ "${GIT_SIZE:-0}" -lt 50 ]; then
        log "  Skip $REPO (${GIT_SIZE}MB < 50MB threshold)"
        unset GIT_DIR
        continue
    fi

    # Remove stale locks
    rm -f "$GD/index.lock" "$GD/gc.pid" 2>/dev/null

    SIZE_BEFORE=$(du -sm "$GD" 2>/dev/null | cut -f1)
    TOTAL_BEFORE=$((TOTAL_BEFORE + SIZE_BEFORE))

    log "--- $REPO (${SIZE_BEFORE}MB) ---"

    # 1. Expire old reflog (keep 30 days)
    git "${GIT_MEM[@]}" reflog expire --expire=30.days --all 2>/dev/null

    # 2. Standard gc (NO --aggressive, safe for RAM)
    nice -n 19 ionice -c3 git "${GIT_MEM[@]}" gc 2>&1 | tail -3 >> "$LOG_FILE"

    # 3. Light repack (window=10 = ~100MB RAM max)
    nice -n 19 ionice -c3 git "${GIT_MEM[@]}" repack -A -d --depth=50 --window=10 2>/dev/null

    # 4. Prune unreachable
    git "${GIT_MEM[@]}" prune --expire=2.weeks.ago 2>/dev/null

    # 5. Prune stale remote branches
    git remote prune origin 2>/dev/null

    SIZE_AFTER=$(du -sm "$GD" 2>/dev/null | cut -f1)
    TOTAL_AFTER=$((TOTAL_AFTER + SIZE_AFTER))
    SAVED=$((SIZE_BEFORE - SIZE_AFTER))

    log "  ${SIZE_BEFORE}MB -> ${SIZE_AFTER}MB (saved ${SAVED}MB)"

    unset GIT_DIR

    # Pause 30s between repos to spread load
    sleep 30
done

TOTAL_SAVED=$((TOTAL_BEFORE - TOTAL_AFTER))
log "=== COMPLETE: ${TOTAL_BEFORE}MB -> ${TOTAL_AFTER}MB (saved ${TOTAL_SAVED}MB) ==="

exit 0
