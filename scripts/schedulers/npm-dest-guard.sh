#!/usr/bin/env bash
# npm-dest-guard: pm2 cron one-shot; alerts on NEW bare-IP destinations in Nginx Proxy Manager.
# Always exits 0: a crash-looping watchdog would hide the next alert.
set -uo pipefail

LINT="${NPM_DEST_LINT:-/root/workspaces/tools/bin/npm-dest-lint}"
STATE="${NPM_DEST_GUARD_STATE:-/root/workspaces/tools/scripts/schedulers/state/npm-dest.json}"
NOTIFY="${NPM_DEST_GUARD_NOTIFY:-1}"

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$*"; }

mkdir -p "$(dirname "$STATE")" 2>/dev/null || { log "state dir create failed: $STATE"; exit 0; }

out=$("$LINT" 2>&1); rc=$?
current=$(printf '%s\n' "$out" | grep -v '^RESULT: ' | sed '/^[[:space:]]*$/d' | LC_ALL=C sort)
count=$(printf '%s\n' "$current" | sed '/^[[:space:]]*$/d' | wc -l)

saved=""
if [ -f "$STATE" ]; then
  saved=$(jq -r '(.violations // [])[]' "$STATE" 2>/dev/null | LC_ALL=C sort)
fi

new=""
if [ "$count" -gt 0 ]; then
  new=$(LC_ALL=C comm -13 <(printf '%s\n' "$saved" | sed '/^[[:space:]]*$/d') \
                          <(printf '%s\n' "$current") 2>/dev/null) || new="$current"
fi
new_count=$(printf '%s\n' "$new" | sed '/^[[:space:]]*$/d' | wc -l)

sent=0
if [ "$new_count" -gt 0 ] && [ "$NOTIFY" != 0 ]; then
  if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
    log "telegram skipped: TG_BOT_TOKEN/TG_CHAT_ID missing"
  else
    msg=$(printf '⚠️ NPM: прокси-хост назначен на голый IP\n\n%s\n\nПравило: имя контейнера, host.docker.internal или *-upstream. Проверка: tools/bin/npm-dest-lint' "$new")
    answer=$({ printf 'url = "https://api.telegram.org/bot%s/sendMessage"\ndata = "chat_id=%s"\n' "$TG_BOT_TOKEN" "$TG_CHAT_ID"
      printf 'data-urlencode = "text=%s"\n' "$msg"; } | curl -s --max-time 10 -K - 2>&1)
    if printf '%s' "$answer" | jq -e '.ok == true' >/dev/null 2>&1; then
      sent=1
    else
      log "send failed: $(printf '%s' "$answer" | head -c 200)"
    fi
  fi
fi

printf '%s\n' "$current" | jq -R -s --argjson rc "$rc" --argjson sent "$sent" \
  '{violations: (split("\n") | map(select(length > 0))), lint_rc: $rc, notified: ($sent == 1)}' \
  > "$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE" || log "state write failed: $STATE"

log "lint_rc=$rc violations=$count new=$new_count sent=$sent"
exit 0