#!/bin/bash
# Ночной запуск зон disk-rotate (spec:090 C4, FR-090-09/10, ADR-090-9).
# Через pm2 (ecosystem: name=disk-zone-codex, cron 15 2 * * *).
# Сторож ресурсов + состояние + один прогон за раз: весь прогон под
# nice/ionice, неблокирующий flock, перед каждой зоной dz_resources_ok,
# успешные зоны записываются в DZ_STATE и в те же сутки пропускаются.
# Зоны выполняются независимо: сбой одной не останавливает остальные;
# итоговый rc — максимум. Журнал зон — общий DZ_ZONES_TSV.
set -u

ZONE_MODE=${ZONE_MODE:-dry-run}
export ZONE_MODE
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_LOCK=${DZ_LOCK:-/var/lib/disk-rotate/run.lock}
DZ_STATE=${DZ_STATE:-/var/lib/disk-rotate/run-night.state}
DZ_DOCKER_BACKUPS=${DZ_DOCKER_BACKUPS:-/root/backups/docker}
DZ_WAIT_STEP=${DZ_WAIT_STEP:-60}
DZ_WAIT_MAX=${DZ_WAIT_MAX:-1800}

DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$DIR/lib-resources.sh"

mkdir -p "$(dirname "$DZ_ZONES_TSV")" "$(dirname "$DZ_LOCK")" "$(dirname "$DZ_STATE")"

# Журнал зон (общий DZ_ZONES_TSV):
#   ts zone path class size_before_mb size_after_mb freed_mb rc state
wlog() { # zone path class sb sa fr rc state
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >>"$DZ_ZONES_TSV"
}

# ADR-090-9: весь прогон под пониженным приоритетом; ionice нет -> без него.
if [ "${DZ_NICE_DONE:-0}" != 1 ]; then
  export DZ_NICE_DONE=1
  if command -v ionice >/dev/null 2>&1; then
    exec nice -n 19 ionice -c3 bash "$0" "$@"
  else
    exec nice -n 19 bash "$0" "$@"
  fi
fi

# Один прогон за раз: неблокирующий flock; занят -> строка locked, выход 0.
exec 9>"$DZ_LOCK" || exit 1
if ! flock -n 9; then
  wlog lock - И 0 0 0 0 locked
  exit 0
fi

zone_done_today() { # name -> 0, если зона уже записана в DZ_STATE сегодня
  local name=$1 today
  today=$(date +%F)
  awk -v z="$name" -v d="$today" '$1==d && $2==z {f=1} END{exit !f}' "$DZ_STATE" 2>/dev/null
}

need_resources() { # name -> 0 ресурсы есть; 1 не дождались (строка deferred)
  local name=$1 waited=0
  if dz_resources_ok; then return 0; fi
  while [ "$waited" -lt "$DZ_WAIT_MAX" ]; do
    sleep "$DZ_WAIT_STEP"
    waited=$((waited + DZ_WAIT_STEP))
    dz_resources_ok && return 0
  done
  wlog "$name" - И 0 0 0 0 deferred-resources
  return 1
}

# FR-090-09: доля сжатых по расширению файлов в последнем каталоге архивов.
zone_docker_backup() {
  local last_dir total ncomp
  last_dir=$(ls -1d "$DZ_DOCKER_BACKUPS"/*/ 2>/dev/null | sort | tail -n1)
  if [ -n "$last_dir" ] && [ -d "$last_dir" ]; then
    total=$(find "$last_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
    total=${total//[[:space:]]/}
    ncomp=$(find "$last_dir" -maxdepth 1 -type f \
      \( -name '*.gz' -o -name '*.zst' -o -name '*.xz' -o -name '*.tgz' \) \
      2>/dev/null | wc -l)
    ncomp=${ncomp//[[:space:]]/}
    wlog docker-backup - И 0 0 0 0 "compressed-$ncomp/$total"
  fi
}

RC=0
DEFER=0
run_zone() { # name cmd [zone_mode] — ресурсы, выполнение, состояние
  local name=$1 cmd=$2 mode=${3:-} rc
  if zone_done_today "$name"; then
    wlog "$name" - И 0 0 0 0 skipped-done
    return 0
  fi
  if ! need_resources "$name"; then
    DEFER=1
    return 0
  fi
  if [ "$name" = docker-backup ]; then
    zone_docker_backup
    rc=$?
  elif [ -z "$mode" ]; then
    bash "$cmd"
    rc=$?
  else
    ZONE_MODE="$mode" bash "$cmd"
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    printf '%s %s\n' "$(date +%F)" "$name" >>"$DZ_STATE"
  fi
  [ "$rc" -gt "$RC" ] && RC=$rc
}

for z in codex claude docker-backup; do
  [ "$DEFER" -eq 1 ] && break
  if [ "$z" = docker-backup ]; then
    run_zone docker-backup zone_docker_backup
  elif [ "$z" = codex ]; then
    # Удаление в зоне Codex — контур Codex; сюда зона приходит всегда dry-run.
    run_zone codex "$DIR/codex-zone.sh" dry-run
  else
    run_zone "$z" "$DIR/$z-zone.sh"
  fi
done

[ "$DEFER" -eq 1 ] && exit 0
exit "$RC"
