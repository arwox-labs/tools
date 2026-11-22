#!/usr/bin/env bash
# b244-fetch.sh — Local resolver for b244.ru/io.b244.ru internal MinIO storage
# Usage:
#   b244-fetch.sh b244://filename
#   b244-fetch.sh https://io.b244.ru/files/filename
#   b244-fetch.sh https://b244.ru/shortcode
# Output: summary header + file content (HTML stripped to text)

set -euo pipefail

MINIO_CONTAINER="minio"
MINIO_BUCKET="files"
PUBLIC_URL_BASE="https://io.b244.ru/files"
SCRIPT_NAME="$(basename "$0")"

OUTPUT_DIR=""
OUTPUT_PATH=""

usage() {
    echo "Usage: $SCRIPT_NAME [--output-dir DIR] [--output PATH] <b244://filename | https://io.b244.ru/... | https://b244.ru/...>"
    exit 1
}

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        --) shift; break ;;
        -*) echo "ERROR: Unknown option: $1" >&2; usage ;;
        *) break ;;
    esac
done

[[ $# -eq 0 ]] && usage
INPUT="$1"
FILENAME=""
FETCH_VIA="mc"  # mc (local MinIO) or curl (remote)

# --- Resolve input to filename ---
if [[ "$INPUT" == b244://* ]]; then
    # b244://somefile.html -> files/somefile.html in MinIO
    FILENAME="${INPUT#b244://}"
    FETCH_VIA="mc"

elif [[ "$INPUT" == https://io.b244.ru/files/* ]]; then
    # Direct io.b244.ru URL
    FILENAME="${INPUT#https://io.b244.ru/files/}"
    FETCH_VIA="mc"

elif [[ "$INPUT" == https://b244.ru/* ]] || [[ "$INPUT" == http://b244.ru/* ]]; then
    # Short URL — follow redirect to get the real filename
    REDIRECT_URL=$(curl -sL --max-time 10 -o /dev/null -w "%{url_effective}" "$INPUT" 2>/dev/null || true)
    if [[ "$REDIRECT_URL" == https://io.b244.ru/files/* ]]; then
        FILENAME="${REDIRECT_URL#https://io.b244.ru/files/}"
        FETCH_VIA="mc"
    else
        # Fallback: download directly via curl
        FETCH_VIA="curl"
        FETCH_URL="$INPUT"
    fi

else
    # Any other URL — try curl directly
    FETCH_VIA="curl"
    FETCH_URL="$INPUT"
fi

# --- Download content ---
TMPFILE=$(mktemp /tmp/b244fetch_XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

if [[ "$FETCH_VIA" == "mc" ]]; then
    # Read inside the MinIO container over localhost: no docker IP, no host mc
    # alias. Credentials come from the container env, never from the host.
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: docker CLI not available; cannot reach MinIO container '${MINIO_CONTAINER}'" >&2
        exit 1
    fi
    MC_ERR=$(docker exec -e B244_NAME="$FILENAME" -e B244_BUCKET="$MINIO_BUCKET" "$MINIO_CONTAINER" \
        sh -c 'set -e
            : "${MINIO_ROOT_USER:?MINIO_ROOT_USER missing in container}" "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD missing in container}"
            command -v mc >/dev/null 2>&1 || { echo "mc binary not found inside container" >&2; exit 3; }
            mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 \
                || { echo "mc alias set local http://localhost:9000 failed" >&2; exit 4; }
            exec mc cat "local/${B244_BUCKET}/${B244_NAME}"' 2>&1 >"$TMPFILE") || {
        echo "ERROR: File not found in MinIO: ${MINIO_BUCKET}/${FILENAME} (link may have expired or the object was removed)" >&2
        if [[ -n "$MC_ERR" ]]; then
            echo "  detail: $(printf '%s' "$MC_ERR" | tr '\n' ' ' | cut -c1-300)" >&2
        fi
        echo "Available files matching pattern:" >&2
        docker exec "$MINIO_CONTAINER" sh -c '
            mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 || exit 0
            mc ls "local/files/" 2>/dev/null' | grep -F "$(basename "$FILENAME" .html)" >&2 || true
        exit 1
    }
else
    if ! curl -sL --max-time 30 -o "$TMPFILE" "${FETCH_URL}"; then
        echo "ERROR: Failed to download: ${FETCH_URL}" >&2
        exit 1
    fi
fi

FILE_SIZE=$(wc -c < "$TMPFILE")
FILE_SIZE_HUMAN=$(du -sh "$TMPFILE" 2>/dev/null | cut -f1)

# --- Detect file type ---
MIME_TYPE=$(file --mime-type -b "$TMPFILE" 2>/dev/null || echo "unknown")
EXT="${FILENAME##*.}"
if [[ "$EXT" == "$FILENAME" ]]; then
    EXT="unknown"
fi

# --- Strip HTML if needed ---
RAW_TEXT_FILE=$(mktemp /tmp/b244text_XXXXXX)
trap 'rm -f "$TMPFILE" "$RAW_TEXT_FILE"' EXIT

if [[ "$MIME_TYPE" == "text/html" ]] || [[ "$EXT" == "html" ]] || [[ "$EXT" == "htm" ]]; then
    FILE_TYPE="HTML"
    # Strip HTML tags using sed (no python required)
    sed 's/<style[^>]*>.*<\/style>//gI; s/<script[^>]*>.*<\/script>//gI' "$TMPFILE" | \
        sed 's/<[^>]*>//g' | \
        sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&nbsp;/ /g; s/&#[0-9]*;//g; s/&[a-z]*;//g' | \
        sed '/^[[:space:]]*$/d' > "$RAW_TEXT_FILE.full"
    head -500 "$RAW_TEXT_FILE.full" > "$RAW_TEXT_FILE"
    rm -f "$RAW_TEXT_FILE.full"
elif [[ "$MIME_TYPE" == "application/json" ]] || [[ "$EXT" == "json" ]]; then
    FILE_TYPE="JSON"
    cp "$TMPFILE" "$RAW_TEXT_FILE"
else
    FILE_TYPE="TEXT (${EXT:-plain})"
    cp "$TMPFILE" "$RAW_TEXT_FILE"
fi

LINE_COUNT=$(wc -l < "$RAW_TEXT_FILE")

# --- Generate summary ---
# Try python3 for richer summary, fallback to bash
SUMMARY_LINES=""
if command -v python3 >/dev/null 2>&1; then
    SUMMARY_LINES=$(python3 - "$RAW_TEXT_FILE" "$FILE_TYPE" "$FILE_SIZE_HUMAN" "$LINE_COUNT" << 'PYEOF'
import sys, re

text_file = sys.argv[1]
file_type = sys.argv[2]
size = sys.argv[3]
lines = sys.argv[4]

with open(text_file, 'r', errors='replace') as f:
    content = f.read(8000)

words = content.split()
word_count = len(words)

# Extract first meaningful sentence or heading
first_meaningful = ""
for line in content.splitlines():
    line = line.strip()
    if len(line) > 20 and not line.startswith('#'):
        first_meaningful = line[:120]
        break

# Detect key topics (simple keyword frequency, top 5 words >5 chars)
from collections import Counter
stopwords = {'which','their','there','where','about','would','could','should','these','those','other','after','before','while','since','until','every','under','above','below','between','through','during','without','within','against','toward','around','whether','though','although','however','therefore','because','because','being','having','doing'}
keywords = [w.lower() for w in words if len(w) > 5 and w.isalpha() and w.lower() not in stopwords]
top_words = [w for w, _ in Counter(keywords).most_common(5)]

print(f"  Type    : {file_type}")
print(f"  Size    : {size} ({lines} lines, ~{word_count} words)")
print(f"  Preview : {first_meaningful[:100]}")
print(f"  Topics  : {', '.join(top_words) if top_words else 'n/a'}")
PYEOF
    )
else
    FIRST_LINE=$(grep -m1 '.\{20,\}' "$RAW_TEXT_FILE" 2>/dev/null | head -c 100 || true)
    SUMMARY_LINES="  Type    : ${FILE_TYPE}
  Size    : ${FILE_SIZE_HUMAN} (${LINE_COUNT} lines)
  Preview : ${FIRST_LINE}"
fi

# --- Output ---
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  b244-fetch summary"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "  Source  : ${INPUT}"
if [[ -n "${FILENAME:-}" ]]; then
    echo "  File    : ${FILENAME}"
    echo "  URL     : ${PUBLIC_URL_BASE}/${FILENAME}"
fi
echo "${SUMMARY_LINES}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
if [[ -n "$OUTPUT_PATH" ]]; then
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    cp "$TMPFILE" "$OUTPUT_PATH"
    echo "$OUTPUT_PATH"
    exit 0
elif [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    DEST="$OUTPUT_DIR/${FILENAME:-$(basename "$INPUT")}"
    cp "$TMPFILE" "$DEST"
    echo "$DEST"
    exit 0
fi

echo "─── CONTENT ────────────────────────────────────────────────────"
echo ""
cat "$RAW_TEXT_FILE"
