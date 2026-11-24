#!/bin/bash
# docker-clean-rotation.sh
# Keeps only the last 3 backups in /var/backups/docker-clean/
# Removes anything older than 3 days
# Safe: never removes if fewer than 2 backups exist (keeps at least 1)

BACKUP_DIR="/var/backups/docker-clean"
LOG_FILE="/var/log/docker-clean-rotation.log"
KEEP=3
MIN_BACKUPS=1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log "=== docker-clean-rotation START ==="

# Ensure backup dir exists
if [ ! -d "$BACKUP_DIR" ]; then
    log "Backup dir $BACKUP_DIR does not exist. Nothing to do."
    log "=== docker-clean-rotation END ==="
    exit 0
fi

# Count all backup directories
ALL_BACKUPS=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" | sort)
TOTAL=$(echo "$ALL_BACKUPS" | grep -c "backup-" 2>/dev/null || echo 0)

log "Found $TOTAL backup(s) in $BACKUP_DIR"

# Safety check: if <= MIN_BACKUPS, do not delete anything
if [ "$TOTAL" -le "$MIN_BACKUPS" ]; then
    log "SAFETY CHECK: Only $TOTAL backup(s) exist (minimum=$MIN_BACKUPS). Nothing deleted."
    log "=== docker-clean-rotation END ==="
    exit 0
fi

# Step 1: Remove backups older than 3 days
log "Step 1: Removing backups older than 3 days..."
OLD_DIRS=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" -mtime +3)

if [ -z "$OLD_DIRS" ]; then
    log "No backups older than 3 days found."
else
    # Re-count after potential removal — safety: ensure we keep at least MIN_BACKUPS
    while IFS= read -r dir; do
        REMAINING=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" | wc -l)
        if [ "$REMAINING" -le "$MIN_BACKUPS" ]; then
            log "SAFETY STOP: Only $REMAINING backup(s) remain. Stopping deletion."
            break
        fi
        log "Removing old backup (>3 days): $dir"
        rm -rf "$dir"
    done <<< "$OLD_DIRS"
fi

# Step 2: Keep only the last KEEP backups by modification time
log "Step 2: Enforcing max $KEEP backups policy..."
# List backups sorted by time, oldest first
SORTED_BACKUPS=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" -printf "%T@ %p\n" | sort -n | awk '{print $2}')
CURRENT_COUNT=$(echo "$SORTED_BACKUPS" | grep -c "backup-" 2>/dev/null || echo 0)

if [ "$CURRENT_COUNT" -gt "$KEEP" ]; then
    TO_DELETE_COUNT=$((CURRENT_COUNT - KEEP))
    log "Need to remove $TO_DELETE_COUNT oldest backup(s) to keep only $KEEP"

    echo "$SORTED_BACKUPS" | head -n "$TO_DELETE_COUNT" | while IFS= read -r dir; do
        REMAINING=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" | wc -l)
        if [ "$REMAINING" -le "$MIN_BACKUPS" ]; then
            log "SAFETY STOP: Only $REMAINING backup(s) remain. Stopping."
            break
        fi
        log "Removing excess backup: $dir"
        rm -rf "$dir"
    done
else
    log "Count=$CURRENT_COUNT is within limit of $KEEP. No rotation needed."
fi

# Final count
FINAL_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" | wc -l)
log "Final backup count: $FINAL_COUNT"
log "=== docker-clean-rotation END ==="
