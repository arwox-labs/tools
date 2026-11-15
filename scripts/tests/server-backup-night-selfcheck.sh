#!/usr/bin/env bash
# Selfcheck R6 (атом dcfg-t56za.11): ночной бэкап, nice/ionice, mirror-check, окно догона.
# Запуск: timeout 120 bash scripts/tests/server-backup-night-selfcheck.sh
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$ROOT/scripts/pm2/server-backup.sh"
CATCHUP="$ROOT/scripts/pm2/backup-catchup.sh"

for f in "$SB" "$CATCHUP"; do
  [ -f "$f" ] || { echo "FATAL: нет $f"; exit 1; }
done

if [ "${1:-}" = --policy-only ]; then
  exec python3 - "$SB" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

source = Path(sys.argv[1]).read_text()
retention = next(block for block in source.split("\n\n") if "run_step forget " in block and "forget_rc=$?" in block)
guard = "exec 9>" + source.split("exec 9>", 1)[1].split("# Снимок cron", 1)[0]
completion = "date +%s >\"$LAST_OK\"" + source.split('date +%s >"$LAST_OK"', 1)[1].split('if [ "$(date +%u)"', 1)[0]


class Policy(unittest.TestCase):
    def test_retention(self):
        for hour in range(24):
            with self.subTest(hour=hour):
                script = 'set -u; NICE_PREFIX=(); RESTIC=restic; run_hour="$1"; run_step() { printf "%s\\0" "$@"; return "$RC"; }; fail() { exit "$2"; };\n' + retention
                result = subprocess.run(["bash", "-c", script, "policy", f"{hour:02}"], env={**os.environ, "RC": "0"}, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = ["forget", "restic", "forget", "--tag", "server", "--group-by", "host,tags", "--keep-hourly", "48", "--keep-daily", "14"]
                if hour == 3:
                    expected.append("--prune")
                expected += ["--retry-lock", "30m"]
                self.assertEqual(result.stdout.decode().rstrip("\0").split("\0"), expected)
        for rc in (1, 3):
            result = subprocess.run(["bash", "-c", script, "policy", "03"], env={**os.environ, "RC": str(rc)}, capture_output=True)
            self.assertEqual(result.returncode, 0 if rc == 3 else rc)

    def run_slot(self, root, epoch, success=True):
        script = 'set -u; log() { printf "%s\\n" "$*" >&2; }; fail() { exit "$2"; }; date() { printf "%s\\n" "$EPOCH"; };\n' + guard
        script += 'printf "cloud\\n" >>"$STAGE/calls"\n'
        script += completion if success else "exit 1\n"
        return subprocess.run(["bash", "-c", script], env={**os.environ, "STAGE": str(root), "LAST_OK": str(root / "last-ok"), "EPOCH": str(epoch)}, capture_output=True)

    def test_successful_slot(self):
        with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
            root = Path(directory)
            for slot in range(8):
                epoch = 1794690000 + slot * 10800
                self.assertEqual(self.run_slot(root, epoch).returncode, 0)
                self.assertEqual(self.run_slot(root, epoch + 60).returncode, 0)
            self.assertEqual((root / "calls").read_text().splitlines(), ["cloud"] * 8)

    def test_incomplete_slot(self):
        with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
            root = Path(directory)
            self.assertEqual(self.run_slot(root, 1794690000, success=False).returncode, 1)
            self.assertEqual(self.run_slot(root, 1794690060).returncode, 75)
            self.assertEqual(self.run_slot(root, 1794700800).returncode, 0)
            self.assertEqual((root / "calls").read_text().splitlines(), ["cloud"] * 2)

    def test_concurrent_slot(self):
        import fcntl
        with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as directory:
            root = Path(directory)
            with (root / ".server-backup.lock").open("w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertEqual(self.run_slot(root, 1794690000).returncode, 0)
            self.assertFalse((root / "calls").exists())


unittest.main(argv=["policy"], verbosity=2)
PY
fi

TMP="$(mktemp -d /tmp/dcfg-sb-selfcheck.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/mirror" "$TMP/work" "$TMP/logs"
# 3 локальных bare-репозитория — для локальной сверки mirror-check.
for n in 1 2 3; do mkdir -p "$TMP/mirror/repo$n.git"; done

: >"$TMP/s3.env"
: >"$TMP/pw.env"
: >"$TMP/notify-empty.env"
printf 'TG_BOT_TOKEN=stub\nTG_CHAT_ID=1\n' >"$TMP/notify-tok.env"

# Ссылка на снимок S3 (для проверки алерта).
export STUB_CURL="$TMP/curl.log"

write_stub() { # name body
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

# Заглушка restic: пишет argv бэкапа + собственный nice, отдаёт ls из файла.
write_stub restic '
mode="${1:-}"
if [ "$mode" = backup ]; then
  {
    printf "nice=%s\n" "$(ps -o ni= $$ | tr -d " ")"
    printf "argv:"
    for a in "$@"; do printf " <%s>" "$a"; done
    printf "\n"
  } >>"$STUB_ARGV"
  if [ "${STUB_IMAGE_MODE:-0}" = 1 ]; then
    printf '{"message_type":"summary","snapshot_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n'
  fi
  exit 0
fi
if [ "$mode" = snapshots ] && [ "${STUB_IMAGE_MODE:-0}" = 1 ]; then
  printf '[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]\n'
  exit 0
fi
if [ "$mode" = ls ]; then for a in "$@"; do [ "$a" = --recursive ] && { cat "$STUB_LS_FILE" 2>/dev/null; break; }; done; exit 0; fi
if [ "$mode" = restore ]; then
  target="" includes=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target) target="$2"; shift 2;;
      --include) includes+=("$2"); shift 2;;
      *) shift;;
    esac
  done
  case "$target" in /tmp/*) ;; *) exit 1;; esac
  [ "${#includes[@]}" -gt 0 ] || exit 1
  for include in "${includes[@]}"; do
    case "$include" in
      /root/backups/docker/20*|/root/backups/docker/current|/root/CLAUDE.md|/root/workspaces/tools/ecosystem.config.js|/root/workspaces/git-dirs/agent-contour.git/HEAD) ;;
      *) exit 1;;
    esac
    mkdir -p "$target$(dirname "$include")" || exit 1
    if [ -d "$include" ]; then
      cp -al -- "$include" "$target$include" || exit 1
    elif [ -f "$include" ]; then
      cp -- "$include" "$target$include" || exit 1
      if [ "${STUB_RESTORE_MISMATCH:-0}" = 1 ] && [ "$include" = /root/workspaces/git-dirs/agent-contour.git/HEAD ]; then
        printf "corrupted\n" >"$target$include" || exit 1
      fi
    else
      exit 1
    fi
  done
  exit 0
fi
if [ "$mode" = stats ]; then printf "Total Size: 100 MiB\n"; exit 0; fi
if [ "$mode" = check ]; then exit "${STUB_CHECK_RC:-0}"; fi
exit 0
'

# Воскресная ветка check требует date +%u=7, +%-d=8; форсируем только по флагу,
# прочие вызовы date (лог, +%s) делегируем системной date.
write_stub date '
if [ "${STUB_FORCE_SUNDAY:-0}" = 1 ]; then
  case "${1:-}" in
    +%u) echo 7; exit 0;;
    +%-d) echo 8; exit 0;;
  esac
fi
# STUB_FORCE_WEEKDAY=1 даёт +%u=3 (результат не зависит от реального дня).
if [ "${STUB_FORCE_WEEKDAY:-0}" = 1 ] && [ "${1:-}" = +%u ]; then echo 3; exit 0; fi
exec /bin/date "$@"
'

# Сетевые/тяжёлые/служебные заглушки — сервер не нагружаем, наружу не ходим.
write_stub curl '
{ printf "curl:"; for a in "$@"; do printf " <%s>" "$a"; done; printf "\n"; } >>"${STUB_CURL:-/dev/null}"
exit 0
'
write_stub pm2 '
echo "pm2:$*" >>"${STUB_PM2:-/dev/null}"
[ "${1:-}" = jlist ] && echo "[]"
exit 0
'
write_stub jq '
[ -z "${STUB_JQ_VALUE:-}" ] || printf "%s\\n" "$STUB_JQ_VALUE"
exit 0
'
write_stub systemctl 'case "$*" in *is-active*) exit 1;; esac; exit 0'
write_stub crontab 'exit 0'
for c in dpkg apt-mark pip3 pipx uv npm snap redis-cli sqlite3 lsb_release; do
  write_stub "$c" 'exit 0'
done
# docker inspect: инвентаризация UpperDir контейнеров (server-backup.sh) получает реальный overlay2/*/diff.
write_stub docker '
if [ "${STUB_IMAGES:-0}" = 1 ] && [ "${1:-}" = image ]; then
  case "${2:-}" in
    ls) printf "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\nsha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\n";;
    inspect) printf "1\\n";;
  esac
fi
if [ "${1:-}" = inspect ]; then
  for d in /var/lib/docker/overlay2/*/diff; do
    if [ -d "$d" ] && [ ! -L "$d" ]; then printf "%s\n" "$d"; exit 0; fi
  done
fi
exit 0
'
write_stub df '
if [ "${STUB_IMAGE_DF:-0}" = 1 ] && [ "${*: -1}" = /var/lib/docker ]; then
  count=$(cat "$STUB_DF_COUNTER" 2>/dev/null || echo 0)
  count=$((count + 1))
  printf "%s\\n" "$count" >"$STUB_DF_COUNTER"
  printf "Avail\\n"
  [ "$count" -eq 1 ] && printf "10000000000\\n" || printf "1\\n"
  exit 0
fi
exec /bin/df "$@"
'
write_stub su 'exit 1'
write_stub docker-backup 'exit 0'
write_stub sha256sum '
for file in "$@"; do
  [ "$file" = -- ] && continue
  printf "%064d  %s\n" 0 "$file"
done
'

run_backup() { # ls_file notify_env argc_file [server-backup args...] -> rc
  local ls_file="$1" notify="$2" argc="$3" rc
  shift 3
  : >"$argc"
  STUB_LS_FILE="$ls_file" \
  STUB_ARGV="$argc" \
  RESTIC="$TMP/bin/restic" \
  S3_ENV="$TMP/s3.env" \
  PW_ENV="$TMP/pw.env" \
  NOTIFY_ENV="$notify" \
  LOG="$TMP/logs/server-backup.log" \
  STAGE="$TMP/work/stage" \
  LAST_OK="$TMP/last-ok" \
  ALERT_PENDING="$TMP/alert-pending" \
  BK_MIRROR_DIR="$TMP/mirror" \
  BK_DOCKER_SCRIPT="$TMP/bin/docker-backup" \
  STUB_IMAGES="${STUB_IMAGES:-1}" \
  STUB_IMAGE_MODE="${STUB_IMAGE_MODE:-1}" \
  STUB_JQ_VALUE="${STUB_JQ_VALUE:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" \
  PATH="$TMP/bin:$PATH" \
  timeout 120 bash "$SB" "$@"
  rc=$?
  return "$rc"
}

PASS=0
TOTAL=23
SB_LOG="$TMP/logs/server-backup.log"

# --- (f): образы идут по одному; второй пропущен из-за резерва на диске.
IMG_ARGV="$TMP/argv-images.txt"
IMG_DF_COUNTER="$TMP/df-images-count"
: >"$IMG_ARGV"
: >"$IMG_DF_COUNTER"
if STUB_IMAGE_MODE=1 STUB_JQ_VALUE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  STUB_IMAGE_DF=1 STUB_DF_COUNTER="$IMG_DF_COUNTER" STUB_IMAGES=1 \
  run_backup "$TMP/ls-ok.txt" "$TMP/notify-empty.env" "$IMG_ARGV" --images-only; then
  echo "[f] ожидали images-only rc!=0 при low-space"; exit 1
fi
if grep -q 'docker-images skip sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb low-space' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[f] нет low-space для второго образа"; exit 1
fi
if grep -q 'docker-images ok=1 failed=1 count=2' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[f] нет итогового счётчика docker-images"; exit 1
fi
if [ "$(grep -c -- '--stdin-from-command' "$IMG_ARGV")" -eq 1 ]; then PASS=$((PASS+1)); else
  echo "[f] restic backup должен быть вызван ровно один раз"; exit 1
fi
if grep -q '<--compression> <auto>' "$IMG_ARGV"; then PASS=$((PASS+1)); else
  echo "[f] restic должен сжимать поток сам"; exit 1
fi
if grep -Eq '<--stdin-filename> <docker-image-[0-9a-f]{64}\.tar>' "$IMG_ARGV"; then PASS=$((PASS+1)); else
  echo "[f] ожидается имя .tar без gzip"; exit 1
fi
if grep -q '<docker> <image> <save> <sha256:aaaaaaaa' "$IMG_ARGV" && ! grep -q 'gzip' "$IMG_ARGV"; then PASS=$((PASS+1)); else
  echo "[f] docker image save должен идти напрямую"; exit 1
fi

# Host integration uses published backup archives and requires an explicit opt-in.
if [ "${STUB_HOST_INTEGRATION:-0}" != 1 ] || [ ! -w /root/backups/docker ] || [ -e /root/.codex/DELETE-APPROVED.json ]; then
  echo "PASS $PASS/6 (stub-only; host Docker integration skipped)"
  exit 0
fi

# --- (g)-(i): воскресное восстановление трёх файлов.
# RUN_HOUR=03 и форсированный день не зависят от реальных часа и дня.
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\nrepos/repo3.git/HEAD\n' >"$TMP/ls-drill.txt"

# (g): воскресенье 03, три файла совпадают -> строка успеха считает три файла.
: >"$SB_LOG"
export RUN_HOUR=03 STUB_FORCE_SUNDAY=1
run_backup "$TMP/ls-drill.txt" "$TMP/notify-empty.env" "$TMP/argv-g.txt"
unset RUN_HOUR STUB_FORCE_SUNDAY
if grep -q 'restore-drill ok (3 files)' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[g] нет 'restore-drill ok (3 files)' в логе"; grep 'restore' "$SB_LOG"; tail -n 3 "$SB_LOG"; exit 1
fi

# (h): воскресенье 03, HEAD git-каталога в восстановленной копии отличается от живого ->
# в логе строка FAIL с именем файла и нет ok, в ALERT_PENDING restore rc=1 (fail restore 1).
: >"$SB_LOG"
: >"$TMP/alert-pending"
export RUN_HOUR=03 STUB_FORCE_SUNDAY=1 STUB_RESTORE_MISMATCH=1
if run_backup "$TMP/ls-drill.txt" "$TMP/notify-empty.env" "$TMP/argv-h.txt"; then
  echo "[h] ожидали сбой restore, а бэкап завершился успешно"; exit 1
fi
unset RUN_HOUR STUB_FORCE_SUNDAY STUB_RESTORE_MISMATCH
if grep -q 'restore-drill FAIL.*HEAD' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[h] нет 'restore-drill FAIL' с именем HEAD git-каталога в логе"; grep 'restore' "$SB_LOG"; tail -n 3 "$SB_LOG"; exit 1
fi
if ! grep -q 'restore-drill ok' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[h] при расхождении HEAD в логе есть 'restore-drill ok'"; exit 1
fi
if grep -q 'server-backup: restore rc=1' "$TMP/alert-pending"; then PASS=$((PASS+1)); else
  echo "[h] нет 'restore rc=1' в ALERT_PENDING"; exit 1
fi

# (i): будний день (форсируем +%u=3), 03 час -> воскресное восстановление не запускается.
# SUMMARY с check_rc=0 доказывает, что прогон прошёл место воскресной ветки и час был 03.
: >"$SB_LOG"
export RUN_HOUR=03 STUB_FORCE_WEEKDAY=1
run_backup "$TMP/ls-drill.txt" "$TMP/notify-empty.env" "$TMP/argv-i.txt"
unset RUN_HOUR STUB_FORCE_WEEKDAY
if grep -q 'SUMMARY .*check_rc=0' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[i] прогон не дошёл до SUMMARY с check_rc=0"; tail -n 5 "$SB_LOG"; exit 1
fi
if ! grep -q 'restore-drill' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[i] в будний день в логе есть restore-drill"; exit 1
fi

# --- (a)+(b): штатный ночной бэкап, mirror-check сходится (3==3).
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\nrepos/repo3.git/HEAD\n' >"$TMP/ls-ok.txt"
ARGV_A="$TMP/argv-a.txt"
: >"$SB_LOG"
if ! STUB_IMAGES=1 STUB_IMAGE_MODE=1 STUB_JQ_VALUE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa run_backup "$TMP/ls-ok.txt" "$TMP/notify-empty.env" "$ARGV_A"; then
  if ! grep -q 'docker-recovery TOTAL .*missing=0 mismatch=0' "$SB_LOG" \
    || ! grep -q 'docker-retention refused: exact owner-controlled' "$SB_LOG"; then
    echo "[a] server-backup rc!=0 до ожидаемого отказа локальной очистки (лог: $SB_LOG)"; exit 1
  fi
fi

if grep -q -- '--limit-upload> <5120>' "$ARGV_A"; then PASS=$((PASS+1)); else
  echo "[a] backup не получил --limit-upload"; exit 1
fi
if grep -q -- '--read-concurrency> <1>' "$ARGV_A"; then PASS=$((PASS+1)); else
  echo "[a] backup не получил --read-concurrency 1"; exit 1
fi
nice_a=$(sed -n 's/^nice=\([0-9]*\)$/\1/p' "$ARGV_A" | head -1)
if [ -n "$nice_a" ] && [ "$nice_a" -ge 19 ]; then PASS=$((PASS+1)); else
  echo "[b] nice=$nice_a < 19"; exit 1
fi
if grep -q 'mirror-check s3=3 local=3' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[a] нет 'mirror-check s3=3 local=3' в логе"; exit 1
fi

# --- (c): догон вне окна (BK_HOUR=14) не запускает server-backup.
old=$(( $(date +%s) - 30 * 3600 ))
printf '%s\n' "$old" >"$TMP/catch-last-ok"
: >"$TMP/pm2.log"
env BK_HOUR=14 LAST_OK="$TMP/catch-last-ok" ALERT_PENDING="$TMP/catch-alert" \
  NOTIFY_ENV="$TMP/notify-empty.env" LOG="$TMP/logs/catchup.log" \
  PM2="$TMP/bin/pm2" STUB_PM2="$TMP/pm2.log" PATH="$TMP/bin:$PATH" bash "$CATCHUP"
if grep -q 'outside-night-window hour=14' "$TMP/logs/catchup.log"; then PASS=$((PASS+1)); else
  echo "[c] нет 'outside-night-window hour=14' в логе догона"; exit 1
fi
if [ ! -s "$TMP/pm2.log" ]; then PASS=$((PASS+1)); else
  echo "[c] pm2 запущен вне ночного окна (BK_HOUR=14)"; exit 1
fi

# --- (c): догон в окне (BK_HOUR=02) запускает server-backup.
: >"$TMP/pm2.log"
env BK_HOUR=02 LAST_OK="$TMP/catch-last-ok" ALERT_PENDING="$TMP/catch-alert" \
  NOTIFY_ENV="$TMP/notify-empty.env" LOG="$TMP/logs/catchup2.log" \
  PM2="$TMP/bin/pm2" STUB_PM2="$TMP/pm2.log" PATH="$TMP/bin:$PATH" bash "$CATCHUP"
if grep -q 'pm2:restart server-backup' "$TMP/pm2.log"; then PASS=$((PASS+1)); else
  echo "[c] pm2 restart server-backup не вызван в окне (BK_HOUR=02)"; exit 1
fi
if ! grep -q 'outside-night-window' "$TMP/logs/catchup2.log"; then PASS=$((PASS+1)); else
  echo "[c] BK_HOUR=02 ошибочно классифицирован как вне окна"; exit 1
fi

# --- (d): mirror-check расходится (s3=2, local=3) -> строка и алерт.
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\n' >"$TMP/ls-2.txt"
ARGV_D="$TMP/argv-d.txt"
: >"$TMP/curl.log"
if run_backup "$TMP/ls-2.txt" "$TMP/notify-tok.env" "$ARGV_D"; then
  echo "[d] ожидали сбой mirror-check, а бэкап завершился успешно"; exit 1
fi
if grep -q 'mirror-check s3=2 local=3' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[d] нет 'mirror-check s3=2 local=3' в логе"; exit 1
fi
if grep -q 'mirror-check' "$TMP/curl.log"; then PASS=$((PASS+1)); else
  echo "[d] нет алерта mirror-check"; exit 1
fi

# --- (e): воскресная ветка check -> rc=1 -> тревога в ALERT_PENDING (пустой токен).
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\nrepos/repo3.git/HEAD\n' >"$TMP/ls-e.txt"
ARGV_E="$TMP/argv-e.txt"
: >"$TMP/alert-pending"
export RUN_HOUR=03 STUB_FORCE_SUNDAY=1 STUB_CHECK_RC=1
if run_backup "$TMP/ls-e.txt" "$TMP/notify-empty.env" "$ARGV_E"; then
  echo "[e] ожидали сбой check rc=1, а бэкап завершился успешно"; exit 1
fi
unset RUN_HOUR STUB_FORCE_SUNDAY STUB_CHECK_RC
if grep -q 'check rc=1' "$TMP/alert-pending"; then PASS=$((PASS+1)); else
  echo "[e] нет 'check rc=1' в ALERT_PENDING"; exit 1
fi

echo "PASS $PASS/$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
