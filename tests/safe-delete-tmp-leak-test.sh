#!/usr/bin/env bash
# safe-delete: не оставлять мусор в /tmp.
# Контракт: после любого выхода из bin/safe-delete в /tmp нет ни одного пути
# по маске /tmp/safe-delete.* — ни при обычном удалении, ни после TERM
# (trap снятия временных файлов на EXIT INT TERM HUP), ни после прогона
# bin/safe-delete-deps-test.
# Фикстуры живут под mktemp -d /tmp/safe-delete-tmp-leak-test.XXXXXX.
# Временные каталоги убираются через bin/safe-delete tmp; сам тестовый каталог
# удаляется напрямую, чтобы уборка не маскировала проверяемый дефект.
set -u
export GIT_CONFIG_NOSYSTEM=1
export SAFE_DELETE_GH=false
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
sd=$root/bin/safe-delete
deps_test=$root/bin/safe-delete-deps-test
d=$(mktemp -d /tmp/safe-delete-tmp-leak-test.XXXXXX)
# маркер: второй каталог того же теста — уборка не должна задеть чужие /tmp/safe-delete.*
mark=$(mktemp -d /tmp/safe-delete-tmp-leak-test.XXXXXX)
d2=$(mktemp -d /tmp/safe-delete-tmp-leak-test.XXXXXX)
start=$SECONDS
ok=0; fail=0
pass(){ echo "PASS $1: $2"; ok=$((ok+1)); }
bad(){ echo "FAIL $1: $2"; fail=$((fail+1)); }
# запуск safe-delete в изоляции: свой корень и свои источники зависимостей
sd_run(){ SAFE_DELETE_ROOTS="$d" SAFE_DELETE_DEPS_SOURCES="$d/src" SAFE_DELETE_CRONTAB_FILE=/dev/null "$sd" --bk "$d/bk" "$@"; }
# сколько путей /tmp/safe-delete.* существует прямо сейчас
leaks(){ find /tmp -maxdepth 1 -name 'safe-delete.*' | wc -l; }
leak_list(){ find /tmp -maxdepth 1 -name 'safe-delete.*' -printf '%p ' 2>/dev/null; }
mkdir -p "$d/src" "$mark/empty"
# отдельный корень для deps-test: он сам убирает за собой через safe-delete tmp
finish(){
  local rc=1
  (( fail == 0 )) && rc=0
  echo "итог: PASS $ok, FAIL $fail"
  SAFE_DELETE_ROOTS="$d:$d2:$mark" "$sd" --bk "$d/bk" tmp "$d" "$d2" >/dev/null 2>&1 || true
  rm -rf -- "$d" "$d2" "$mark" >/dev/null 2>&1 || true
  exit $rc
}
trap finish EXIT

# T1: обычное удаление — временные файлы сняты после штатного выхода
printf 'plain\n' >"$d/plain.txt"
out=$(sd_run tmp "$d/plain.txt" 2>&1); rc=$?
if [[ $rc == 0 && ! -e $d/plain.txt ]]; then
  sleep 0.2
  if [[ $(leaks) == 0 ]]; then
    pass 1 "rc=0 deleted=yes leftovers=0"
  else bad 1 "rc=$rc deleted=yes leftovers=$(leaks) paths=$(leak_list)"; fi
else bad 1 "rc=$rc exists=$([[ -e $d/plain.txt ]] && echo yes || echo no) out=$(printf %q "$out")"; fi

# T2: каталог из 300 файлов, TERM через 0.3 с — пути /tmp/safe-delete.* не остаются
mkdir -p "$d/d300"
for i in $(seq 1 300); do printf 'y\n' >"$d/d300/f$i.txt"; done
sd_run dir "$d/d300" >"$d/t2.log" 2>&1 &
pid=$!
sleep 0.3
kill -TERM "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null; rc=$?
sleep 0.2
n=$(leaks)
if [[ $n == 0 ]]; then
  pass 2 "rc=$rc term=yes leftovers=0"
else bad 2 "rc=$rc leftovers=$n paths=$(leak_list)"; fi

# T3: штатный набор проверок safe-delete — после него в /tmp нет /tmp/safe-delete.*
before=$(leaks)
timeout 120 bash "$deps_test" >"$d/t3.log" 2>&1; rc=$?
tail=$(tail -n1 "$d/t3.log")
sleep 0.2
n=$(leaks)
if [[ $n == 0 ]]; then
  pass 3 "rc=$rc deps_test_итог=$(printf %q "$tail") leftovers=0"
else bad 3 "rc=$rc before=$before leftovers=$n paths=$(leak_list)"; fi

# T4: весь набор уложился в 60 с
dur=$((SECONDS-start))
if (( dur < 60 )); then pass 4 "duration=${dur}s"; else bad 4 "duration=${dur}s > 60"; fi