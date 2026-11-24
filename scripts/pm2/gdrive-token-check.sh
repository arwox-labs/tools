#!/bin/bash
# gdrive-token-check.sh — Мониторинг Google Drive доступа
# PM2 cron: каждые 12 часов
# Проверяет все 3 уровня доступа и записывает статус
set +e

SA_KEY="/root/workspaces/secrets/services/google/service-account.json"
OAUTH_TOKEN="/root/workspaces/secrets/services/google/token.json"
STATUS_FILE="/root/workspaces/system/tools/scripts/data/gdrive-token-status.txt"
REDIS_KEY="system:error:gdrive-token"

mkdir -p /root/workspaces/system/tools/scripts/data
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# === Check 1: Public Download ===
PUBLIC_OK=false
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://www.googleapis.com/drive/v3/files/test?alt=media" 2>/dev/null)
if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    PUBLIC_OK=true
fi

# === Check 2: Service Account ===
SA_OK=false
SA_STATUS="not configured"
if [ -f "$SA_KEY" ]; then
    SA_EMAIL=$(jq -r '.client_email // empty' "$SA_KEY" 2>/dev/null)
    SA_TYPE=$(jq -r '.type // empty' "$SA_KEY" 2>/dev/null)
    if [ "$SA_TYPE" = "service_account" ] && [ -n "$SA_EMAIL" ]; then
        SA_OK=true
        SA_STATUS="configured ($SA_EMAIL)"
    else
        SA_STATUS="invalid key file"
    fi
fi

# === Check 3: OAuth Token ===
OAUTH_OK=false
OAUTH_STATUS="not configured"
if [ -f "$OAUTH_TOKEN" ]; then
    CLIENT_ID=$(jq -r '.client_id // empty' "$OAUTH_TOKEN" 2>/dev/null)
    CLIENT_SECRET=$(jq -r '.client_secret // empty' "$OAUTH_TOKEN" 2>/dev/null)
    REFRESH_TOKEN=$(jq -r '.refresh_token // empty' "$OAUTH_TOKEN" 2>/dev/null)

    if [ -n "$CLIENT_ID" ] && [ -n "$REFRESH_TOKEN" ]; then
        RESPONSE=$(curl -s --max-time 10 -X POST https://oauth2.googleapis.com/token \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=refresh_token" \
            -d "client_id=$CLIENT_ID" \
            -d "client_secret=$CLIENT_SECRET" \
            -d "refresh_token=$REFRESH_TOKEN")

        ACCESS=$(echo "$RESPONSE" | jq -r '.access_token // empty' 2>/dev/null)
        ERROR=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null)

        if [ -n "$ACCESS" ] && [ "$ACCESS" != "null" ]; then
            OAUTH_OK=true
            OAUTH_STATUS="valid"
        else
            OAUTH_STATUS="expired ($ERROR)"
        fi
    else
        OAUTH_STATUS="incomplete credentials"
    fi
fi

# === Overall status ===
if [ "$SA_OK" = true ]; then
    OVERALL="OK_SA"
    MSG="Service Account active"
    redis-cli DEL "$REDIS_KEY" >/dev/null 2>&1
elif [ "$PUBLIC_OK" = true ]; then
    OVERALL="OK_PUBLIC"
    MSG="Public access only (SA recommended)"
    redis-cli SET "$REDIS_KEY" "no_sa" EX 604800 >/dev/null 2>&1
else
    OVERALL="DEGRADED"
    MSG="No reliable access method"
    redis-cli SET "$REDIS_KEY" "degraded" EX 604800 >/dev/null 2>&1
fi

# === Write status ===
{
    echo "$TIMESTAMP $OVERALL — $MSG"
    echo "  Public API: $([ "$PUBLIC_OK" = true ] && echo "OK" || echo "FAIL")"
    echo "  Service Account: $SA_STATUS"
    echo "  OAuth: $OAUTH_STATUS"
} > "$STATUS_FILE"

echo "$TIMESTAMP $OVERALL — $MSG"
echo "  Public: $([ "$PUBLIC_OK" = true ] && echo "OK" || echo "FAIL")"
echo "  SA: $SA_STATUS"
echo "  OAuth: $OAUTH_STATUS"

if [ "$SA_OK" = false ] && [ "$OAUTH_OK" = false ]; then
    echo ""
    echo "RECOMMEND: Setup Service Account:"
    echo "  bash /root/workspaces/tools/acc1-scripts/scripts/gdrive-setup-sa.sh"
fi

exit 0
