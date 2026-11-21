#!/bin/bash
# Self-check declared_paths (D1): закомментированные строки crontab не должны
# попадать в проверку «объявленное существует». Тест offline: фикстура-croutab
# через DR_CRONTAB_CMD, без записи в /var/log.
#   bash scripts/tests/disk-rotate-declared-selfcheck.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-rotate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export DR_LOCK_FILE="$TMP/disk-rotate.lock"   # offline: не competing с живыми прогонами

FAILS=0
report() { # name status
  if [ "$2" = PASS ]; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi
}

# Фикстура: живая и закомментированная строки указывают на несуществующие пути;
# ещё одна закомментированная — на существующий (тоже не должна учитываться).
GHOST_MISSING=$TMP/no-such-dir/scripts/ghost.sh
LIVE_MISSING=$TMP/no-such-dir/scripts/live-task.sh
REAL=$TMP/scripts/real.sh
mkdir -p "$TMP/scripts" && : >"$REAL"
cat >"$TMP/crontab.txt" <<EOF
# FREEZE-20261121 * * * * * /usr/bin/bash $GHOST_MISSING >/dev/null 2>&1
# comment mentioning $REAL
* * * * * /usr/bin/bash $LIVE_MISSING
EOF
export DR_CRONTAB_CMD="cat $TMP/crontab.txt"
ECOSYSTEM=$TMP/ecosystem.config.js
: >"$ECOSYSTEM"

# --- контроль фикстуры: без фильтра закомментированных строк баг ловится ---
declared_raw=$(sed -E 's/^[[:space:]]*#//' "$TMP/crontab.txt" | grep -oE '/[^[:space:]]+' \
  | grep -E '(scripts?/|\.sh$|\.py$|\.js$)' | sed -E 's/:[0-9]+$//' | grep '^/' | sort -u)
if printf '%s\n' "$declared_raw" | grep -qF "$GHOST_MISSING"; then
  report "фикстура ловит баг: unfiltered-путь missing-комментария" PASS
else
  report "фикстура ловит баг: unfiltered-путь missing-комментария" FAIL
fi

DR_SOURCE_ONLY=1 . "$SCRIPT"

out=$(declared_paths crontab)
if ! printf '%s\n' "$out" | grep -qF "$GHOST_MISSING"; then
  report "crontab: закомментированный путь не в declared_paths" PASS
else
  report "crontab: закомментированный путь не в declared_paths (got: $(printf '%s' "$out" | tr '\n' ' '))" FAIL
fi
if printf '%s\n' "$out" | grep -qxF "$LIVE_MISSING"; then
  report "crontab: живой путь остался в declared_paths" PASS
else
  report "crontab: живой путь остался в declared_paths" FAIL
fi

# DECLARED_MISSING: только живой пропавший путь (плюс ecosystem-фикстура пустая).
ECOSYSTEM=$TMP/ecosystem.config.js
: >"$ECOSYSTEM"
check_declared >/dev/null
if [ "${DECLARED_MISSING:-x}" = 1 ]; then
  report "DECLARED_MISSING: закомментированный missing-путь не растит счётчик (=1)" PASS
else
  report "DECLARED_MISSING: закомментированный missing-путь не растит счётчик (got ${DECLARED_MISSING:-unset})" FAIL
fi

# Живая строка с несуществующим путём -> счётчик ровно 1 (только она).
out2=$(check_declared)
if [ "${DECLARED_MISSING:-x}" = 1 ] && printf '%s\n' "$out2" | grep -qF "crontab | $LIVE_MISSING"; then
  report "DECLARED_MISSING: живая missing-строка учтена (=1)" PASS
else
  report "DECLARED_MISSING: живая missing-строка учтена (got ${DECLARED_MISSING:-unset}, out: $out2)" FAIL
fi

if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAILS invariant(s) FAILED"; exit 1
