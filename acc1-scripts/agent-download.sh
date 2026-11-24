#!/usr/bin/env bash
# agent-download.sh - canonical agent download tool for b244.ru and Google Drive.
# Usage:
#   agent-download.sh [--output-dir DIR] [--output PATH] <URL_or_GDrive_ID>
# Output:
#   Prints downloaded file path(s) to stdout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GDRIVE="$SCRIPT_DIR/gdrive-download.sh"
B244="$SCRIPT_DIR/b244-fetch.sh"
LINK_RESOLVER="${AGENT_LINK_RESOLVER:-agent-link-resolve}"
LINK_INTAKE="${AGENT_LINK_INTAKE:-agent-link-intake}"
OUTPUT_DIR=""
OUTPUT_PATH=""

usage() {
    echo "Usage: $(basename "$0") [--output-dir DIR] [--output PATH] <URL_or_GDrive_ID>" >&2
    exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ $# -lt 2 ]] && usage
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output)
            [[ $# -lt 2 ]] && usage
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --help|-h)
            usage 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -eq 1 ]] || usage
INPUT="$1"

if [[ -n "$OUTPUT_PATH" && -n "$OUTPUT_DIR" ]]; then
    echo "ERROR: Use either --output or --output-dir, not both" >&2
    exit 1
fi

is_gdrive() {
    [[ "$1" =~ drive\.google\.com|docs\.google\.com|sheets\.google\.com|slides\.google\.com|googleapis\.com ]]
}

is_raw_gdrive_id() {
    [[ "$1" =~ ^[A-Za-z0-9_-]{25,80}$ ]]
}

resolve_url() {
    local url="$1"
    AGENT_DOWNLOAD_INTERNAL=1 curl -sI -o /dev/null -w '%{url_effective}' -L --max-time 10 "$url" 2>/dev/null || true
}

run_gdrive() {
    if [[ -n "$OUTPUT_PATH" ]]; then
        local tmp_dir
        tmp_dir="$(mktemp -d /tmp/agent-download-gdrive-XXXXXX)"
        mapfile -t paths < <(bash "$GDRIVE" --output-dir "$tmp_dir" "$INPUT")
        [[ "${#paths[@]}" -gt 0 ]] || { echo "ERROR: Google Drive download produced no path" >&2; exit 1; }
        mkdir -p "$(dirname "$OUTPUT_PATH")"
        cp "${paths[0]}" "$OUTPUT_PATH"
        printf '%s\n' "$OUTPUT_PATH"
    elif [[ -n "$OUTPUT_DIR" ]]; then
        bash "$GDRIVE" --output-dir "$OUTPUT_DIR" "$INPUT"
    else
        bash "$GDRIVE" "$INPUT"
    fi
}

run_b244() {
    if [[ -n "$OUTPUT_PATH" ]]; then
        bash "$B244" --output "$OUTPUT_PATH" "$INPUT"
    elif [[ -n "$OUTPUT_DIR" ]]; then
        bash "$B244" --output-dir "$OUTPUT_DIR" "$INPUT"
    else
        bash "$B244" --output-dir "${CLAUDE_DOWNLOAD_DIR:-/tmp/claude-gdrive}" "$INPUT"
    fi
}

resolver_field() {
    local json="$1"
    local field="$2"
    python3 - "$json" "$field" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(0)

value = payload.get(sys.argv[2])
if value is not None:
    print(value)
PY
}

if is_raw_gdrive_id "$INPUT" || is_gdrive "$INPUT"; then
    run_gdrive
    exit 0
fi

if [[ "$INPUT" =~ ^https?://(www\.)?b244\.ru/ ]]; then
    if command -v "$LINK_INTAKE" >/dev/null 2>&1; then
        INTAKE_JSON="$("$LINK_INTAKE" --intent download --output json "$INPUT" 2>/dev/null || true)"
        INTAKE_STATUS="$(resolver_field "$INTAKE_JSON" status)"
        INTAKE_ACTION="$(resolver_field "$INTAKE_JSON" action)"
        INTAKE_ALLOWED_URL="$(resolver_field "$INTAKE_JSON" allowed_url)"
        if [[ "$INTAKE_STATUS" == "PASS" && "$INTAKE_ACTION" == "download_allowed" && -n "$INTAKE_ALLOWED_URL" ]]; then
            INPUT="$INTAKE_ALLOWED_URL"
            if [[ "$INPUT" =~ ^b244:// || "$INPUT" =~ ^https?://io\.b244\.ru/files/ ]]; then
                run_b244
                exit 0
            elif is_gdrive "$INPUT"; then
                run_gdrive
                exit 0
            fi
        elif [[ "$INTAKE_STATUS" == "BLOCKED" ]]; then
            echo "BLOCKED: agent-link-intake refused protected download for $INPUT" >&2
            exit 2
        fi
    fi

    if command -v "$LINK_RESOLVER" >/dev/null 2>&1; then
        RESOLVER_JSON="$("$LINK_RESOLVER" --output json "$INPUT" 2>/dev/null || true)"
        RESOLVER_MODE="$(resolver_field "$RESOLVER_JSON" mode)"
        if [[ "$RESOLVER_MODE" == "local_storage" ]]; then
            LOCAL_FETCH_URI="$(resolver_field "$RESOLVER_JSON" local_fetch_uri)"
            if [[ -n "$LOCAL_FETCH_URI" ]]; then
                INPUT="$LOCAL_FETCH_URI"
                run_b244
                exit 0
            fi
        elif [[ "$RESOLVER_MODE" == "external_passthrough" ]]; then
            TARGET_URL="$(resolver_field "$RESOLVER_JSON" target_url)"
            if [[ -n "$TARGET_URL" ]] && is_gdrive "$TARGET_URL"; then
                INPUT="$TARGET_URL"
                run_gdrive
                exit 0
            fi
        fi
    fi

    RESOLVED="$(resolve_url "$INPUT")"
    if [[ -n "$RESOLVED" ]] && is_gdrive "$RESOLVED"; then
        INPUT="$RESOLVED"
        run_gdrive
    else
        run_b244
    fi
    exit 0
fi

if [[ "$INPUT" =~ ^https?://io\.b244\.ru/files/ || "$INPUT" =~ ^b244:// ]]; then
    run_b244
    exit 0
fi

echo "ERROR: Unsupported download source. Use b244.ru/io.b244.ru or Google Drive links/IDs." >&2
exit 1
