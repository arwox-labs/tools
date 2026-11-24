#!/bin/bash
# Ежедневная чистка диска. Владелец: Александр. Обновлено 22.09.2026 (spec:054).
#
# Уборка ограничена заменимыми package-manager caches и vendor log cleanup.
# DENY_LIST приоритетнее любых правил. Проекты, браузеры, Docker и Snap revisions
# не входят в автоматическую уборку.
#
# Классы уборки (по занятости диска):
#   cache  — при soft (>=80) и выше
#
# Лог: /var/log/disk-rotate.log
# Ledger: /var/log/disk-rotate-ledger.tsv
set -u
DR_LOG=${DR_LOG:-/var/log/disk-rotate.log}
DR_LEDGER=${DR_LEDGER:-${LEDGER:-/var/log/disk-rotate-ledger.tsv}}
DR_STATE_FILE=${DR_STATE_FILE:-/var/lib/disk-rotate/fixed.tsv}
DR_LOGROTATE_STATE=${DR_LOGROTATE_STATE:-/var/lib/disk-rotate/logrotate.state}
DR_ALERT_STATE_FILE=${DR_ALERT_STATE_FILE:-/var/log/disk-rotate-alert-state.tsv}
DR_REALERT_SEC=${DR_REALERT_SEC:-86400}
DR_LOCK_FILE=${DR_LOCK_FILE:-/var/run/disk-rotate.lock}
DR_LAST_OK=${DR_LAST_OK:-/root/workspaces/system/tools/scripts/data/server-backup.last-ok}
DR_JOURNAL=${DR_JOURNAL:-/var/log/disk-rotate-deletions.tsv}
DR_USAGE_PCT=${DR_USAGE_PCT:-}
DR_NOTIFY_CMD=${DR_NOTIFY_CMD:-}
DR_TEST_ONLY=${DR_TEST_ONLY:-}
# DR_USED_KB_BEFORE / DR_USED_KB_AFTER: тест-подмены занятого места (КБ), как DR_USAGE_PCT
DR_TEST_IRREPLACEABLE_DIR=${DR_TEST_IRREPLACEABLE_DIR:-}
DR_TEST_REPLACEABLE_DIR=${DR_TEST_REPLACEABLE_DIR:-}
DR_JOURNAL_COPY=${DR_JOURNAL_COPY:-/root/workspaces/system/tools/scripts/data/disk-rotate-deletions.tsv}
# /tmp: верхний уровень чистит cleanup_tmp (spec dcfg-oglfz); возраст и лимит за прогон.
DR_TMP_ROOT=${DR_TMP_ROOT:-/tmp}
DR_TMP_AGE_MIN=${DR_TMP_AGE_MIN:-1440}
DR_TMP_MAX=${DR_TMP_MAX:-500}
# Тест подменяет корень Codex; явно заданный путь отличаем от значения по умолчанию,
# чтобы тестовый режим без DR_CODEX_HOME не трогал боевой /root/.codex.
CODEX_HOME_EXPLICIT=${DR_CODEX_HOME:+1}
DR_CODEX_HOME=${DR_CODEX_HOME:-/root/.codex}
DR_CODEX_OFFLOAD_DAYS=${DR_CODEX_OFFLOAD_DAYS:-14}
RUNNER_EXPLICIT=${DR_RUNNER_ROOTS:+1}
DR_RUNNER_ROOTS=${DR_RUNNER_ROOTS:-/opt/actions-runner /root/actions-runner-2}
NOTIFY_ENV=${NOTIFY_ENV:-/root/workspaces/secrets/services/pm2-notify.env}
ECOSYSTEM="${0%/*}/../ecosystem.config.js"
RUN_ID=$(date +%Y%m%d-%H%M%S)
GATE_MODE=${GATE_MODE:-shadow}
if [ "$GATE_MODE" = enforce ]; then
  JOURNAL_MODE=enforce
else
  JOURNAL_MODE=shadow
fi
RESTIC=${RESTIC:-/root/workspaces/tools/bin/restic}
TOOLS=${TOOLS:-/root/workspaces/tools}

SOFT_PCT=${SOFT_PCT:-80}
HARD_PCT=${HARD_PCT:-90}
EXHAUSTED_PCT=88

# Коды возврата (spec:054)
RC_ALERT_FAILED=1
RC_USAGE=2
RC_EXHAUSTED=3   # классы исчерпаны, занятость после уборки выше 88%
RC_LOCKED=4
RC_GATE_CLOSED=5 # предусловие гейта не выполнено: last-ok стар, репозиторий недоступен

# Пять каталогов для top5 и алертов (spec:054).
TOP5_DIRS=(/root/workspaces /var/lib/docker /root/backups /root/.local /tmp)
TOP5_NAMES=(workspaces docker backups local tmp)

# Запретный список дополняет whitelist заменимых кэшей.
DENY_LIST=(
  '/root/backups'
  '/root/backups/**'
  '/root/workspaces/secrets'
  '/root/workspaces/secrets/**'
  '/root/workspaces/projects'
  '/root/workspaces/projects/**'
  '/root/.claude'
  '/root/.claude/**'
  '/root/workspaces/projects/.claude'
  '/root/workspaces/projects/.claude/**'
  '/root/workspaces/system/archives'
  '/root/workspaces/system/archives/**'
  '/root/.codex'
  '/root/.codex/**'
  '**/hh-scoring*/**'
  '/root/.local/share/uv/**'
  '/home/gitmirror/**'
  '/var/lib/docker'
  '/var/lib/docker/**'
)
PROJECTS_ALLOW=(
  '/root/workspaces/projects/.agent-work/*'
  '/root/workspaces/projects/.worktrees/codex/*'
  '/root/workspaces/projects/.worktrees/claude/*'
)
# Узкие базы Codex, которые чистит cleanup_codex; под ними DENY_LIST не действует,
# остальной /root/.codex/** остаётся под запретом.
CODEX_ALLOW=(
  "$DR_CODEX_HOME/plugins/data/auto-review-just-every/turns"
  "$DR_CODEX_HOME/packages/standalone/releases"
  "$DR_CODEX_HOME/sessions"
  "$DR_CODEX_HOME/archived_sessions"
  "$DR_CODEX_HOME/.tmp"
  "$DR_CODEX_HOME/tmp"
)
# Класс backups (spec:054 CR FR-027/029, владелец 10.10): N|маска; N новейших остаются локально,
# остальные — только через гейт restic. Новый вид бэкапа = одна строка.
BACKUP_RULES=(
  '0|/root/backups/docker/20*_*'
  '0|/root/backups/hh-scoring-snapshots/*.tar.gz'
  '1|/root/workspaces/projects/rss-tg-ins/data/backups/rss-tg-ins-*.tar.gz'
  '0|/root/workspaces/projects/clients/stroyremont/*backup*.sql'
  '0|/root/workspaces/projects/clients/stroyremont/backups/*.sql'
  '0|/root/workspaces/system/infra/minio-b244/minio_backup_*.tar.gz'
  '0|/root/workspaces/system/archives/*'
)
NEVER_LIST=(
  '*hh-scoring*' '*/secrets/*' '*/.claude/*' '*/system/archives/*'
  '*/client-materials/*' '*.db' '*-wal'
)

backup_rule_match() { # path -> 0, если путь — элемент маски правила или файл внутри такого элемента
  local p=$1 rule mask
  for rule in "${BACKUP_RULES[@]}"; do
    mask=${rule#*|}
    [[ "$p" == $mask || "$p" == $mask/* ]] && return 0
  done
  return 1
}

denied() { # path -> 0 если путь в запретном списке
  local p=$1 pat b
  # правила backups сильнее NEVER_LIST и DENY_LIST, но действуют только на свои маски
  backup_rule_match "$p" && return 1
  for pat in "${NEVER_LIST[@]}"; do [[ "$p" == $pat ]] && return 0; done
  for pat in "${PROJECTS_ALLOW[@]}"; do [[ "$p" == $pat ]] && return 1; done
  # узкие базы CODEX_ALLOW не считаются запрещёнными (см. cleanup_codex)
  for b in "${CODEX_ALLOW[@]}"; do
    [[ "$p" == "$b" || "$p" == "$b"/* ]] && return 1
  done
  for pat in "${DENY_LIST[@]}"; do
    [[ "$p" == $pat ]] && return 0
  done
  return 1
}

denied_top() { # dir -> 0 если сам каталог напрямую входит в запретный список
  local p=$1 pat base
  for pat in "${DENY_LIST[@]}"; do
    base="${pat%/\*\*}"
    [ "$p" = "$base" ] && return 0
  done
  return 1
}

CODEX_CLEAN_ONLY=0
_args=()
for _a in "$@"; do
  if [ "$_a" = --codex-clean ]; then CODEX_CLEAN_ONLY=1; else _args+=("$_a"); fi
done
set -- "${_args[@]+"${_args[@]}"}"
MODE=run
DRY_RUN_ONLY_GATEROSS=0
GATE_RC=0
CLEANUP_FAILED=0
case "${1:-}" in
  '')               MODE=run ;;
  --dry-run)        MODE=dry-run ;;
  --report)         MODE=report ;;
  --check-declared) MODE=check ;;
  --restore-drill)  MODE=drill ;;
  --help)
    cat <<'EOF'
Usage: disk-rotate.sh [--codex-clean] [--dry-run|--report|--check-declared|--restore-drill|--help]
  (нет аргументов)  обычный прогон из cron: уборка по классам + алерт при необходимости
  --dry-run         ничего не удаляет; печатает перечень кандидатов и прогноз
  --codex-clean     только класс codex-clean (с --dry-run: вердикты без удаления)
  --report          только измерение и строка в ledger; без уборки и алерта
  --check-declared  сверяет пути скриптов из crontab и ecosystem.config.js
  --restore-drill   репетиция восстановления: сверяет последний снимок predelete с живыми файлами
  --help            этот перечень
EOF
    exit 0
    ;;
  *)
    echo "unknown flag: $1" >&2
    exit $RC_USAGE
    ;;
esac

# Взаимное исключение прогонов: неблокирующий flock во всех режимах, кроме help.
exec 9>"$DR_LOCK_FILE" || exit $RC_USAGE
if ! flock -n 9; then
  echo "LOCKED другой прогон идёт" >>"$DR_LOG"
  exit $RC_LOCKED
fi

echo "=== $(date '+%F %T') ${MODE^^} START ===" >>"$DR_LOG"
df -h / | tail -1 >>"$DR_LOG"

now=$(date +%s)
ts=$(date '+%Y-%m-%dT%H:%M:%S')
TOTAL_KB=0
ALERT_SENT=0
ALERT_FAIL=0
ALERT_RESULT=none
FIXED_COUNT=0
FIXED_MB=0
DEFERRED_COUNT=0
WT_CANDIDATES=()
PROJECTS_NOTICES=()

use_pct() {
  if [ -n "$DR_USAGE_PCT" ]; then
    echo "$DR_USAGE_PCT"
  else
    df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
  fi
}
used_kb() { df -P / | awk 'NR==2 {print $3}'; }

# --- счётчик «объявленное существует» (spec:054 п.4) ---
declared_paths() { # источник: crontab | ecosystem
  local src=$1
  if [ "$src" = crontab ]; then
    ${DR_CRONTAB_CMD:-crontab -l} 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -oE '/[^[:space:]]+' \
      | grep -E '(scripts?/|\.sh$|\.py$|\.js$)' | sed -E 's/:[0-9]+$//' | grep '^/' | sort -u
  else
    grep -oE "script: *'[^']+'" "$ECOSYSTEM" 2>/dev/null | sed -E "s/script: *'([^']+)'/\1/" | grep '^/' | sort -u
  fi
}

check_declared() { # -> stdout: строки «источник | путь»; global DECLARED_MISSING
  local src p missing=0
  for src in crontab ecosystem; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ ! -e "$p" ]; then
        printf '%s | %s\n' "$src" "$p"
        missing=$((missing + 1))
      fi
    done <<<"$(declared_paths "$src")"
  done
  DECLARED_MISSING=$missing
}

mechanism_status() { # удаляющий скрипт по имени файла -> статус из встроенного списка | UNDECLARED
  local p=$1 b
  b=$(basename "$p")
  case "$b" in
    disk-rotate.sh)                          printf 'stage\n' ;;
    docker-backup.sh|backup-rotation.sh|redis-backup-daemon.sh) printf 'local-copies\n' ;;
    runtime-cache-janitor*)                  printf 'codex-zone\n' ;;
    docker-log-rotation.sh)                  printf 'container-logs\n' ;;
    server-backup.sh)                        printf 'own-drill-dir\n' ;;
    *)                                       printf 'UNDECLARED\n' ;;
  esac
}

print_mechanisms() { # -> таблица удаляющих механизмов: источник | путь | статус; undeclared: N
  local src p status undeclared=0
  for src in crontab ecosystem; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ -f "$p" ] || continue
      grep -Eq 'rm[[:space:]]+-rf|-delete|truncate' "$p" 2>/dev/null || continue
      status=$(mechanism_status "$p")
      [ "$status" = UNDECLARED ] && undeclared=$((undeclared + 1))
      printf '%s | %s | %s\n' "$src" "$p" "$status"
    done <<<"$(declared_paths "$src")"
  done
  printf 'undeclared: %s\n' "$undeclared"
}

# --- ledger (spec:054 п.3) ---
ledger_init() {
  [ -s "$DR_LEDGER" ] && return
  printf 'ts\tmode\tpct_before\tpct_after\tfreed_mb\tstate\talert\ttop5\tdeclared_missing\n' >"$DR_LEDGER"
}

ledger_top5() { # имя=вес:дельта; разделитель ';'; дельта к последней строке live
  local i n w lastw delta out="" base seg
  base=$(awk -F'\t' '$2=="live"{last=$8} END{if (last!="") print last}' "$DR_LEDGER" 2>/dev/null)
  for i in "${!TOP5_DIRS[@]}"; do
    n="${TOP5_NAMES[$i]}"
    w=$(du -sm "${TOP5_DIRS[$i]}" 2>/dev/null | awk '{print $1}'); w="${w:-0}"
    lastw=""
    if [ -n "$base" ]; then
      for seg in ${base//;/ }; do
        [[ "$seg" == "$n="* ]] && { lastw="${seg#*=}"; lastw="${lastw%%:*}"; break; }
      done
    fi
    if [ -n "$lastw" ] && [[ "$lastw" =~ ^[0-9]+$ ]]; then
      delta=$((w - lastw))
    else
      delta=0
    fi
    out+="$n=$w:${delta};"
  done
  echo "${out%;}"
}

# --- алерт (один на состояние до восстановления) ---
send_alert() { # text -> 0/1
  local code
  if [ -n "$DR_NOTIFY_CMD" ]; then
    "$DR_NOTIFY_CMD" "$1"
    return $?
  fi
  local token="" chat=""
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    echo "ALERT-FAILED no token/chat" >>"$DR_LOG"
    return 1
  fi
  code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" 2>/dev/null)
  [ "$code" = "200" ]
}

alert_active() { # состояние
  awk -F= -v st="$1" '$1==st{found=1} END{exit !found}' "$DR_ALERT_STATE_FILE" 2>/dev/null
}

mark_alert() { # состояние
  sed -i "/^$1=/d" "$DR_ALERT_STATE_FILE" 2>/dev/null || true
  echo "$1=$(date +%s)" >>"$DR_ALERT_STATE_FILE"
}

clear_alert() { # состояние
  [ -f "$DR_ALERT_STATE_FILE" ] || return 0
  sed -i "/^$1=/d" "$DR_ALERT_STATE_FILE"
}

maybe_alert() { # состояние текст
  local st=$1 txt=$2
  local val
  if alert_active "$st"; then
    if [ "$st" = exhausted ]; then
      val=$(awk -F= -v st="$st" '$1==st{print $2}' "$DR_ALERT_STATE_FILE" 2>/dev/null)
      if [[ "$val" =~ ^[0-9]+$ ]] && [ $(( $(date +%s) - val )) -lt "$DR_REALERT_SEC" ]; then
        echo "ALERT-SKIP $st уже активен" >>"$DR_LOG"
        return 0
      fi
    else
      echo "ALERT-SKIP $st уже активен" >>"$DR_LOG"
      return 0
    fi
  fi
  if send_alert "$txt"; then
    ALERT_SENT=$((ALERT_SENT + 1))
    mark_alert "$st"
  else
    ALERT_FAIL=$((ALERT_FAIL + 1))
  fi
}

# Кандидаты ходят сюда: в dry-run печатаются, иначе удаляются. Все проверены по DENY_LIST.
journal_row() { # class action path size snapshot restore reason -> 10-колоночная строка в $DR_JOURNAL
  local class=$1 action=$2 path=$3 size=$4
  if [ "$action" = fixed ] && [[ "$size" =~ ^[0-9]+$ ]]; then
    FIXED_COUNT=$((FIXED_COUNT + 1))
    FIXED_MB=$((FIXED_MB + size / 1024 / 1024))
  elif [ "$action" = deferred ]; then
    DEFERRED_COUNT=$((DEFERRED_COUNT + 1))
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" "$RUN_ID" "$JOURNAL_MODE" "$@" >>"$DR_JOURNAL"
}

# Верхний уровень /tmp: удаляет старые записи каждый прогон (spec dcfg-oglfz).
# Щадит чужие процессы, известные временные каталоги и сокеты; в dry-run только печатает.
cleanup_tmp() {
  local root=${DR_TMP_ROOT:-/tmp}
  local age_min=${DR_TMP_AGE_MIN:-1440}
  local max=${DR_TMP_MAX:-500}
  [ -d "$root" ] && [ ! -L "$root" ] || return 0
  local -a live_cwds=() candidates=()
  local -A open_fds=()
  local cwd tgt p name c skip deleted=0 fd top
  # Один проход по cwd живых процессов до цикла кандидатов.
  for cwd in /proc/[0-9]*/cwd; do
    [ -L "$cwd" ] || continue
    tgt=$(readlink -- "$cwd" 2>/dev/null) || continue
    [ -n "$tgt" ] || continue
    live_cwds+=("$tgt")
  done
  # Цели открытых дескрипторов под корнем: верхний уровень в ассоциативный массив
  # (без дублей), чтобы уборка не удаляла записи, открытые живыми процессами.
  for fd in /proc/[0-9]*/fd/*; do
    [ -L "$fd" ] || continue
    tgt=$(readlink -- "$fd" 2>/dev/null) || continue
    [[ "$tgt" == "$root/"* ]] || continue
    top=${tgt#"$root/"}; top=${top%%/*}
    open_fds["$root/$top"]=1
  done
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    name=${p##*/}
    case "$name" in
      tmux-*|claude-*|systemd-private-*|snap-private-tmp|restic-*|.X*|.ICE-unix|.font-unix|*.lock|*.pid|*.sock) continue ;;
    esac
    skip=0
    for c in "${live_cwds[@]}"; do
      if [ "$p" = "$c" ] || [[ "$c" == "$p"/* ]]; then skip=1; break; fi
    done
    [ "$skip" -eq 1 ] && continue
    [ -n "${open_fds[$p]:-}" ] && continue
    candidates+=("$p")
  done < <(find -P "$root" -mindepth 1 -maxdepth 1 -mmin +"$age_min" ! -type s -print0 2>/dev/null)
  [ "${#candidates[@]}" -gt 0 ] || return 0
  [ "${#candidates[@]}" -gt "$max" ] && candidates=("${candidates[@]:0:$max}")
  if [ "$MODE" = dry-run ]; then
    for p in "${candidates[@]}"; do
      printf 'tmp candidate: %s\n' "$p"
    done
    return 0
  fi
  if [ "$root" = /tmp ]; then
    nice -n 19 ionice -c3 "$TOOLS/bin/safe-delete" tmp "${candidates[@]}" 2>>"$DR_LOG"
  else
    nice -n 19 ionice -c3 rm -r -- "${candidates[@]}" 2>>"$DR_LOG"
  fi
  for p in "${candidates[@]}"; do
    if [ -e "$p" ]; then
      journal_row tmp failed "$p" - - - "removal failed"
    else
      journal_row tmp deleted "$p" - - - -
      deleted=$((deleted + 1))
    fi
  done
  echo "tmp: deleted $deleted" >>"$DR_LOG"
}

# Только функции (тесты подключают скрипт через source): выход до основного потока.
if [ "${DR_SOURCE_ONLY:-}" = 1 ]; then
  return 0 2>/dev/null || exit 0
fi

# Общий список незаменимых файлов прогона (копится во время классов, фиксируется
# через гейт после них). Создаётся в начале каждого прогона; удаляется при выходе.
IRR_LIST=$(mktemp /tmp/disk-rotate-irr-XXXX) || exit 1
trap 'rm -f -- "$IRR_LIST"' EXIT

# --check-declared: сверка объявленных путей; без уборки и без строки в ledger.
if [ "$MODE" = check ]; then
  check_declared
  if [ "$DECLARED_MISSING" -gt 0 ]; then
    maybe_alert declared "Уборка диска: не найдено $DECLARED_MISSING запланированных скриптов — часть автозадач не работает. Нужен атом."
  else
    clear_alert declared
  fi
  print_mechanisms
  echo "=== $(date '+%F %T') END ===" >>"$DR_LOG"
  exit 0
fi

# --report: только отчёт о росте; без уборки, без алерта, без ledger.
if [ "$MODE" = report ]; then
  echo "growth:"
  awk -F'\t' '
    BEGIN { one_day = 86400; seven_days = 7 * 86400; now = systime() }
    $2 == "live" && $1 != "ts" {
      ts = $1
      ts = substr(ts, 1, 19)
      gsub(/[-T:]/, " ", ts)
      ts_sec = mktime(ts)
      if (ts_sec >= now - one_day) {
        top5 = $8
        n = split(top5, segs, ";")
        for (i = 1; i <= n; i++) {
          if (segs[i] != "") {
            split(segs[i], kv, "=")
            name = kv[1]
            split(kv[2], vw, ":")
            delta = vw[2] + 0
            d1[name] += delta
          }
        }
      }
      if (ts_sec >= now - seven_days) {
        top5 = $8
        n = split(top5, segs, ";")
        for (i = 1; i <= n; i++) {
          if (segs[i] != "") {
            split(segs[i], kv, "=")
            name = kv[1]
            split(kv[2], vw, ":")
            delta = vw[2] + 0
            d7[name] += delta
          }
        }
      }
    }
    END {
      for (name in d1) print "1d " name " +" d1[name]
      for (name in d7) print "7d " name " +" d7[name]
    }
  ' "$DR_LEDGER" 2>/dev/null | sort -t' ' -k2,2 -k3,3rn
  exit 0
fi

# Измерение до уборки и состояние.
pct_before=$(use_pct)
used_before=${DR_USED_KB_BEFORE:-$(used_kb)}
if [ "$pct_before" -ge "$HARD_PCT" ]; then
  state=hard
elif [ "$pct_before" -ge "$SOFT_PCT" ]; then
  state=soft
else
  state=below
fi
state_ledger=$state
mode_ledger=live
[ "$MODE" = dry-run ] && mode_ledger=dry
[ "$MODE" = report ] && mode_ledger=report

# «Объявленное существует» — при обычном прогоне (spec:054 п.4).
DECLARED_MISSING=0
if [ "$MODE" = run ] && [ "$DR_TEST_ONLY" != 1 ] && [ "$CODEX_CLEAN_ONLY" != 1 ]; then
  check_declared
  if [ "$DECLARED_MISSING" -gt 0 ]; then
    echo "DECLARED-MISSING $DECLARED_MISSING" >>"$DR_LOG"
    maybe_alert declared "Уборка диска: не найдено $DECLARED_MISSING запланированных скриптов — часть автозадач не работает. Нужен атом."
  else
    clear_alert declared
  fi
fi

restic_env() { # задать RESTIC_REPOSITORY/RESTIC_PASSWORD_FILE из DR_RESTIC_REPO или env-файлов
  RESTIC=${RESTIC:-/root/workspaces/tools/bin/restic}
  if [ -n "${DR_RESTIC_REPO:-}" ]; then
    export RESTIC_REPOSITORY="$DR_RESTIC_REPO" RESTIC_PASSWORD_FILE="$DR_RESTIC_PASSWORD_FILE"
  else
    set -a
    # shellcheck disable=SC1090
    source "/root/workspaces/secrets/yandex-s3.env"
    # shellcheck disable=SC1090
    source "/root/workspaces/secrets/restic.env"
    set +a
  fi
}

gate_open() { # -> 0 если предусловие гейта выполнено; иначе печатает причину в GATE_REASON и 1
  GATE_REASON=
  local last_ok now_s
  if [ ! -f "$DR_LAST_OK" ]; then
    GATE_REASON=no-last-ok
    return 1
  fi
  last_ok=$(cat "$DR_LAST_OK" 2>/dev/null)
  now_s=$(date +%s)
  if [ $(( now_s - last_ok )) -gt 129600 ]; then
    GATE_REASON=last-ok-stale
    return 1
  fi
  if ! "$RESTIC" cat config >/dev/null 2>&1; then
    GATE_REASON=restic-unreachable
    return 1
  fi
  if ! "$RESTIC" check --retry-lock 10m >>"$DR_LOG" 2>&1; then
    GATE_REASON=restic-check-failed
    return 1
  fi
  return 0
}

irrep_candidates() { # -> незаменимые кандидаты (не в state, не в DENY_LIST) на stdout
  if [ -n "$DR_TEST_IRREPLACEABLE_DIR" ] && [ -d "$DR_TEST_IRREPLACEABLE_DIR" ]; then
    while IFS= read -r -d '' p; do
      denied "$p" && continue
      grep -qxF "$p" <(awk -F'\t' '{print $1}' "$DR_STATE_FILE" 2>/dev/null) && continue
      printf '%s\n' "$p"
    done < <(find "$DR_TEST_IRREPLACEABLE_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
  fi
  for p in "${REFIX_PATHS[@]:-}"; do
    printf '%s\n' "$p"
  done
}

# --restore-drill (spec:055): репетиция восстановления; без уборки и без ledger.
if [ "$MODE" = drill ]; then
  restic_env
  drill_tag=${DR_DRILL_TAG:-predelete}
  drill_id=$("$RESTIC" snapshots --tag "$drill_tag" --latest 1 --json 2>/dev/null \
    | jq -r '.[0].short_id' 2>/dev/null)
  if [ -z "$drill_id" ] || [ "$drill_id" = null ]; then
    echo "drill: 0 files"
    exit 1
  fi
  drill_d=$(mktemp -d /tmp/restore-drill-XXXX) || exit 1
  "$RESTIC" restore "$drill_id" --target "$drill_d" --verify >/dev/null 2>&1
  drill_rc=$?
  drill_n=0; drill_m=0; drill_k=0; drill_v=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    real="${f#"$drill_d"}"
    if [ ! -f "$real" ]; then
      # оригинала уже нет: содержимое проверил сам restic (--verify)
      drill_v=$((drill_v + 1))
      continue
    fi
    drill_n=$((drill_n + 1))
    if cmp -s -- "$f" "$real"; then
      drill_m=$((drill_m + 1))
    else
      drill_k=$((drill_k + 1))
    fi
  done < <(find "$drill_d" -type f 2>/dev/null)
  rm -rf -- "$drill_d"
  echo "drill: $drill_n files, $drill_m match, $drill_k mismatch, $drill_v verified"
  if [ "$drill_rc" -eq 0 ] && [ "$drill_k" -eq 0 ] && [ $((drill_n + drill_v)) -gt 0 ]; then
    echo "RESTORE_OK $drill_id $((drill_n + drill_v)) files"
    exit 0
  fi
  exit 1
fi

# Каталог состояния: state и logrotate дописывают в него с первого прогона.
# Создаём заранее, чтобы запись не падала и logrotate не ругался на отсутствие.
mkdir -p "$(dirname "$DR_STATE_FILE")" /var/lib/disk-rotate
mkdir -p "$(dirname "$DR_LOGROTATE_STATE")"

fix_candidates() { # class listfile -> 0/1; фиксирует незаменимые в restic predelete и пишет state/journal
  local class=$1 listfile=$2
  local -a paths=() fix_paths=()
  local -A sha1_map=()
  local p sha1 sha2 size mtime snapshot_id dump rc total quota
  local quota=${DR_FIX_QUOTA_BYTES:-10737418240}
  total=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    paths+=("$p")
    sha1_map["$p"]=$(sha256sum < "$p" | cut -c1-64)
  done <"$listfile"
  # Квота (spec:055): при превышении бюджета оставшиеся пути не фиксируем, а откладываем.
  for p in "${paths[@]}"; do
    size=$(stat -c %s "$p" 2>/dev/null || echo 0)
    if [ "$total" -gt 0 ] && [ $((total + size)) -gt "$quota" ]; then
      journal_row "$class" deferred "$p" "$size" - - quota
      continue
    fi
    fix_paths+=("$p")
    total=$((total + size))
  done
  if [ "${#fix_paths[@]}" -eq 0 ]; then
    return 1
  fi
  fix_list=$(mktemp)
  printf '%s\n' "${fix_paths[@]}" >"$fix_list"
  local tags=predelete
  # backups: копия — единственная после удаления, forget её не трогает (владелец 10.10)
  # codex-*: отгруженные данные хранятся бессрочно и находятся по тегу codex (владелец 26.10)
  case "$class" in
    backups) tags=predelete,keep-archive ;;
    codex-sessions|codex-tmp) tags=predelete,keep-archive,codex ;;
  esac
  dump=$("$RESTIC" backup --files-from-verbatim "$fix_list" --tag "$tags" --host "$(hostname)" --json)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    for p in "${fix_paths[@]}"; do
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      journal_row "$class" deferred "$p" "$size" - - restic-backup-failed
    done
    rm -f -- "$fix_list"
    return 1
  fi
  snapshot_id=$(printf '%s' "$dump" | jq -r 'select(.message_type=="summary") | .snapshot_id')
  for p in "${fix_paths[@]}"; do
    sha2=$(sha256sum < "$p" | cut -c1-64)
    if [ "${sha1_map["$p"]}" = "$sha2" ]; then
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      mtime=$(stat -c %Y "$p" 2>/dev/null || echo -)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$p" "$size" "$mtime" "$sha2" "$snapshot_id" "$(date +%s)" >>"$DR_STATE_FILE"
      journal_row "$class" fixed "$p" "$size" "$snapshot_id" - -
    else
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      journal_row "$class" deferred "$p" "$size" - - changed-during-snapshot
    fi
  done
  rm -f -- "$fix_list"
}

verify_and_delete() { # class -> удаление по гейту: проверка копии в restic; заполняет REFIX_PATHS
  local class=$1
  [ -f "$DR_STATE_FILE" ] || return 0
  local tmp now_s path size mtime sha256 snapshot_id fixed_ts sid_path line own
  local -a rec
  local -A snap_path=() snap_done=() snap_kept=()
  local p s m ms meta snap_size snap_mtime
  tmp=$(mktemp)
  now_s=$(date +%s)
  while IFS= read -r line || [ -n "$line" ]; do
    IFS=$'\t' read -ra rec <<<"$line"
    path="${rec[0]:-}"; own=0
    # ponytail: six-column state uses path ownership; add class metadata if classes share paths.
    case "$class" in
      projects) for p in "${PROJECTS_ALLOW[@]}"; do [[ "$path" == $p ]] && { own=1; break; }; done ;;
      runner) for p in $DR_RUNNER_ROOTS; do [[ "$path" == "$p/"* ]] && { own=1; break; }; done ;;
      backups) backup_rule_match "$path" && own=1 ;;
      codex-sessions) for p in "$DR_CODEX_HOME/sessions" "$DR_CODEX_HOME/archived_sessions"; do [[ "$path" == "$p/"* ]] && { own=1; break; }; done ;;
      codex-tmp) for p in "$DR_CODEX_HOME/.tmp" "$DR_CODEX_HOME/tmp"; do [[ "$path" == "$p/"* ]] && { own=1; break; }; done ;;
      test-irreplaceable) [ -n "${DR_TEST_IRREPLACEABLE_DIR:-}" ] && [[ "$path" == "$DR_TEST_IRREPLACEABLE_DIR/"* ]] && own=1 ;;
      codex-clean) [[ "$path" == "$DR_CODEX_HOME"/codex-clean.*/* ]] && own=1 ;;
    esac
    if [ "$own" -eq 0 ] || [ "${#rec[@]}" -ne 6 ]; then
      printf '%s\n' "$line" >>"$tmp"
      continue
    fi
    path="${rec[0]}"; size="${rec[1]}"; mtime="${rec[2]}"
    sha256="${rec[3]}"; snapshot_id="${rec[4]}"; fixed_ts="${rec[5]}"
    [ -n "$path" ] || continue
    if [ ! -e "$path" ]; then
      journal_row "$class" vanished "$path" "$size" "$snapshot_id" - -
      continue
    fi
    if [ $((now_s - fixed_ts)) -gt 86400 ]; then
      journal_row "$class" snapshot-stale "$path" "$size" "$snapshot_id" - -
      REFIX_PATHS+=("$path")
      continue
    fi
    if [ -z "${snap_done[$snapshot_id]:-}" ]; then
      snap_done[$snapshot_id]=1
      [ "$class" = backups ] && snap_kept[$snapshot_id]=$("$RESTIC" snapshots --json "$snapshot_id" 2>/dev/null \
        | jq -r '.[0].tags // [] | index("keep-archive") != null' 2>/dev/null)
      while IFS=$'\t' read -r p s m; do
        [ -n "$p" ] || continue
        ms=$(date -d "$m" +%s 2>/dev/null || echo 0)
        snap_path["$snapshot_id"$'\x1f'"$p"]="$s"$'\t'"$ms"
      done < <("$RESTIC" ls --json "$snapshot_id" 2>/dev/null \
        | jq -r 'select(.struct_type=="node" and .type=="file") | [.path, (.size|tostring), .mtime] | @tsv')
    fi
    # backups: удаление только при бессрочной копии (keep-archive), иначе перефиксация с меткой (владелец 10.10)
    if [ "$class" = backups ] && [ "${snap_kept[$snapshot_id]:-}" != true ]; then
      journal_row "$class" snapshot-not-kept "$path" "$size" "$snapshot_id" - -
      REFIX_PATHS+=("$path")
      continue
    fi
    sid_path="$snapshot_id"$'\x1f'"$path"
    if [ -z "${snap_path[$sid_path]+set}" ]; then
      journal_row "$class" changed-after-snapshot "$path" "$size" "$snapshot_id" - -
      REFIX_PATHS+=("$path")
      continue
    fi
    meta="${snap_path[$sid_path]}"
    snap_size="${meta%%$'\t'*}"; snap_mtime="${meta#*$'\t'}"
    if [ "$snap_size" = "$(stat -c %s "$path" 2>/dev/null)" ] \
       && [ "$snap_mtime" = "$(stat -c %Y "$path" 2>/dev/null)" ] \
       && [ "$(sha256sum < "$path" | cut -c1-64)" = "$sha256" ]; then
    if [ "$GATE_MODE" = enforce ]; then
      rm -f -- "$path"
      journal_row "$class" deleted "$path" "$size" "$snapshot_id" \
          "$RESTIC restore $snapshot_id --repo '$RESTIC_REPOSITORY' --target /var/lib/disk-rotate/restore/$RUN_ID --include '$path'" -
    else
      journal_row "$class" would-delete "$path" "$size" "$snapshot_id" - -
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$path" "$size" "$mtime" "$sha256" "$snapshot_id" "$fixed_ts" >>"$tmp"
      fi
      continue
    fi
    journal_row "$class" changed-after-snapshot "$path" "$size" "$snapshot_id" - -
    REFIX_PATHS+=("$path")
  done <"$DR_STATE_FILE"
  mv -f "$tmp" "$DR_STATE_FILE"
}

gate_process() { # class listfile -> 0, либо RC_GATE_CLOSED при закрытом гейте
  local class=$1 listfile=$2
  local p path size rec
  local -A known=()
  restic_env
  GATE_REASON=
  GATE_RC=0
  if ! gate_open; then
    # незаменимые не фиксируем и не удаляем — только журнал с причиной закрытия
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      journal_row "$class" deferred "$p" "$size" - - "gate-closed:$GATE_REASON"
    done <"$listfile"
    GATE_RC=$RC_GATE_CLOSED
    return $RC_GATE_CLOSED
  fi
  verify_and_delete "$class"
  # Уже зафиксированные (в state) при повторной фиксации пропускаем; к оставшимся
  # добавляем пути из списка повторной фиксации (stale/changed в verify_and_delete).
  local tmp
  tmp=$(mktemp)
  if [ -f "$DR_STATE_FILE" ]; then
    while IFS=$'\t' read -ra rec; do
      [ "${#rec[@]}" -eq 6 ] || continue
      path="${rec[0]}"
      [ -n "$path" ] || continue
      known["$path"]=1
    done <"$DR_STATE_FILE"
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || continue
    [ -n "${known[$p]:-}" ] && continue
    printf '%s\n' "$p"
  done <"$listfile" >"$tmp"
  for p in "${REFIX_PATHS[@]:-}"; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || continue
    printf '%s\n' "$p"
  done >>"$tmp"
  if [ -s "$tmp" ]; then
    fix_candidates "$class" "$tmp" || GATE_RC=$?
  fi
  rm -f "$tmp"
  # срок хранения снимков predelete: 10 дней (владелец 02.10, CR-02 §6 п.4); неудача не блокирует прогон
  if ! "$RESTIC" forget --quiet --tag predelete --group-by host,tags --keep-within 10d --keep-tag keep-archive >>"$DR_LOG" 2>&1; then
    journal_row gate forget-skipped - 0 - - forget-locked
  fi
  # при занятости >=95% свежие снимки проходят правило 24 ч сразу
  if [ "$(use_pct)" -ge 95 ]; then
    verify_and_delete "$class"
  fi
  return $GATE_RC
}

handle() { # class [irr]; пути из stdin (NUL). irr — незаменимые: не удалять, копить в IRR_LIST
  local cls=$1 irr=${2:-} p kb age size label
  label=$cls
  [ "$irr" = irr ] && label=irreplaceable
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    denied "$p" && continue
    [ -f "$p" ] && [ ! -L "$p" ] || continue
    [ "$(realpath -e -- "$p" 2>/dev/null)" = "$p" ] || continue
    if [ "$MODE" = dry-run ]; then
      kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      age=$(( (now - $(stat -c %Y "$p" 2>/dev/null)) / 86400 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t%sd\t%s\n' "$p" "$kb" "$age" "$label"
    elif [ "$irr" = irr ]; then
      printf '%s\n' "$p" >>"$IRR_LIST"
    else
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      if rm -f -- "$p" 2>>"$DR_LOG"; then
        journal_row "$cls" deleted "$p" "$size" replaceable - -
      else
        CLEANUP_FAILED=1
        journal_row "$cls" failed "$p" "$size" replaceable - "removal failed"
      fi
    fi
  done
}

# Один список regular files для dry/live, обработчик работает в текущем shell.
clean_dir() { # base mtime class
  local base=$1 mtime=$2 cls=$3 marker
  denied "$base" && return
  [ -d "$base" ] && [ ! -L "$base" ] || return 0
  [ "$(realpath -e -- "$base" 2>/dev/null)" = "$base" ] || return 0
  # ponytail: skip a whole cache containing project markers; narrower cleanup needs owner approval.
  marker=$(find -P "$base" \( -name .git -o -name package.json -o -name pyproject.toml -o -name Cargo.toml -o -name go.mod -o -name '*.py' -o -name '*.js' -o -name '*.sh' \) -print -quit 2>/dev/null)
  [ -z "$marker" ] || return 0
  handle "$cls" < <(find -P "$base" -mindepth 1 -mtime "+$mtime" -type f -print0 2>/dev/null)
}

# snap-revisions (owner 21.11): disabled-ревизии удаляются штатным snap; снят запрет из spec:054
# только для disabled — активные ревизии не трогаются. Guard: snapd жив.
cleanup_snap() {
  local line name rev notes
  command -v snap >/dev/null 2>&1 || return 0
  systemctl is-active --quiet snapd 2>/dev/null || { echo "snap: snapd неактивен, пропуск" >>"$DR_LOG"; return 0; }
  while read -r name rev notes; do
    [ -n "$name" ] && [ -n "$rev" ] || continue
    case " $notes " in *" disabled "*) ;; *) continue;; esac
    if [ "$MODE" = run ]; then
      if snap remove "$name" --revision="$rev" >>"$DR_LOG" 2>&1; then
        journal_row snap deleted "rev:$name:$rev" - replaceable - "disabled revision removed"
      else
        CLEANUP_FAILED=1
        journal_row snap failed "rev:$name:$rev" - replaceable - "snap remove failed"
      fi
    else
      printf 'rev:%s:%s\t0k\t-\tsnap-revision\n' "$name" "$rev"
    fi
  done < <(snap list --all 2>/dev/null | awk 'NR>1 && $NF ~ /disabled/ {print $1, $3, $NF}')
}

# vscode-servers (owner 21.11): мёртвые серверы удаляются; активные определяются по процессам и lru.json.
cleanup_vscode() {
  local base=/root/.vscode-server/cli/servers d keep
  [ -d "$base" ] && [ ! -L "$base" ] || return 0
  for d in "$base"/Stable-*; do
    [ -d "$d" ] || continue
    # активен: процесс с cwd/exe/fd внутри каталога
    if grep -qF "$d" /proc/[0-9]*/cwd /proc/[0-9]*/exe 2>/dev/null; then continue; fi
    # активен: упомянут живыми процессами (командные строки)
    if ps -eo args 2>/dev/null | grep -F "$d" | grep -qv grep; then continue; fi
    denied "$d" && continue
    handle vscode < <(find -P "$d" -type f -print0 2>/dev/null)
    if [ "$MODE" = run ]; then
      find "$d" -depth -type d -empty -delete 2>/dev/null
    fi
  done
  # lru.json: подрезать до живых серверов
  if [ "$MODE" = run ] && [ -f "$base/lru.json" ]; then
    keep=$(ls -1 "$base" 2>/dev/null | grep '^Stable-' | tr '\n' ',' | sed 's/,$//')
    [ -n "$keep" ] || return 0
    python3 - "$base/lru.json" "$keep" <<'PY' 2>/dev/null || echo "vscode lru trim skipped" >>"$DR_LOG"
import json, sys
p, keep = sys.argv[1], sys.argv[2].split(',')
data = json.load(open(p))
trimmed = [x for x in (data if isinstance(data, list) else []) if x in keep]
if trimmed != data:
    json.dump(trimmed, open(p, 'w'))
PY
  fi
}

# node-versions (owner 21.11): неактивные версии nvm удаляются; активные — по процессам и alias.
cleanup_node() {
  local nvm_root=${DR_NVM_ROOT:-/root/.nvm/versions/node} d active alias keep
  [ -d "$nvm_root" ] || return 0
  # цели: alias default и lts
  keep="$({
    cat "$nvm_root/../alias/default" 2>/dev/null
    cat "$nvm_root/../alias/lts" 2>/dev/null
  } | grep -E '^v?[0-9]' | sed 's/^/v/' | sort -u)"
  for d in "$nvm_root"/v*; do
    [ -d "$d" ] || continue
    active=0
    # процесс использует эту версию
    if ps -eo args 2>/dev/null | grep -F "$d" | grep -qv grep; then active=1; fi
    # версия в keep-списке alias
    if echo "$keep" | grep -qF "$(basename "$d")"; then active=1; fi
    [ "$active" = 1 ] && continue
    denied "$d" && continue
    handle node < <(find -P "$d" -type f -mtime +7 -print0 2>/dev/null)
    if [ "$MODE" = run ]; then
      find "$d" -depth -type d -empty -delete 2>/dev/null
      rmdir --ignore-fail-on-non-empty -p "$d" 2>/dev/null || true
    fi
  done
}

# sandbox (owner 21.11): тестовые песочницы старше 30 дней; test-assert исключён (TOOLS-REGISTRY).
cleanup_sandbox() {
  local base=/root/workspaces/sandbox d
  [ -d "$base" ] && [ ! -L "$base" ] || return 0
  local age_min=$(( ${DR_SANDBOX_AGE_DAYS:-30} * 1440 ))
  for d in "$base"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = test-assert ] && continue
    # каталог занят живым процессом (cwd/exe/fd)
    if grep -qF "$d" /proc/[0-9]*/cwd /proc/[0-9]*/exe 2>/dev/null; then continue; fi
    denied "$d" && continue
    handle sandbox < <(find -P "$d" -type f -mmin +"$age_min" -print0 2>/dev/null)
    if [ "$MODE" = run ]; then
      find "$d" -depth -type d -empty -delete 2>/dev/null
    fi
  done
}

# migration-dups (owner 21.11): .tmp-копии репо удаляются только при точном совпадении HEAD с живым оригиналом.
cleanup_migration_dups() {
  local base=/root/workspaces/projects/.tmp/repo-migration-backups b name live bh lh
  [ -d "$base" ] || return 0
  for b in "$base"/*.git; do
    [ -d "$b" ] || continue
    name=$(basename "$b" .git)
    live=""
    for cand in /root/workspaces/git-dirs/"$name".git /root/workspaces/projects/"$name" \
                /root/workspaces/projects/clients/"$name" /root/workspaces/system/services/"$name"; do
      [ -d "$cand" ] && live="$cand"
    done
    if [ -z "$live" ]; then
      echo "migration-dup: $name без живого оригинала — не трогаем" >>"$DR_LOG"
      continue
    fi
    bh=$(git -C "$b" rev-parse HEAD 2>/dev/null); lh=$(git -C "$live" rev-parse HEAD 2>/dev/null)
    if [ "$bh" != "$lh" ] || [ -z "$bh" ]; then
      echo "migration-dup: $name HEAD расходится ($bh vs $lh) — не трогаем" >>"$DR_LOG"
      continue
    fi
    handle migration-dup < <(find -P "$b" -type f -print0 2>/dev/null)
    if [ "$MODE" = run ]; then
      find "$b" -depth -type d -empty -delete 2>/dev/null
    fi
  done
}

cleanup_cache() { # только доказанные заменимые кэши, каждый прогон
  clean_dir /root/.cache/pip               1 cache
  clean_dir /root/.npm/_cacache            1 cache
  clean_dir /root/.nvm/.cache              1 cache
  clean_dir /var/lib/snapd/cache           1 cache
  clean_dir /root/.cache/go-build          1 cache
  clean_dir /root/.cache/pnpm              1 cache
  clean_dir /root/.cache/typescript        1 cache
  clean_dir /root/.cache/mesa_shader_cache 1 cache
  clean_dir /root/.cache/composer          1 cache
  clean_dir /root/.cache/uv                1 cache
  # codebase-memory-mcp (owner 21.11): регенерируемый индекс MCP; исходники проектов живы отдельно.
  # _npx (owner 21.11): кэш npx-установок, регенерируется при следующем запуске; порог 30 дней.
  clean_dir /root/.cache/codebase-memory-mcp 1 cache
  clean_dir /root/.npm/_npx                30 cache

  # browser/session/project data не кандидаты.
  # /tmp (верхний уровень) чистит cleanup_tmp.
  if [ "$MODE" = run ]; then
    if apt-get clean >>"$DR_LOG" 2>&1; then
      journal_row cache cleaned - - replaceable - "apt-get clean"
    else
      CLEANUP_FAILED=1
      journal_row cache failed - - replaceable - "apt-get clean failed"
    fi
    if journalctl --vacuum-size=200M >>"$DR_LOG" 2>&1; then
      journal_row logs cleaned - - replaceable - "journalctl --vacuum-size=200M"
    else
      CLEANUP_FAILED=1
      journal_row logs failed - - replaceable - "journalctl vacuum failed"
    fi
    # owner 21.11: агрессивная очистка образов — только по явному флагу (по умолчанию off).
    if [ "${DOCKER_AGGRESSIVE:-0}" = 1 ]; then
      if docker image prune -a -f >>"$DR_LOG" 2>&1; then
        journal_row docker-images cleaned - - replaceable - "docker image prune -a (DOCKER_AGGRESSIVE=1)"
      else
        CLEANUP_FAILED=1
        journal_row docker-images failed - - replaceable - "docker image prune -a failed"
      fi
    fi
  else
    echo "vendor actions: apt-get clean; journalctl --vacuum-size=200M (dry-run; not executed)"
  fi
}

cleanup_always() { # только существующая vendor log rotation, без чужих файлов
  local lr=/root/workspaces/tools/etc/disk-rotate-logrotate.conf
  if [ ! -f "$lr" ]; then
    CLEANUP_FAILED=1
    echo "logrotate: нет $lr" >>"$DR_LOG"
    return
  fi
  if [ "$MODE" = dry-run ]; then
    logrotate -d -s "$DR_LOGROTATE_STATE" "$lr" >>"$DR_LOG" 2>&1 || CLEANUP_FAILED=1
  else
    logrotate -s "$DR_LOGROTATE_STATE" "$lr" >>"$DR_LOG" 2>&1 || CLEANUP_FAILED=1
  fi
}

# codex-sessions / codex-tmp: старые файлы отгружаются в restic и удаляются гейтом,
# свежие остаются (владелец 26.10). Список — как у cleanup_backups.
cleanup_codex_offload() { # class base age_min
  local cls=$1 base=$2 age_min=$3 list
  [ -d "$base" ] && [ ! -L "$base" ] || return 0
  [ "$(realpath -e -- "$base" 2>/dev/null)" = "$base" ] || return 0
  if [ "$MODE" = run ]; then
    list=$(mktemp) || return 1
    find -P "$base" -type f -mmin +"$age_min" 2>/dev/null >>"$list"
    if [ -s "$list" ]; then
      REFIX_PATHS=()
      gate_process "$cls" "$list" || true
    fi
    rm -f -- "$list"
  else
    handle "$cls" < <(find -P "$base" -type f -mmin +"$age_min" -print0 2>/dev/null)
  fi
}

# Codex (владелец 26.10): старые сессии и tmp отгружаются в restic (S3) и удаляются, свежие остаются.
cleanup_codex() {
  local turns="$DR_CODEX_HOME/plugins/data/auto-review-just-every/turns"
  local standalone="$DR_CODEX_HOME/packages/standalone"
  local releases="$standalone/releases"
  local sessions="$DR_CODEX_HOME/sessions"
  local archived="$DR_CODEX_HOME/archived_sessions"
  local dot_tmp="$DR_CODEX_HOME/.tmp"
  local tmp="$DR_CODEX_HOME/tmp"
  local current d mt newest newest_mt b
  local offload_min=$(( ${DR_CODEX_OFFLOAD_DAYS:-14} * 1440 ))
  local tmp_min=$(( 14 * 1440 ))

  # codex-review: заменимые turn-файлы старше 24 ч
  if [ -d "$turns" ]; then
    handle codex-review < <(find -P "$turns" -mindepth 2 -type f -mmin +1440 -print0 2>/dev/null)
    if [ "$MODE" = run ]; then
      find "$turns" -mindepth 1 -type d -empty -delete 2>/dev/null
    fi
  fi

  # codex-releases: кроме цели current и одного самого нового после неё
  if [ -d "$releases" ]; then
    current=$(readlink -f "$standalone/current" 2>/dev/null || true)
    newest=; newest_mt=-1
    for d in "$releases"/*; do
      [ -d "$d" ] || continue
      [ "$(readlink -f -- "$d" 2>/dev/null)" = "$current" ] && continue
      mt=$(stat -c %Y "$d" 2>/dev/null || echo 0)
      if [ "$mt" -gt "$newest_mt" ]; then newest=$d; newest_mt=$mt; fi
    done
    for d in "$releases"/*; do
      [ -d "$d" ] || continue
      [ "$(readlink -f -- "$d" 2>/dev/null)" = "$current" ] && continue
      [ "$d" = "$newest" ] && continue
      handle codex-releases < <(find -P "$d" -type f -print0 2>/dev/null)
    done
    if [ "$MODE" = run ]; then
      find "$releases" -mindepth 1 -type d -empty -delete 2>/dev/null
    fi
  fi

  # codex-sessions: регулярные файлы старше DR_CODEX_OFFLOAD_DAYS дней (0 = все)
  for b in "$sessions" "$archived"; do
    cleanup_codex_offload codex-sessions "$b" "$offload_min"
  done
  # codex-tmp: старше 14 дней; свежие файлы могут держать живые процессы Codex
  for b in "$dot_tmp" "$tmp"; do
    cleanup_codex_offload codex-tmp "$b" "$tmp_min"
  done
  if [ "$MODE" = run ]; then
    for b in "$sessions" "$archived" "$dot_tmp" "$tmp"; do
      [ -d "$b" ] && find "$b" -mindepth 1 -type d -empty -delete 2>/dev/null
    done
  fi
}

# codex-clean (TZ dcfg-x0iaq): прямые подкаталоги CODEX_HOME/codex-clean.*; простаивающие уходят через гейт целиком.
codex_dir_in_use() { # dir -> 0, если cwd, exe или открытый fd живого процесса лежит внутри каталога
  local d=$1 l t
  for l in /proc/[0-9]*/cwd /proc/[0-9]*/exe /proc/[0-9]*/fd/*; do
    t=$(readlink -- "$l" 2>/dev/null) || continue
    if [ "$t" = "$d" ] || [[ "$t" == "$d"/* ]]; then return 0; fi
  done
  return 1
}

codex_clean_gate() { # dir -> CC_VERDICT; гейт restic, затем удаление проверенных файлов и пустых каталогов
  local d=$1 list rc=0
  list=$(mktemp) || { CC_VERDICT=failed; return; }
  find -P "$d" -type f 2>/dev/null >"$list"
  if [ -s "$list" ]; then
    REFIX_PATHS=()
    gate_process codex-clean "$list" || rc=$?
  fi
  rm -f -- "$list"
  if [ -n "$(find -P "$d" -type f -print -quit 2>/dev/null)" ]; then
    CC_VERDICT=pending
    if [ "$rc" -eq "$RC_GATE_CLOSED" ]; then CC_VERDICT=gate-closed; fi
  else
    find -P "$d" -type l -delete 2>/dev/null
    find -P "$d" -depth -type d -empty -delete 2>/dev/null
    CC_VERDICT=deleted
    if [ -e "$d" ]; then CC_VERDICT=pending; fi
  fi
}

codex_clean_ledger() { # name verdict size_mb -> строка ledger с именем каталога
  local freed=0 pct
  if [ "$2" = deleted ]; then freed=$3; fi
  pct=$(use_pct)
  ledger_init
  printf '%s\tcodex-clean:%s\t%s\t%s\t%s\t%s\t-\t-\t%s\n' \
    "$ts" "$1" "$pct" "$pct" "$freed" "$2" "${DECLARED_MISSING:-0}" >>"$DR_LEDGER"
}

cleanup_codex_clean() {
  local idle_min=${DR_CODEX_CLEAN_IDLE_MIN:-1440} d name size_mb verdict bad=0
  if ! [[ "$idle_min" =~ ^[0-9]+$ ]] || [ "$idle_min" -lt 1 ]; then
    bad=1
    echo "codex-clean: bad-config $idle_min" | tee -a "$DR_LOG"
  fi
  for d in "$DR_CODEX_HOME"/codex-clean.*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    [ "$(realpath -e -- "$d" 2>/dev/null)" = "$d" ] || continue
    name=${d##*/}
    size_mb=$(du -sm "$d" 2>/dev/null | awk '{print $1}')
    if [ "$bad" -eq 1 ]; then
      verdict=bad-config
    elif [ -n "$(find -P "$d" -mmin -"$idle_min" -print -quit 2>/dev/null)" ]; then
      verdict=fresh
    elif codex_dir_in_use "$d"; then
      verdict=in-use
    elif [ "$MODE" = dry-run ]; then
      verdict=eligible
    else
      codex_clean_gate "$d"
      verdict=$CC_VERDICT
    fi
    echo "codex-clean $name: $verdict" >>"$DR_LOG"
    if [ "$MODE" = dry-run ]; then
      echo "codex-clean $name: $verdict"
    else
      codex_clean_ledger "$name" "$verdict" "${size_mb:-0}"
    fi
  done
}

# Класс backups (владелец 10.10, spec:054 FR-027/029): в каждом правиле N новейших
# элементов маски остаются локально, остальные идут только через гейт restic.
cleanup_backups() {
  local rule n mask el list mt cnt
  local -a els keep
  # FR-032: живой режим класса — только после подтверждения владельцем списка сухого прогона.
  if [ "$MODE" = run ] && [ "${DR_BACKUPS_APPROVED:-0}" != 1 ]; then
    echo "BACKUPS-HOLD нет DR_BACKUPS_APPROVED=1 — класс backups не трогается" >>"$DR_LOG"
    return 0
  fi
  for rule in "${BACKUP_RULES[@]}"; do
    n=${rule%%|*}; mask=${rule#*|}
    els=()
    for el in $mask; do
      [ -e "$el" ] && [ ! -L "$el" ] || continue
      mt=$(stat -c %Y "$el" 2>/dev/null || echo 0)
      # только бэкапы старше подтверждения владельца (10.10 13:35); новые не трогаются
      [ "$mt" -lt "${DR_BACKUPS_BEFORE:-0}" ] || continue
      els+=("$mt"$'\t'"$el")
    done
    [ "${#els[@]}" -gt 0 ] || continue
    keep=(); cnt=0
    while IFS=$'\t' read -r mt el; do
      [ -n "$el" ] || continue
      cnt=$((cnt + 1))
      [ "$cnt" -le "$n" ] && continue
      keep+=("$el")
    done < <(printf '%s\n' "${els[@]}" | sort -t$'\t' -k1,1nr)
    [ "${#keep[@]}" -gt 0 ] || continue
    if [ "$MODE" = run ]; then
      list=$(mktemp) || continue
      for el in "${keep[@]}"; do find -P "$el" -type f 2>/dev/null >>"$list"; done
      REFIX_PATHS=()
      gate_process backups "$list" || true
      rm -f -- "$list"
      for el in "${keep[@]}"; do
        [ -d "$el" ] && [ ! -L "$el" ] && find "$el" -type d -empty -delete 2>/dev/null
      done
    else
      for el in "${keep[@]}"; do
        handle backups < <(find -P "$el" -type f -print0 2>/dev/null)
      done
    fi
  done
}

projects_candidates() { # -> безопасные files; WT_CANDIDATES для remove только после gate
  local agent=/root/workspaces/projects/.agent-work p rel top wt tmp ts zone path cls size after freed rc state line self_dir
  WT_CANDIDATES=(); PROJECTS_NOTICES=()
  if [ -d "$agent" ]; then while IFS= read -r p; do
    case "$p" in *.log|*.txt|*.out|*.jsonl|*.json|*.md|*.csv|*.tsv|*.html) ;; *) continue;; esac
    case "/$p/" in */node_modules/*|*/.git/*|*/.venv/*|*/__pycache__/*|*/dist/*|*/.worktrees/*) continue;; esac
    rel=${p#"$agent/"}; top=${rel%%/*}; [ -e "$agent/$top/.git" ] && continue
    denied "$p" || { [ -f "$p" ] && [ ! -L "$p" ] && [ "$(realpath -e -- "$p" 2>/dev/null)" = "$p" ] && printf '%s\n' "$p"; }
  done < <(find -P "$agent" -type f -mtime +"${DZ_AGE_DAYS:-14}" 2>/dev/null); fi
  self_dir=$(cd "${0%/*}" && pwd -P)
  for wt in /root/workspaces/projects/.worktrees/codex /root/workspaces/projects/.worktrees/claude; do
    [ -d "$wt" ] || continue; tmp=$(mktemp) || continue
    if ! (cd /root/workspaces/projects && ZONE_MODE=dry-run DZ_CODEX_WT="$wt" DZ_ZONES_TSV="$tmp" bash "$self_dir/disk-zones/codex-worktrees.sh") >>"$DR_LOG" 2>&1; then
      echo "projects classifier failed: $wt" >>"$DR_LOG"; rm -f -- "$tmp"; continue
    fi
    while IFS=$'\t' read -r ts zone path cls size after freed rc state; do
      case "$state" in
        candidate) WT_CANDIDATES+=("$path")
          while IFS= read -r p; do p="$path/$p"
            denied "$p" || { [ -f "$p" ] && [ ! -L "$p" ] && [ "$(realpath -e -- "$p" 2>/dev/null)" = "$p" ] && printf '%s\n' "$p"; }
          done < <(git -C "$path" ls-files --others);;
        run-done) ;;
        *) line="kept-${state#kept-}"$'\t'"$path"
          echo "$line" >>"$DR_LOG"
          [ "$MODE" = dry-run ] && PROJECTS_NOTICES+=("$line");;
      esac
    done <"$tmp"; rm -f -- "$tmp"
  done
  size=$(du -sm /root/workspaces/projects/hh-scoring-dev 2>/dev/null | awk '{print $1}')
  line="hh-scoring-dev size: ${size:-0}M (closed zone)"
  echo "$line" >>"$DR_LOG"; [ "$MODE" = dry-run ] && PROJECTS_NOTICES+=("$line")
}

projects_gate() {
  local list p wt others status root reason
  list=$(mktemp) || return; projects_candidates >"$list"
  if [ "$MODE" = dry-run ]; then [ "${#PROJECTS_NOTICES[@]}" -eq 0 ] || printf '%s\n' "${PROJECTS_NOTICES[@]}"; while IFS= read -r p; do handle projects < <(printf '%s\0' "$p"); done <"$list"
  else
    REFIX_PATHS=(); gate_process projects "$list" || true
    if [ "$GATE_MODE" = enforce ]; then for wt in "${WT_CANDIDATES[@]}"; do
      status=
      if others=$(git -C "$wt" ls-files --others) && status=$(git -C "$wt" status --porcelain --ignored) && [ -z "$others" ] && [ -z "$status" ] && root=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
        root=${root%/.git}; if git -C "$root" worktree remove -- "$wt"; then journal_row projects worktree-removed "$wt" - - - -; else journal_row projects worktree-kept "$wt" - - - remove-refused; fi
      else
        reason=pending-gate
        if printf '%s\n' "$status" | grep -q '^!! '; then
          reason=kept-ignored
          printf 'kept-ignored\t%s\n' "$wt" >>"$DR_LOG"
        fi
        journal_row projects worktree-kept "$wt" - - - "$reason"
      fi
    done; fi
  fi
  rm -f -- "$list"
}

runner_old_dirs() { # root -> старые версии bin.* и externals.* (каталоги); текущие цели bin и externals не входят
  local root=$1 cur_bin cur_ext d real
  cur_bin=$(readlink -f "$root/bin"); cur_ext=$(readlink -f "$root/externals")
  for d in "$root"/bin.* "$root"/externals.*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    real=$(readlink -f "$d")
    { [ "$real" = "$cur_bin" ] || [ "$real" = "$cur_ext" ]; } && continue
    printf '%s\n' "$d"
  done
}

runner_candidates() { # -> файлы класса runner на stdout; корни из DR_RUNNER_ROOTS
  local root cur_bin cur_ext d e pid exe busy p
  for root in $DR_RUNNER_ROOTS; do
    if denied "$root"; then echo "runner denied: $root" >>"$DR_LOG"; continue; fi
    [ -d "$root" ] && [ ! -L "$root" ] || continue
    cur_bin=$(readlink -f "$root/bin"); cur_ext=$(readlink -f "$root/externals")
    if [ -z "$cur_bin" ] || [ -z "$cur_ext" ]; then echo "runner skipped: $root no current version" >>"$DR_LOG"; continue; fi
    while IFS= read -r d; do find -P "$d" -type f 2>/dev/null; done < <(runner_old_dirs "$root")
    busy=0
    for pid in /proc/[0-9]*; do
      exe=$(readlink "$pid/exe" 2>/dev/null) || continue
      [[ "$exe" == "$cur_bin/"*Runner.Worker ]] && { busy=1; break; }
    done
    if [ "$busy" -eq 1 ]; then echo "runner busy: $root" >>"$DR_LOG"; continue; fi
    for e in "$root/_work"/*; do
      [ -e "$e" ] || continue
      [ "${e##*/}" = _tool ] && continue
      [ -z "$(find -P "$e" -newermt "-${DR_RUNNER_WORK_DAYS:-7} days" -print -quit 2>/dev/null)" ] || continue
      find -P "$e" -type f 2>/dev/null
    done
  done | while IFS= read -r p; do
    denied "$p" || { [ -f "$p" ] && [ ! -L "$p" ] && [ "$(realpath -e -- "$p" 2>/dev/null)" = "$p" ] && printf '%s\n' "$p"; }
  done
}

runner_gate() {
  local list p root d
  list=$(mktemp) || return; runner_candidates >"$list"
  if [ "$MODE" = dry-run ]; then while IFS= read -r p; do handle runner < <(printf '%s\0' "$p"); done <"$list"
  else
    REFIX_PATHS=(); gate_process runner "$list" || true
    if [ "$GATE_MODE" = enforce ]; then for root in $DR_RUNNER_ROOTS; do
      [ -d "$root" ] && [ ! -L "$root" ] && ! denied "$root" || continue
      while IFS= read -r d; do find -P "$d" -mindepth 1 -depth -type d -empty -delete 2>/dev/null; done < <(runner_old_dirs "$root")
      find -P "$root/_work" -mindepth 2 -depth -type d -empty -delete 2>/dev/null
    done; fi
  fi
  rm -f -- "$list"
}

s3_line() {
  local stats used max pct line
  if stats=$("${DR_YC:-yc}" storage bucket stats --name arwox-server-backup --format json 2>/dev/null) && used=$(jq -r '.used_size' <<<"$stats" 2>/dev/null) && max=$(jq -r '.max_size' <<<"$stats" 2>/dev/null) && [[ "$used" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]] && [ "$max" -gt 0 ]; then pct=$((used * 100 / max)); line="s3: $used/$max ${pct}%"; else line='s3: unavailable'; fi
  echo "$line" >>"$DR_LOG"; [ "$MODE" = dry-run ] && echo "$line"
  if [ "$MODE" = run ]; then if [ "${pct:-0}" -ge "${S3_ALERT_PCT:-80}" ]; then maybe_alert s3 "Резервное хранилище заполнено на ${pct}% — нужен атом."; else clear_alert s3; fi; fi
}

# --codex-clean: только класс codex-clean; лок и restic-настройка как у обычного прогона, затем выход.
if [ "$CODEX_CLEAN_ONLY" = 1 ]; then
  if [ "$MODE" = run ]; then
    restic_env
    if ! gate_open; then
      GATE_RC=$RC_GATE_CLOSED
      echo "GATE-REASON $GATE_REASON" >>"$DR_LOG"
    fi
  fi
  if [ "$GATE_RC" -eq 0 ]; then
    cleanup_codex_clean
  fi
  echo "=== $(date '+%F %T') END ===" >>"$DR_LOG"
  exit $GATE_RC
fi

# Тестовый режим (DR_TEST_ONLY=1): только тестовые классы, реальная уборка не выполняется.
if [ "$DR_TEST_ONLY" = 1 ]; then
  REFIX_PATHS=()
  # Незаменимые кандидаты фильтруются так же, как в боевом контуре.
  irrep_tmp=$(mktemp)
  irrep_candidates >"$irrep_tmp"
  if [ "$MODE" = run ]; then
    gate_process test-irreplaceable "$irrep_tmp"
  else
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      age=$(( (now - $(stat -c %Y "$p" 2>/dev/null)) / 86400 ))
      printf '%s\t%sk\t%sd\tirreplaceable\n' "$p" "$kb" "$age"
    done <"$irrep_tmp"
  fi
  rm -f -- "$irrep_tmp"
  # Тот же обработчик, что в production: подсчёт и проверка удаления.
  if [ -n "$DR_TEST_REPLACEABLE_DIR" ] && [ -d "$DR_TEST_REPLACEABLE_DIR" ]; then
    handle replaceable < <(find -P "$DR_TEST_REPLACEABLE_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
  fi
  # Codex-классы: только при явно заданном DR_CODEX_HOME (фикстура теста),
  # иначе прогон тронул бы боевой /root/.codex.
  if [ -n "$CODEX_HOME_EXPLICIT" ]; then
    cleanup_codex
    cleanup_codex_clean
  fi
  [ -n "$RUNNER_EXPLICIT" ] && runner_gate
elif [ "$MODE" != report ]; then
  if [ "$MODE" = run ]; then
    restic_env
    if ! gate_open; then
      GATE_RC=$RC_GATE_CLOSED
      echo "GATE-REASON $GATE_REASON" >>"$DR_LOG"
    fi
  fi
  if [ "$GATE_RC" -eq 0 ]; then
    cleanup_always
    cleanup_tmp
    cleanup_codex
    cleanup_codex_clean
    cleanup_backups
    cleanup_cache
    cleanup_snap
    cleanup_vscode
    cleanup_node
    cleanup_sandbox
    cleanup_migration_dups
    projects_gate
    runner_gate
  fi
fi

if { [ "$MODE" = run ] || [ "$MODE" = dry-run ]; } && { [ "$DR_TEST_ONLY" != 1 ] || [ -n "${DR_YC:-}" ]; }; then s3_line; fi

pct_after=$(use_pct)
used_after=${DR_USED_KB_AFTER:-$(used_kb)}
case "$MODE" in
  dry-run) freed_mb=$(( TOTAL_KB / 1024 )) ;;
  report)  freed_mb=0 ;;
  *)       freed_mb=$(( (used_before - used_after) / 1024 )) ;;
esac

# Журнал зон (spec:090): каждый прогон пишет меры своей зоны; ловит зоны,
# молчащие дольше DR_ZONE_SILENT_H часов. Вызывается в конце run/dry-run.
zones_check() { # end of run/dry-run; журналирует зону claude и сигналит молчащие
  local zones_file="${DR_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}"
  local expected="${DR_ZONES_EXPECTED:-codex}"
  local silent_h="${DR_ZONE_SILENT_H:-26}"
  local used_before_mb=$((used_before / 1024))
  local used_after_mb=$((used_after / 1024))
  mkdir -p "$(dirname "$zones_file")"
  printf '%s\tclaude\t/\tИ\t%s\t%s\t%s\t0\trun-done\n' \
    "$ts" "$used_before_mb" "$used_after_mb" "$freed_mb" >>"$zones_file"
  local zone last_ts ts_epoch age silent
  for zone in $expected; do
    last_ts=$(awk -F'\t' -v z="$zone" '$2==z && $NF=="run-done" {ts=$1} END{print ts}' "$zones_file" 2>/dev/null)
    silent=1
    if [ -n "$last_ts" ]; then
      ts_epoch=$(date -d "$last_ts" +%s 2>/dev/null)
      ts_epoch="${ts_epoch:-$now}"
      age=$(( (now - ts_epoch) / 3600 ))
      if [ "$age" -le "$silent_h" ]; then silent=0; fi
    fi
    if [ "$silent" = 1 ]; then
      journal_row zone silent "$zone" - - - "zone-silent $zone"
      [ "$MODE" = dry-run ] && echo "zone-silent $zone"
      echo "zone-silent $zone" >>"$DR_LOG"
      maybe_alert "zone-silent:$zone" "Зона $zone молчит >${silent_h}ч — нужен агент зоны $zone"
    else
      clear_alert "zone-silent:$zone"
    fi
  done
}

[ "${DR_ZONES_ONLY:-}" = 1 ] && { zones_check; exit 0; }

if [ "$MODE" = run ] || [ "$MODE" = dry-run ]; then
  zones_check
fi

# Состояние exhausted: классы отработали, а занятость после уборки выше 88% (код 3).
if [ "$MODE" = run ] && [ "$pct_after" -gt "$EXHAUSTED_PCT" ]; then
  state_ledger=exhausted
  owner_list=""
  for i in "${!TOP5_DIRS[@]}"; do
    d="${TOP5_DIRS[$i]}"
    if denied_top "$d"; then
      sz=$(du -sm "$d" 2>/dev/null | awk '{print $1}'); sz="${sz:-0}"
      owner_list+=" ${d}=${sz}M"
    fi
  done
  echo "EXHAUSTED-LIST$owner_list" >>"$DR_LOG"
  maybe_alert exhausted "Диск занят на ${pct_after}% даже после уборки — скоро может не хватить места. Безопасные кандидаты уборки исчерпаны. Нужен атом для освобождения места; список — в журнале уборки."
elif [ "$MODE" = run ]; then
  clear_alert exhausted
fi

# Алерты о заполнении диска — только обычный прогон.
if [ "$MODE" = run ]; then
  # dead-man server-backup: последний успешный прогон старше 36 ч (или не было)
  F=$DR_LAST_OK
  last_ok=0
  [ -f "$F" ] && last_ok=$(cat "$F")
  if [ ! -f "$F" ] || [ $((now - last_ok)) -gt 129600 ]; then
    echo "server-backup dead-man: последний успешный прогон старше 36 ч (или не было)" >>"$DR_LOG"
    maybe_alert backup "Резервная копия сервера не делалась больше 36 часов — данные не защищены. Нужен атом."
  else
    clear_alert backup
  fi
fi

GATE_STATUS=not-checked
if [ "$MODE" = run ]; then
  GATE_STATUS=open
  if [ "$GATE_RC" = "$RC_GATE_CLOSED" ]; then
    GATE_STATUS="closed:$GATE_REASON"
  fi
fi

[ "$ALERT_SENT" -gt 0 ] && ALERT_RESULT=sent
[ "$ALERT_FAIL" -gt 0 ] && ALERT_RESULT=failed

df -h / | tail -1 >>"$DR_LOG"

# Итог dry-run: суммарный объём и прогноз занятости (диск при этом не меняется).
if [ "$MODE" = dry-run ]; then
  total_kb=$(df -P / | awk 'NR==2 {print $2}')
  freed_pct=$(awk -v k="$TOTAL_KB" -v t="$total_kb" 'BEGIN{ if (t>0) printf "%.2f", (k/t)*100; else printf "0" }')
  pct_now=$(use_pct)
  forecast=$(awk -v p="$pct_now" -v f="$freed_pct" 'BEGIN{ printf "%.1f", p-f }')
  echo "total candidates: ${TOTAL_KB}K"
  echo "use now: ${pct_now}% ; forecast after cleanup: ${forecast}% (dry-run, disk unchanged)"
fi

top5=$(ledger_top5)
ledger_init
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$ts" "$mode_ledger" "$pct_before" "$pct_after" "$freed_mb" \
  "$state_ledger" "$ALERT_RESULT" "$top5" "$DECLARED_MISSING" >>"$DR_LEDGER"

# Копия журнала в конце прогона.
cp -f "$DR_JOURNAL" "$DR_JOURNAL_COPY" 2>/dev/null || true

# Сводка за прогон — только обычный прогон (один вызов на run).
if [ "$MODE" = run ]; then
  if [ "$freed_mb" -lt 0 ]; then
    _summary="Уборка диска: занято ${pct_after}% (было ${pct_before}%), диск вырос на $(( -freed_mb )) МБ."
  else
    _summary="Уборка диска: занято ${pct_after}% (было ${pct_before}%), освобождено ${freed_mb} МБ."
  fi
  if [ "$GATE_STATUS" != open ]; then
    _summary+=" Уборка приостановлена — нет свежей копии. Нужен атом."
  fi
  _tech="disk-rotate: ${pct_before}% → ${pct_after}%, освобождено ${freed_mb} МБ, зафиксировано ${FIXED_COUNT} (${FIXED_MB} МБ), отложено ${DEFERRED_COUNT}, гейт ${GATE_STATUS}, режим ${GATE_MODE}"
  echo "SUMMARY-LOG-ONLY $_tech" >>"$DR_LOG"
  if [ "$GATE_STATUS" = open ] && [ "${pct_after%%.*}" -lt "$HARD_PCT" ]; then
    clear_alert summary
  fi
  if [ "$ALERT_SENT" -eq 0 ] && { [ "$GATE_STATUS" != open ] || [ "${pct_after%%.*}" -ge "$HARD_PCT" ] 2>/dev/null; }; then
    maybe_alert summary "$_summary"
  fi
fi

echo "=== $(date '+%F %T') END ===" >>"$DR_LOG"

if [ "$GATE_RC" = "$RC_GATE_CLOSED" ]; then
  exit $RC_GATE_CLOSED
fi
if [ "$CLEANUP_FAILED" -ne 0 ]; then
  exit $RC_ALERT_FAILED
fi
if [ "$state_ledger" = exhausted ]; then
  exit $RC_EXHAUSTED
fi
if [ "$MODE" = run ] && [ "$ALERT_FAIL" -gt 0 ]; then
  exit $RC_ALERT_FAILED
fi
exit 0
