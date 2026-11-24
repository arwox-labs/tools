#!/usr/bin/env bash
# Транскрибация Groq Whisper (transcription-dev/transcribe.py) с ключом
# из admin/.env рабочей панели transcription-panel-dev без раскрытия
# значения агенту.
# Usage: bash tools/secure/run_transcribe.sh <файл> [--lang ru] [--model …] [--no-cleanup]
set -euo pipefail

ENV_FILE="/root/workspaces/projects/transcription-dev/admin/.env"
SCRIPT=/root/workspaces/projects/transcription-dev/transcribe.py

[[ -f "$ENV_FILE" ]] || { echo "Ошибка: $ENV_FILE не найден" >&2; exit 1; }
[[ -f "$SCRIPT" ]] || { echo "Ошибка: $SCRIPT не найден" >&2; exit 1; }

GROQ_API_KEY="$(grep -m1 '^GROQ_API_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d "\"'")"; export GROQ_API_KEY
[[ -n "$GROQ_API_KEY" ]] || { echo "Ошибка: GROQ_API_KEY нет в $ENV_FILE" >&2; exit 1; }

exec python3 "$SCRIPT" "$@"
