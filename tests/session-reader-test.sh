#!/usr/bin/env bash
set -euo pipefail

ROOT="/root/workspaces/tools"
READER="$ROOT/bin/session-reader"
DB="/root/.local/share/opencode/opencode.db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PYTHONPYCACHEPREFIX="$TMP/pycache" python3 -m py_compile "$READER"
"$READER" sessions 3 > "$TMP/sessions.json"
python3 - "$TMP/sessions.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    sessions = json.load(stream)
assert isinstance(sessions, list) and len(sessions) == 3
assert all(isinstance(item, dict) and "id" in item for item in sessions)
PY

SESSION_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))[0]["id"])' "$TMP/sessions.json")"
"$READER" session "$SESSION_ID" > "$TMP/session.json"
python3 - "$TMP/session.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    session = json.load(stream)
assert isinstance(session, dict) and "tokens_input" in session
PY

python3 - "$DB" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
try:
    connection.execute("PRAGMA query_only=ON")
    try:
        connection.execute("INSERT INTO session (id) VALUES (?)", ("reader-write-test",))
    except sqlite3.OperationalError:
        pass
    else:
        raise AssertionError("query_only did not reject a write")
finally:
    connection.close()
PY

printf '%s\n' 'session-reader tests passed'
