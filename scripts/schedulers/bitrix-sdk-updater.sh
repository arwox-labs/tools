#!/bin/bash
# =============================================================================
# bitrix-sdk-updater.sh — Check stable SDK versions for Bitrix24
# PM2 job: runs every 5 days (loop-based, no cron)
# Checks: JS (@bitrix24/b24jssdk) + PHP (mesilov/bitrix24-php-sdk)
# Output: /root/workspaces/system/tools/scripts/data/bitrix-sdk-status.json
# Log: /root/workspaces/system/tools/scripts/logs/sdk-updates.log
# =============================================================================

set +e

DATA_DIR="/root/workspaces/system/tools/scripts/data"
LOG="/root/workspaces/system/tools/scripts/logs/sdk-updates.log"
STATUS_FILE="$DATA_DIR/bitrix-sdk-status.json"
SDK_JS_DIR="/root/workspaces/projects/bitrix/sdk-js"
SLEEP_INTERVAL=$((5 * 24 * 3600))  # 5 days in seconds

mkdir -p "$DATA_DIR" "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

CYCLE=0

while true; do
CYCLE=$((CYCLE + 1))
log "=== SDK Update Check Started (cycle #$CYCLE) ==="

# === JS SDK: @bitrix24/b24jssdk ===
JS_CURRENT="null"
JS_STABLE="null"
JS_UPDATE="false"
JS_AUDIT="unknown"

# Get current version from project
if [ -f "$SDK_JS_DIR/package.json" ]; then
    JS_CURRENT=$(python3 -c "
import json
with open('$SDK_JS_DIR/package.json') as f:
    d = json.load(f)
deps = d.get('dependencies', {})
v = deps.get('@bitrix24/b24jssdk', 'null')
print(v.lstrip('^~>='))
" 2>/dev/null)
fi

# Get stable version from npm (not latest — check dist-tags)
JS_NPM_INFO=$(npm view @bitrix24/b24jssdk dist-tags --json 2>/dev/null)
if [ -n "$JS_NPM_INFO" ]; then
    # Prefer 'stable' tag, fallback to 'latest'
    JS_STABLE=$(echo "$JS_NPM_INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('stable', d.get('latest', 'null')))
except:
    print('null')
" 2>/dev/null)
fi

# Compare versions
if [ "$JS_CURRENT" != "null" ] && [ "$JS_STABLE" != "null" ] && [ "$JS_CURRENT" != "$JS_STABLE" ]; then
    JS_UPDATE="true"
    log "JS SDK: $JS_CURRENT -> $JS_STABLE (update available)"
else
    log "JS SDK: $JS_CURRENT (current)"
fi

# Security audit
if [ -d "$SDK_JS_DIR/node_modules" ]; then
    AUDIT_RESULT=$(cd "$SDK_JS_DIR" && npm audit --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    meta = d.get('metadata', {}).get('vulnerabilities', {})
    crit = meta.get('critical', 0)
    high = meta.get('high', 0)
    if crit > 0:
        print('CRITICAL')
    elif high > 0:
        print('HIGH')
    else:
        print('clean')
except:
    print('unknown')
" 2>/dev/null)
    JS_AUDIT="$AUDIT_RESULT"
    log "JS SDK audit: $JS_AUDIT"
fi

# === PHP SDK ===
PHP_CURRENT="null"
PHP_STABLE="null"
PHP_RECOMMENDED="mesilov/bitrix24-php-sdk"
PHP_AUDIT="n/a"

# Check packagist for stable version
PHP_PACKAGIST=$(curl -s "https://repo.packagist.org/p2/mesilov/bitrix24-php-sdk.json" 2>/dev/null)
if [ -n "$PHP_PACKAGIST" ]; then
    PHP_STABLE=$(echo "$PHP_PACKAGIST" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    packages = d.get('packages', {}).get('mesilov/bitrix24-php-sdk', [])
    # Find latest stable (no -dev, -alpha, -beta, -RC)
    for pkg in packages:
        v = pkg.get('version', '')
        if v and not any(tag in v for tag in ['-dev', '-alpha', '-beta', '-RC', 'dev-']):
            print(v.lstrip('v'))
            break
    else:
        print('null')
except:
    print('null')
" 2>/dev/null)
    log "PHP SDK stable: $PHP_STABLE ($PHP_RECOMMENDED)"
fi

# Check if any project uses PHP SDK
for cjson in /root/workspaces/projects/bitrix/sdk-php/composer.json /root/workspaces/projects/bitrix/*/composer.json; do
    if [ -f "$cjson" ] && grep -q "bitrix24" "$cjson" 2>/dev/null; then
        PHP_CURRENT=$(python3 -c "
import json
with open('$cjson') as f:
    d = json.load(f)
req = d.get('require', {})
for k, v in req.items():
    if 'bitrix24' in k.lower() or 'bitrix' in k.lower():
        print(v.lstrip('^~>='))
        break
else:
    print('null')
" 2>/dev/null)
        break
    fi
done

# === Write status JSON ===
python3 -c "
import json
from datetime import datetime

status = {
    'last_check': datetime.now().isoformat(timespec='seconds'),
    'js_sdk': {
        'package': '@bitrix24/b24jssdk',
        'current': '$JS_CURRENT',
        'stable': '$JS_STABLE',
        'update_available': True if '$JS_UPDATE' == 'true' else False,
        'audit': '$JS_AUDIT'
    },
    'php_sdk': {
        'package': '$PHP_RECOMMENDED',
        'current': '$PHP_CURRENT' if '$PHP_CURRENT' != 'null' else None,
        'stable': '$PHP_STABLE',
        'recommended': '$PHP_RECOMMENDED',
        'audit': '$PHP_AUDIT'
    }
}

with open('$STATUS_FILE', 'w') as f:
    json.dump(status, f, indent=2, ensure_ascii=False)
print('Status written to $STATUS_FILE')
"

log "=== SDK Update Check Completed (cycle #$CYCLE) ==="
log "Status file: $STATUS_FILE"
log "Sleeping $((SLEEP_INTERVAL / 86400)) days until next check..."

sleep "$SLEEP_INTERVAL"
done
