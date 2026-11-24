#!/bin/bash
# redis-backup-daemon.sh — Daily Redis backup to git
# PM2: pm2 start --no-autorestart --max-memory-restart 100M
set +e
ulimit -v 524288

INTERVAL=86400  # 24 hours
BACKUP_DIR="/root/workspaces/system/tools/scripts/backups/redis"
REDIS_DUMP="/var/lib/redis/dump.rdb"
KEEP_DAYS=3

mkdir -p "$BACKUP_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2; }

while true; do
    log "=== REDIS BACKUP START ==="

    # 1. Force Redis to save
    redis-cli BGSAVE >/dev/null 2>&1
    sleep 5  # Wait for save to complete

    # 2. Copy current dump
    if [ -f "$REDIS_DUMP" ]; then
        cp "$REDIS_DUMP" "$BACKUP_DIR/dump.rdb"
        cp "$REDIS_DUMP" "$BACKUP_DIR/dump-$(date +%Y%m%d).rdb"
        log "Copied dump.rdb ($(du -sh "$REDIS_DUMP" | cut -f1))"
    else
        log "ERROR: $REDIS_DUMP not found"
    fi

    # 3. Delete old backups (keep last KEEP_DAYS)
    find "$BACKUP_DIR" -name "dump-*.rdb" -mtime +$KEEP_DAYS -delete 2>/dev/null

    # 4. Commit and push
    cd /root/workspaces/system/tools/scripts
    nice -n 19 git add backups/redis/ 2>/dev/null
    nice -n 19 git commit -m "backup: daily Redis dump $(date +%Y-%m-%d)" --quiet 2>/dev/null
    nice -n 19 git push origin main --quiet 2>/dev/null

    log "=== REDIS BACKUP COMPLETE ==="
    log "Sleeping ${INTERVAL}s until next backup..."
    sleep $INTERVAL
done
