#!/bin/bash
# gdrive-download.sh — Download files from Google Drive
# Обёртка над gdrive-download.py — трёхуровневая стратегия:
#   1. Публичный доступ (без авторизации)
#   2. OAuth2 refresh
#   3. Service Account (JWT fallback)
#
# Usage: bash gdrive-download.sh "https://drive.google.com/file/d/FILE_ID/view"
# Output: prints local path of downloaded file
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/gdrive-download.py"

if [ -z "$1" ]; then
    echo "Error: No URL provided" >&2
    echo "Usage: bash gdrive-download.sh 'https://drive.google.com/file/d/FILE_ID/view'" >&2
    exit 1
fi

if [ ! -f "$PY_SCRIPT" ]; then
    echo "Error: gdrive-download.py not found at $PY_SCRIPT" >&2
    exit 1
fi

# Запускаем Python-скрипт с трёхуровневой стратегией
python3 "$PY_SCRIPT" "$@"
EXIT_CODE=$?

exit $EXIT_CODE
