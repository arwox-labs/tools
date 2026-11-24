#!/bin/bash
set +e
INTERVAL=86400
LOG="/root/workspaces/system/tools/scripts/logs/search-quality-report.log"

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Search Quality Report" >> "$LOG"
    TOTAL_HITS=0
    TOTAL_MISSES=0
    DEGRADED_DAYS=0

    for i in $(seq 0 6); do
        DAY=$(date -d "$i days ago" '+%Y-%m-%d' 2>/dev/null)
        HITS=$(redis-cli GET "search:hit:$DAY" 2>/dev/null || echo "0")
        MISSES=$(redis-cli GET "search:miss:$DAY" 2>/dev/null || echo "0")
        TOTAL=$(redis-cli GET "search:total:$DAY" 2>/dev/null || echo "0")
        [ "$HITS" = "" ] || [ "$HITS" = "(nil)" ] && HITS=0
        [ "$MISSES" = "" ] || [ "$MISSES" = "(nil)" ] && MISSES=0
        [ "$TOTAL" = "" ] || [ "$TOTAL" = "(nil)" ] && TOTAL=0

        if [ "$TOTAL" -gt 0 ] 2>/dev/null; then
            HIT_RATE=$((HITS * 100 / TOTAL))
            echo "  $DAY: $HITS/$TOTAL = ${HIT_RATE}%" >> "$LOG"
            TOTAL_HITS=$((TOTAL_HITS + HITS))
            TOTAL_MISSES=$((TOTAL_MISSES + MISSES))
            [ "$HIT_RATE" -lt 60 ] && DEGRADED_DAYS=$((DEGRADED_DAYS + 1))
        fi
    done

    GRAND_TOTAL=$((TOTAL_HITS + TOTAL_MISSES))
    if [ "$GRAND_TOTAL" -gt 0 ]; then
        OVERALL=$((TOTAL_HITS * 100 / GRAND_TOTAL))
        if [ "$DEGRADED_DAYS" -ge 3 ]; then
            redis-cli SET "search:alert" "Quality ${OVERALL}%, ${DEGRADED_DAYS}d degraded" EX 259200 2>/dev/null
        else
            redis-cli DEL "search:alert" 2>/dev/null
        fi
        echo "  Overall: ${OVERALL}% | Degraded days: $DEGRADED_DAYS" >> "$LOG"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done" >> "$LOG"
    sleep $INTERVAL
done
