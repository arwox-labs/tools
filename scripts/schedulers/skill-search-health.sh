#!/usr/bin/env bash
# skill-search-health: one-shot health watchdog for skill search.
# 1) refreshes both Claude Code plugin marketplaces (catalogs),
# 2) probes the local skills.sh CLI (skills_sh),
# then atomically rewrites a 3-line state file. Failure is reflected in the
# state, never in the exit code (always 0; pm2 just re-runs on cron).
set -uo pipefail

CLAUDE=/root/.local/bin/claude
SKILLS=/root/workspaces/tools/skill-search/node_modules/.bin/skills
STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state"
STATE_FILE="$STATE_DIR/skill-search-health.state"

MARKETPLACES=(claude-plugins-official claude-community)

mkdir -p "$STATE_DIR"

# 1) Refresh both catalogs (network). Both must exit 0 => catalogs=ok.
cat_ok=1
for name in "${MARKETPLACES[@]}"; do
  timeout 120 "$CLAUDE" plugin marketplace update "$name" >/dev/null 2>&1 || cat_ok=0
done
if [ "$cat_ok" = 1 ]; then
  catalogs=ok
else
  catalogs=fail
fi

# 2) Probe skills.sh: alive only when it exits 0 and emits a skills.sh/ line.
probe_out=$(DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 timeout 20 "$SKILLS" find testing 2>/dev/null)
probe_rc=$?
clean_out=$(printf '%s\n' "$probe_out" | sed 's/\x1b\[[0-9;]*m//g')
if [ "$probe_rc" -eq 0 ] && printf '%s\n' "$clean_out" | grep -q 'skills.sh/'; then
  skills_sh=ok
else
  skills_sh=fail
fi

# 3) Atomic rewrite of the state file (tmp + mv).
tmp="${STATE_FILE}.$$"
printf 'ts=%s\ncatalogs=%s\nskills_sh=%s\n' "$(date +%s)" "$catalogs" "$skills_sh" > "$tmp"
mv -f "$tmp" "$STATE_FILE"

# 4) One summary line on stdout; exit 0 always.
printf 'skill-search-health ts=%s catalogs=%s skills_sh=%s\n' "$(date +%s)" "$catalogs" "$skills_sh"
exit 0
