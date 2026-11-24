#!/bin/bash
set +e

TOKEN_FILE="/root/workspaces/secrets/services/google/token.json"
LOG_FILE="/root/workspaces/system/tools/scripts/data/google-token-refresh.log"
BACKUP_DIR="/root/workspaces/system/tools/scripts/data/google-token-backups"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

CLIENT_ID=$(jq -r '.client_id // empty' "$TOKEN_FILE" 2>/dev/null)
CLIENT_SECRET=$(jq -r '.client_secret // empty' "$TOKEN_FILE" 2>/dev/null)
REFRESH_TOKEN=$(jq -r '.refresh_token // empty' "$TOKEN_FILE" 2>/dev/null)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$REFRESH_TOKEN" ]; then
  log "ERROR: Missing required fields in token.json"
  redis-cli SET "alert:google:token_refresh_failed" "missing_fields $(date)" EX 604800 2>/dev/null
  exit 1
fi

cp "$TOKEN_FILE" "$BACKUP_DIR/token_$(date '+%Y%m%d_%H%M%S').json"
ls -t "$BACKUP_DIR"/token_*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null

RESPONSE=$(curl -sf --max-time 10 -X POST "https://oauth2.googleapis.com/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "refresh_token=${REFRESH_TOKEN}" \
  -d "grant_type=refresh_token" 2>/dev/null)

NEW_ACCESS=$(echo "$RESPONSE" | jq -r '.access_token // empty' 2>/dev/null)
NEW_REFRESH=$(echo "$RESPONSE" | jq -r '.refresh_token // empty' 2>/dev/null)
ERROR=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null)

if [ -z "$NEW_ACCESS" ] || [ -n "$ERROR" ]; then
  log "ERROR: Token refresh failed. Error: ${ERROR:-unknown}. Response: $RESPONSE"
  redis-cli SET "alert:google:token_refresh_failed" "${ERROR:-unknown} $(date)" EX 604800 2>/dev/null
  exit 1
fi

EXPIRY=$(date -u -d '+3600 seconds' '+%Y-%m-%dT%H:%M:%SZ')

if [ -n "$NEW_REFRESH" ]; then
  jq --arg at "$NEW_ACCESS" --arg rt "$NEW_REFRESH" --arg exp "$EXPIRY" \
    '.access_token = $at | .refresh_token = $rt | .token_expiry = $exp' \
    "$TOKEN_FILE" > "${TOKEN_FILE}.tmp" && mv "${TOKEN_FILE}.tmp" "$TOKEN_FILE"
  log "OK: Token refreshed (refresh_token rotated). Expiry: $EXPIRY"
else
  jq --arg at "$NEW_ACCESS" --arg exp "$EXPIRY" \
    '.access_token = $at | .token_expiry = $exp' \
    "$TOKEN_FILE" > "${TOKEN_FILE}.tmp" && mv "${TOKEN_FILE}.tmp" "$TOKEN_FILE"
  log "OK: Token refreshed (access_token only). Expiry: $EXPIRY"
fi

redis-cli DEL "alert:google:token_refresh_failed" 2>/dev/null
log "SUCCESS: Google token refresh completed"
exit 0
