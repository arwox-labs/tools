#!/bin/bash
# topic-extractor.sh — Extract keywords from JSONL session files
# Usage: topic-extractor.sh <jsonl_path> [max_keywords=10]
# Output: space-separated keywords to stdout
# Timeout: 10 seconds max

set +e

JSONL_PATH="$1"
MAX_KEYWORDS="${2:-20}"
STOPWORDS_FILE="/root/workspaces/tools/acc1-scripts/data/stopwords.txt"
TIMEOUT=10

# Validate input
if [ -z "$JSONL_PATH" ] || [ ! -f "$JSONL_PATH" ]; then
    exit 0
fi

# Build stopwords hash file for grep -f (much faster than long regex)
STOPWORDS_FLAT="/tmp/.topic-extractor-stopwords.txt"
if [ -f "$STOPWORDS_FILE" ]; then
    grep -v '^#' "$STOPWORDS_FILE" | grep -v '^$' | tr ' ' '\n' | grep -v '^$' | sort -u > "$STOPWORDS_FLAT"
else
    echo -e "the\nand\nfor\nthat\nthis\nwith\nfrom" > "$STOPWORDS_FLAT"
fi

# OOM protection: for large files, sample head + tail (user text often at start,
# tool_results dominate the end)
FILE_SIZE=$(stat -c%s "$JSONL_PATH" 2>/dev/null || echo "0")
SAMPLE_FILE="/tmp/.topic-extractor-sample-$$"

if [ "$FILE_SIZE" -gt 5242880 ]; then
    # Take first 300 lines (user text) + last 200 lines (recent activity)
    { head -300 "$JSONL_PATH"; tail -200 "$JSONL_PATH"; } > "$SAMPLE_FILE"
else
    cp "$JSONL_PATH" "$SAMPLE_FILE"
fi

# Extract user messages + first 10 assistant messages, clean, tokenize with Perl (UTF-8 safe)
timeout "$TIMEOUT" bash -c '
    {
        # User messages (primary source)
        jq -r "select(.type == \"user\") | .message.content | if type == \"string\" then . elif type == \"array\" then [.[] | select(type == \"object\" and .type == \"text\") | .text] | join(\" \") else empty end" "'"$SAMPLE_FILE"'" 2>/dev/null
        # First 10 assistant messages (project names, key decisions)
        head -200 "'"$SAMPLE_FILE"'" 2>/dev/null | jq -r "select(.type == \"assistant\") | .message.content | if type == \"string\" then . elif type == \"array\" then [.[] | select(type == \"object\" and .type == \"text\") | .text] | join(\" \") else empty end" 2>/dev/null | head -10
    } | \
    sed "s/<[^>]*>//g" | \
    perl -C -ne '"'"'$_ = lc; while (/(\b[\p{L}\d]{3,}\b)/g) { print "$1\n" }'"'"' | \
    grep -vxFf "'"$STOPWORDS_FLAT"'" | \
    grep -vE "^[0-9]+$" | \
    grep -vE "^[0-9a-f]{8,}$" | \
    grep -vE "^[0-9]+[mMkKgGbBtT][0-9]*$" | \
    grep -vE "^(drwx|rwx|lrwx|crw)" | \
    grep -vE "^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)$" | \
    grep -vE "^bot[0-9]+$" | \
    grep -vE "^[a-z0-9]{20,}$" | \
    sort | uniq -c | sort -rn | \
    head -'"$MAX_KEYWORDS"' | \
    awk "{print \$2}"
' 2>/dev/null | tr '\n' ' ' | sed 's/ $//'

rm -f "$SAMPLE_FILE"
exit 0
