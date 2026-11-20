#!/bin/bash
# Self-check codex-worktrees.sh (spec:090 C3 / CR-01). Запуск вручную:
#   bash scripts/tests/codex-worktrees-selfcheck.sh
# Фикстура в mktemp -d: bare-репо origin, worktree-клоны и связанные worktree. Ничего не удаляет.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-zones/codex-worktrees.sh"
TMP="$(mktemp -d)"
SLEEP_PID=
trap 'rm -rf -- "$TMP"; [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; true' EXIT

WT="$TMP/wt"
mkdir -p "$WT"

ORIGIN="$TMP/origin.git"
git init -q --bare -b main "$ORIGIN"
SEED="$TMP/seed"
mkdir -p "$SEED"
git -C "$SEED" init -q
git -C "$SEED" config user.email selfcheck@test
git -C "$SEED" config user.name selfcheck
printf 'base\n' >"$SEED/base"
git -C "$SEED" add base
git -C "$SEED" commit -qm base
git -C "$SEED" remote add origin "$ORIGIN"
git -C "$SEED" push -q -u origin HEAD:main

# (a) candidate: HEAD в origin/main, чисто
git clone -q "$ORIGIN" "$WT/dcfg-aaa1"
# (b) kept-not-merged: лишний коммит поверх main
git clone -q "$ORIGIN" "$WT/dcfg-bbb1"
git -C "$WT/dcfg-bbb1" config user.email selfcheck@test
git -C "$WT/dcfg-bbb1" config user.name selfcheck
git -C "$WT/dcfg-bbb1" -c core.hooksPath=/dev/null commit -q --allow-empty -m extra
# (c) kept-dirty: неотслеживаемый файл
git clone -q "$ORIGIN" "$WT/dcfg-ccc1"
printf 'dirty\n' >"$WT/dcfg-ccc1/untracked.txt"
# (d) kept-busy: процесс sleep с cwd внутри worktree
git clone -q "$ORIGIN" "$WT/dcfg-ddd1"
(
  cd "$WT/dcfg-ddd1" || exit 1
  exec sleep 30
) &
SLEEP_PID=$!

# Владельческие имена <атом>-<описание>: связанный worktree с веткой codex/<имя каталога>.
# (e) candidate по суффиксу; (k) кандидат от дочернего атома с точкой
git -C "$SEED" worktree add -q -b codex/dcfg-eee1-rotation "$WT/dcfg-eee1-rotation"
git -C "$SEED" worktree add -q -b codex/dcfg-kkk1.1-kid "$WT/dcfg-kkk1.1-kid"
# (f) kept-wt-mismatch: суффикс, но обычный клон (ветка main, не связан)
git clone -q "$ORIGIN" "$WT/dcfg-fff1-deep"
# (g) kept-wt-mismatch: ветка не совпадает с именем каталога
git -C "$SEED" worktree add -q -b codex/dcfg-other "$WT/dcfg-ggg1-mis"
# (h) kept-wt-mismatch: detached HEAD без ветки
git -C "$SEED" worktree add -q --detach "$WT/dcfg-hhh1-det"
# (i) kept-atom-open: атом открыт; (j) kept-atom-open: атом не найден
git -C "$SEED" worktree add -q -b codex/dcfg-iii1-openfn "$WT/dcfg-iii1-openfn"
git -C "$SEED" worktree add -q -b codex/dcfg-jjj1-gonefn "$WT/dcfg-jjj1-gonefn"

# Фейковый bd: id из аргумента; статус из fakebd.db, по умолчанию closed, missing -> rc 1
FAKEBD="$TMP/fakebd"
printf 'dcfg-iii1 open\ndcfg-jjj1 missing\n' >"$TMP/fakebd.db"
cat >"$FAKEBD" <<'EOF'
#!/bin/bash
st=$(awk -v id="$2" '$1 == id {print $2}' "$(dirname "$0")/fakebd.db")
case "$st" in
  missing) printf 'Issue %s not found\n' "$2" >&2; exit 1 ;;
  open) printf '[{"id":"%s","status":"open"}]\n' "$2" ;;
  *) printf '[{"id":"%s","status":"closed"}]\n' "$2" ;;
esac
EOF
chmod +x "$FAKEBD"

ZONE_MODE=dry-run DZ_CODEX_WT="$WT" DZ_ZONES_TSV="$TMP/zones.tsv" \
  DZ_BD="$FAKEBD" bash "$SCRIPT"
rc=$?

PASS=0
FAIL=0
TOTAL=0
check_state() { # name expected
  local got
  TOTAL=$((TOTAL + 1))
  got=$(awk -F'\t' -v n="$1" 'substr($3, length($3) - length(n) + 1) == n {print $9}' "$TMP/zones.tsv")
  if [ "$got" = "$2" ]; then
    PASS=$((PASS + 1))
    echo "PASS $1 -> $2"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $1 -> got '$got', want '$2'"
  fi
}

check_state dcfg-aaa1 candidate
check_state dcfg-bbb1 kept-not-merged
check_state dcfg-ccc1 kept-dirty
check_state dcfg-ddd1 kept-busy
check_state dcfg-eee1-rotation candidate
check_state dcfg-fff1-deep kept-wt-mismatch
check_state dcfg-ggg1-mis kept-wt-mismatch
check_state dcfg-hhh1-det kept-wt-mismatch
check_state dcfg-iii1-openfn kept-atom-open
check_state dcfg-jjj1-gonefn kept-atom-open
check_state dcfg-kkk1.1-kid candidate

# Сопутствующие инварианты: rc=0, строка run-done, каталоги целы.
check_ok() { # rc label
  TOTAL=$((TOTAL + 1))
  if [ "$1" -eq 0 ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $2"
  fi
}

check_ok "$rc" "script rc=$rc"
grep -q $'\trun-done$' "$TMP/zones.tsv"
check_ok $? "нет строки run-done"
for d in dcfg-aaa1 dcfg-bbb1 dcfg-ccc1 dcfg-ddd1 dcfg-eee1-rotation dcfg-kkk1.1-kid \
         dcfg-fff1-deep dcfg-ggg1-mis dcfg-hhh1-det dcfg-iii1-openfn dcfg-jjj1-gonefn; do
  [ -d "$WT/$d" ]
  check_ok $? "удалён каталог $d"
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS $PASS/$TOTAL"
  exit 0
fi
echo "FAIL $PASS/$TOTAL"
exit 1
