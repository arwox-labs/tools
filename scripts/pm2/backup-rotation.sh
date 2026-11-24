#!/bin/bash
# backup-rotation.sh — Rotates backup files in profile backups/ directory
# Keeps files for 5 days, deletes older ones
# Also moves any stray .backup/.bak files found in profile into backups/
# Runs via PM2 every 6 hours
set +e

BACKUP_DIR="/root/workspaces/system/tools/scripts/backups"
PROFILE_DIR="/root/workspaces/system/tools/scripts"
RETENTION_DAYS=5
LOG_FILE="/tmp/backup-rotation.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') — Backup rotation started" >> "$LOG_FILE"

# Step 1: Move any stray backup files into backups/
MOVED=0
while IFS= read -r f; do
    rel=$(echo "$f" | sed "s|${PROFILE_DIR}/||" | sed "s|/|__|g")
    mv "$f" "${BACKUP_DIR}/${rel}" 2>/dev/null && MOVED=$((MOVED + 1))
done < <(find "$PROFILE_DIR" \( -name "*.backup" -o -name "*.bak" -o -name "*.backup.*" \) -not -path "*/backups/*" 2>/dev/null)

if [ $MOVED -gt 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') — Moved $MOVED stray backup files into backups/" >> "$LOG_FILE"
fi

# Step 2: Delete files older than RETENTION_DAYS
DELETED=$(find "$BACKUP_DIR" -maxdepth 1 -type f -mtime +${RETENTION_DAYS} -delete -print 2>/dev/null | wc -l)

if [ "$DELETED" -gt 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') — Deleted $DELETED files older than ${RETENTION_DAYS} days" >> "$LOG_FILE"
fi

# Step 3: Report current state
TOTAL=$(find "$BACKUP_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

echo "$(date '+%Y-%m-%d %H:%M:%S') — State: ${TOTAL} files, ${SIZE} total. Moved: ${MOVED}, Deleted: ${DELETED}" >> "$LOG_FILE"

# Keep log file small (last 100 lines)
if [ -f "$LOG_FILE" ]; then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

exit 0
