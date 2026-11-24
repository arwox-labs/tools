#!/bin/bash
# conductor-dedup.sh — Error deduplication for PM2 conductor
# Sourced by pm2-conductor.sh. Uses Redis DB 3.

REDIS_DB=3

get_error_hash() {
    local app_name="$1" error_text="$2"
    echo "$error_text" | head -c 200 | md5sum | cut -c1-16
}

check_error_changed() {
    local app_name="$1" error_text="$2"
    local new_hash=$(get_error_hash "$app_name" "$error_text")
    local stored_hash=$(redis-cli -n $REDIS_DB GET "conductor:error-hash:${app_name}" 2>/dev/null)

    if [[ "$stored_hash" == "$new_hash" ]]; then
        local consecutive=$(redis-cli -n $REDIS_DB INCR "conductor:same-error-count:${app_name}" 2>/dev/null)
        redis-cli -n $REDIS_DB EXPIRE "conductor:same-error-count:${app_name}" 86400 >/dev/null 2>&1
        if [[ "${consecutive:-0}" -gt 3 ]]; then
            echo "SKIP"
            return
        fi
        echo "CHANGED"
    else
        redis-cli -n $REDIS_DB SET "conductor:error-hash:${app_name}" "$new_hash" EX 86400 >/dev/null 2>&1
        redis-cli -n $REDIS_DB DEL "conductor:same-error-count:${app_name}" >/dev/null 2>&1
        echo "CHANGED"
    fi
}

is_permanently_broken() {
    local app_name="$1"
    redis-cli -n $REDIS_DB EXISTS "conductor:permanent-broken:${app_name}" 2>/dev/null | grep -q "1"
}

mark_permanently_broken() {
    local app_name="$1"
    redis-cli -n $REDIS_DB SET "conductor:permanent-broken:${app_name}" "1" EX 604800 >/dev/null 2>&1
}
