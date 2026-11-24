#!/bin/bash
# PM2 Conductor - Rate Limit Control (loop protection)
# Note: No budget tracking - Claude works on subscription

REDIS_DB="${CONDUCTOR_REDIS_DB:-3}"
RATE_KEY_PREFIX="conductor:rate"
HOURLY_LIMIT="${CONDUCTOR_MAX_CALLS_HOUR:-10}"

# Check hourly call limit (prevents infinite fix loops)
check_rate_limit() {
  local calls=$(redis-cli -n $REDIS_DB GET "${RATE_KEY_PREFIX}:$(date +%Y-%m-%d-%H)" 2>/dev/null || echo "0")
  [ -z "$calls" ] && calls="0"

  if [ "$calls" -ge "$HOURLY_LIMIT" ]; then
    echo "⚠️ Rate limit reached: $calls >= $HOURLY_LIMIT calls/hour"
    echo "   This prevents infinite fix loops, not budget control"
    return 1
  fi

  echo "✅ Rate OK: $calls / $HOURLY_LIMIT calls this hour"
  return 0
}

# Increment call counter
increment_calls() {
  local hour=$(date +%Y-%m-%d-%H)
  redis-cli -n $REDIS_DB INCR "${RATE_KEY_PREFIX}:$hour" >/dev/null
  redis-cli -n $REDIS_DB EXPIRE "${RATE_KEY_PREFIX}:$hour" 7200 >/dev/null
}

# Get current stats (simplified)
get_rate_stats() {
  local hour=$(date +%Y-%m-%d-%H)
  local calls=$(redis-cli -n $REDIS_DB GET "${RATE_KEY_PREFIX}:$hour" 2>/dev/null || echo "0")

  cat <<EOF
{
  "hourly_calls": ${calls:-0},
  "hourly_limit": $HOURLY_LIMIT,
  "note": "Rate limit only - no budget (subscription model)"
}
EOF
}

export -f check_rate_limit increment_calls get_rate_stats
