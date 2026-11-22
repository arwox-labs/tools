#!/usr/bin/env bash
# Ежедневный restic-бэкап критичных данных сервера.
set -u

RESTIC=${RESTIC:-/root/workspaces/tools/bin/restic}
S3_ENV=${S3_ENV:-/root/workspaces/secrets/yandex-s3.env}
PW_ENV=${PW_ENV:-/root/workspaces/secrets/restic.env}
LOG=${LOG:-/root/workspaces/system/tools/scripts/logs/server-backup.log}
run_hour=${RUN_HOUR:-$(date +%H)}
NOTIFY_ENV=${NOTIFY_ENV:-/root/workspaces/secrets/services/pm2-notify.env}
STAGE=${STAGE:-/root/workspaces/system/tools/scripts/data/server-backup-stage}
LAST_OK=${LAST_OK:-/root/workspaces/system/tools/scripts/data/server-backup.last-ok}
ALERT_PENDING=${ALERT_PENDING:-/root/workspaces/system/tools/scripts/data/server-backup.alert-pending}
BK_MIRROR_DIR=${BK_MIRROR_DIR:-/home/gitmirror/repos}

# Ночной бэкап — максимально низкий приоритет (nice 19 + ionice idle).
NICE_PREFIX=(nice -n 19)
if command -v ionice >/dev/null 2>&1; then
  NICE_PREFIX=(nice -n 19 ionice -c3)
fi
renice --priority 19 -p $$ >/dev/null 2>&1 || true
printf '[%s] nice=%s\n' "$(date '+%F %T')" "$(ps -o ni= -p $$ | tr -d '[:space:]')" >>"$LOG"

if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt $((5 * 1024 * 1024)) ]; then
  mv -f "$LOG" "$LOG.1"
fi
mkdir -p "$(dirname "$LOG")" "$STAGE"
log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

send_telegram() { # text
  local token="" chat="" rc
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    log "telegram skipped (no token/chat): $1"
    return 1
  fi
  curl -sf --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then log "telegram sent"; else log "telegram send failed rc=$rc"; fi
  return "$rc"
}

run_step() { # name command...
  local name="$1" rc
  shift
  timeout -k 30s 3600 "$@" >>"$LOG" 2>&1
  rc=$?
  log "$name rc=$rc"
  return "$rc"
}

stage_manifests() {
  mkdir -p "$STAGE/manifests"
  dpkg --get-selections >"$STAGE/manifests/dpkg-selections.txt" 2>/dev/null || :
  apt-mark showmanual >"$STAGE/manifests/apt-manual.txt" 2>/dev/null || :
  pip3 freeze >"$STAGE/manifests/pip-freeze.txt" 2>/dev/null || :
  pipx list --json >"$STAGE/manifests/pipx.json" 2>/dev/null || :
  uv tool list >"$STAGE/manifests/uv-tools.txt" 2>/dev/null || :
  NPM=$(ls -d /root/.nvm/versions/node/*/bin/npm 2>/dev/null | sort -V | tail -1)
  "$NPM" ls -g --depth=0 >"$STAGE/manifests/npm-global.txt" 2>/dev/null || :
  snap list >"$STAGE/manifests/snap.txt" 2>/dev/null || :
  docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' >"$STAGE/manifests/docker-images.txt" 2>/dev/null || :
  ls -la /usr/local/bin >"$STAGE/manifests/usr-local-bin.txt" 2>/dev/null || :
  systemctl list-unit-files --state=enabled >"$STAGE/manifests/systemd-enabled.txt" 2>/dev/null || :
  { uname -a; lsb_release -a; } >"$STAGE/manifests/os.txt" 2>/dev/null || :
  log "manifests: $(ls "$STAGE/manifests" | wc -l) файлов"
}

stage_host_dumps() {
  local pg=skip redis=skip grafana=skip integrity
  mkdir -p "$STAGE/host-db"

  if systemctl is-active --quiet 'postgresql@16-main'; then
    su - postgres -c pg_dumpall 2>>"$LOG" | gzip >"$STAGE/host-db/pg_dumpall.sql.gz"
    [ -f "$STAGE/host-db/pg_dumpall.sql.gz" ] && [ "$(stat -c%s "$STAGE/host-db/pg_dumpall.sql.gz")" -ge 100 ] && pg=ok
  else
    log "WARNING: postgresql@16-main не запущен"
  fi
  [ -f "$STAGE/host-db/pg_dumpall.sql.gz" ] && [ "$(stat -c%s "$STAGE/host-db/pg_dumpall.sql.gz")" -ge 100 ] || log "WARNING: host-db pg_dumpall.sql.gz пустой"

  if systemctl is-active --quiet redis-server; then
    redis-cli --rdb "$STAGE/host-db/redis-dump.rdb" >>"$LOG" 2>&1 || cp /var/lib/redis/dump.rdb "$STAGE/host-db/redis-dump.rdb"
    [ -f "$STAGE/host-db/redis-dump.rdb" ] && [ "$(stat -c%s "$STAGE/host-db/redis-dump.rdb")" -ge 100 ] && redis=ok
  else
    log "WARNING: redis-server не запущен"
  fi
  [ -f "$STAGE/host-db/redis-dump.rdb" ] && [ "$(stat -c%s "$STAGE/host-db/redis-dump.rdb")" -ge 100 ] || log "WARNING: host-db redis-dump.rdb пустой"

  if [ -f /var/lib/grafana/grafana.db ]; then
    sqlite3 /var/lib/grafana/grafana.db ".backup '$STAGE/host-db/grafana.db'" >>"$LOG" 2>&1
    integrity=$(sqlite3 "$STAGE/host-db/grafana.db" "PRAGMA integrity_check" 2>>"$LOG")
    if [ "$integrity" = ok ]; then
      [ -f "$STAGE/host-db/grafana.db" ] && [ "$(stat -c%s "$STAGE/host-db/grafana.db")" -ge 100 ] && grafana=ok
    else
      log "WARNING: grafana.db integrity_check=$integrity"
    fi
  else
    log "WARNING: grafana.db отсутствует"
  fi
  [ -f "$STAGE/host-db/grafana.db" ] && [ "$(stat -c%s "$STAGE/host-db/grafana.db")" -ge 100 ] || log "WARNING: host-db grafana.db пустой"
  log "host-db: pg=$pg redis=$redis grafana=$grafana"
}

fail() { # step rc [exit]
  local step="$1" rc="$2" code="${3:-1}"
  local alert="🚨 server-backup: ${step} rc=${rc}, лог ${LOG}"
  if ! send_telegram "$alert"; then
    printf '%s\n' "$alert" >"$ALERT_PENDING"
    log "alert queued"
  fi
  exit "$code"
}

drill() { # проба: каталог ~100 МБ из снимка server в mktemp, restic сверяет со снимком
  local dir=${BK_DRILL_DIR:-/root/workspaces/tools/bin} d rc mb
  d=$(mktemp -d /tmp/restic-drill.XXXXXX) || fail drill 1
  run_step drill "${NICE_PREFIX[@]}" "$RESTIC" restore latest --tag server --target "$d" --include "$dir" --verify --retry-lock 30m
  rc=$?
  mb=$(du -sm --apparent-size "$d" | cut -f1)
  log "restore-drill rc=$rc size=${mb}M dir=$dir"
  [ "$rc" -eq 0 ] && [ ! -d "$d$dir" ] && rc=2
  [ "$rc" -eq 0 ] && [ "$mb" -lt "${BK_DRILL_MIN_MB:-50}" ] && rc=3
  rm -rf "$d"
  [ "$rc" -eq 0 ] || fail drill "$rc"
}

# Capture only flat, regular compressed archives. Recheck before any deletion.
docker_manifest() {
  local dir="$1" file size hash count=0
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  for file in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$file" ] || [ -L "$file" ] || continue
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    [[ ${file##*/} =~ ^[A-Za-z0-9_.-]+\.gz$ ]] || return 1
    size=$(stat -c%s -- "$file") || return 1
    hash=$(sha256sum -- "$file") || return 1
    printf '%s\t%s\t%s\n' "${file##*/}" "$size" "${hash%% *}"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ]
}

docker_recovery_and_retention() {
  local snapshot="$1" proof="$2" dir name target before after restored count=0 verified=0 kept
  local gate=/root/.codex/DELETE-APPROVED.json cleanup_rc=0 approved=0 required available mode entry
  kept=${docker_snapshots[${#docker_snapshots[@]}-1]}
  mkdir -p "$STAGE/docker-receipts" || return 1
  # Verify all directories before deleting any: a partial drill grants no cleanup.
  for dir in "${docker_snapshots[@]}"; do
    name=${dir##*/}
    before="$proof/$name.before"
    after="$proof/$name.after"
    restored="$proof/$name.restored"
    required=$(awk -F '\t' '{sum += $2} END {printf "%.0f", sum + 268435456}' "$before") || return 1
    available=$(df -B1 --output=avail /tmp | tail -1 | tr -d '[:space:]') || return 1
    [[ $available =~ ^[0-9]+$ && $required =~ ^[0-9]+$ ]] || return 1
    if [ "$available" -lt "$required" ]; then
      log "docker-recovery insufficient space: required=$required available=$available; originals retained"
      return 1
    fi
    target=$(mktemp -d /tmp/restic-docker-drill.XXXXXX) || return 1
    if ! run_step docker-restore "${NICE_PREFIX[@]}" "$RESTIC" restore "$snapshot" \
      --target "$target" --include "$dir" --verify --retry-lock 30m; then
      rm -rf -- "$target"
      return 1
    fi
    if ! docker_manifest "$target$dir" >"$restored" || ! docker_manifest "$dir" >"$after" \
      || ! cmp -s "$before" "$after" || ! cmp -s "$before" "$restored"; then
      log "docker-recovery mismatch: $name; originals retained"
      rm -rf -- "$target"
      return 1
    fi
    count=$(wc -l <"$before")
    verified=$((verified + count))
    rm -rf -- "$target"
    log "docker-recovery snapshot=$snapshot directory=$name matching=$count missing=0 mismatch=0"
    cp -- "$before" "$STAGE/docker-receipts/$name.sha256.tsv" || return 1
    printf '%s\n' "$snapshot" >"$STAGE/docker-receipts/$name.snapshot" || return 1
  done
  log "docker-recovery TOTAL snapshot=$snapshot matching=$verified missing=0 mismatch=0"
  [ "${#docker_snapshots[@]}" -gt 1 ] || return 0
  # The owner-controlled host gate is never created or changed by this script.
  # Accepted gate contract: paths is an array of exact canonical directory paths.
  if [ -f "$gate" ] && [ ! -L "$gate" ] && [ "$(stat -c%u "$gate")" = 0 ]; then
    approved=1
    # Reject extended ACLs as well as group/world-write access; fail closed.
    for entry in /root /root/.codex "$gate"; do
      [ ! -L "$entry" ] && [ "$(stat -c%u "$entry")" = 0 ] || approved=0
      mode=$(stat -c%a -- "$entry") || return 1
      [ "$((8#$mode & 0022))" -eq 0 ] || approved=0
      python3 - "$entry" <<'PY' || approved=0
import os, sys
try:
    attrs = os.listxattr(sys.argv[1], follow_symlinks=False)
    sys.exit(any(a in attrs for a in ("system.posix_acl_access", "system.posix_acl_default")))
except OSError:
    sys.exit(1)
PY
    done
    for dir in "${docker_snapshots[@]}"; do
      [ "$dir" = "$kept" ] && continue
      jq -e --arg path "$dir" '.paths | type == "array" and index($path) != null' "$gate" >/dev/null 2>&1 \
        || approved=0
    done
  fi
  if [ "$approved" -ne 1 ]; then
    log "docker-retention refused: exact owner-controlled DELETE-APPROVED.json paths absent; originals retained"
    return 4
  fi
  for dir in "${docker_snapshots[@]}"; do
    [ "$dir" = "$kept" ] && continue
    [ "$(realpath -e -- "$dir")" = "$dir" ] && [ ! -L "$dir" ] || return 1
    [[ $dir =~ ^/root/backups/docker/20[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9]{2,6}$ ]] || return 1
    docker_manifest "$dir" >"$proof/delete-current" || return 1
    cmp -s "$proof/${dir##*/}.before" "$proof/delete-current" || return 1
    if ! rm -r --one-file-system -- "$dir"; then
      cleanup_rc=1
      log "docker-retention delete failed: ${dir##*/}"
    else
      log "docker-retention deleted=${dir##*/} snapshot=$snapshot kept=${kept##*/}"
    fi
  done
  return "$cleanup_rc"
}

set -a
# shellcheck disable=SC1090
source "$S3_ENV"
set +a

backup_docker_images() {
  local image_list id size avail need reserve rc short_snapshot snapshot candidate receipt result
  local ok=0 failed=0 count=0
  local -a image_ids=()
  receipt="$STAGE/docker-images.receipt"
  result="$STAGE/docker-images-result.jsonl"
  reserve=${BK_IMAGE_RESERVE_BYTES:-3221225472}
  [[ $reserve =~ ^[0-9]+$ ]] || { log "docker-images invalid reserve=$reserve"; return 1; }
  image_list=$(docker image ls --no-trunc --quiet) || { log "docker-images inventory failed"; return 1; }
  [ -n "$image_list" ] || { log "docker-images inventory empty"; return 1; }
  mapfile -t image_ids < <(printf '%s\n' "$image_list" | LC_ALL=C sort -u)
  count=${#image_ids[@]}
  for id in "${image_ids[@]}"; do
    [[ $id =~ ^sha256:[0-9a-f]{64}$ ]] || { log "docker-images invalid id=$id"; return 1; }
  done

  for id in "${image_ids[@]}"; do
    snapshot=''
    if [ -f "$receipt" ]; then
      while read -r receipt_id candidate; do
        if [ "$receipt_id" = "$id" ] && [[ $candidate =~ ^[0-9a-f]{64}$ ]] \
          && "$RESTIC" cat snapshot "$candidate" >/dev/null 2>>"$LOG"; then
          snapshot=$candidate
          break
        fi
      done <"$receipt"
    fi
    if [ -n "$snapshot" ]; then
      ok=$((ok + 1))
      continue
    fi
    size=$(docker image inspect -f '{{.Size}}' "$id") || { log "docker-images inspect failed id=$id"; failed=$((failed + 1)); continue; }
    avail=$(df -B1 --output=avail /var/lib/docker | tail -1 | tr -d '[:space:]') || { log "docker-images df failed id=$id"; failed=$((failed + 1)); continue; }
    if ! [[ $size =~ ^[0-9]+$ && $avail =~ ^[0-9]+$ ]]; then
      log "docker-images invalid size/avail id=$id size=$size avail=$avail"
      failed=$((failed + 1))
      continue
    fi
    need=$((size + reserve))
    if [ "$avail" -lt "$need" ]; then
      log "docker-images skip $id low-space need=$need avail=$avail"
      failed=$((failed + 1))
      continue
    fi
    timeout -k 30s 3600 "${NICE_PREFIX[@]}" "$RESTIC" backup --json --tag docker-images \
      --stdin-from-command --stdin-filename "docker-image-${id#sha256:}.tar" \
      --compression auto --limit-upload "${BK_LIMIT_UPLOAD:-5120}" --retry-lock 30m -- \
      env -u AWS_SECRET_ACCESS_KEY -u AWS_ACCESS_KEY_ID -u RESTIC_PASSWORD \
      docker image save "$id" >"$result" 2>>"$LOG"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      log "docker-images backup failed id=$id rc=$rc"
      failed=$((failed + 1))
      continue
    fi
    short_snapshot=$(jq -er 'select(.message_type == "summary") | .snapshot_id | select(test("^[0-9a-f]{8,64}$"))' "$result") || {
      log "docker-images snapshot receipt failed id=$id"; failed=$((failed + 1)); continue;
    }
    timeout -k 30s 120 "${NICE_PREFIX[@]}" "$RESTIC" snapshots --tag docker-images --json \
      >"$result" 2>>"$LOG" || { log "docker-images snapshots failed id=$id"; failed=$((failed + 1)); continue; }
    snapshot=$(jq -er --arg prefix "$short_snapshot" '[.[] | .id | select(startswith($prefix))] | if length == 1 then .[0] else empty end | select(test("^[0-9a-f]{64}$"))' "$result") || {
      log "docker-images snapshot resolve failed id=$id"; failed=$((failed + 1)); continue;
    }
    printf '%s %s\n' "$id" "$snapshot" >>"$receipt" || { log "docker-images receipt write failed id=$id"; failed=$((failed + 1)); continue; }
    ok=$((ok + 1))
  done
  run_step unlock "${NICE_PREFIX[@]}" "$RESTIC" unlock --retry-lock 30m
  run_step docker-images-retention "${NICE_PREFIX[@]}" "$RESTIC" forget --tag docker-images \
    --group-by host,paths --keep-last 1 --retry-lock 30m || failed=$((failed + 1))
  log "docker-images ok=$ok failed=$failed count=$count"
  [ "$failed" -eq 0 ]
}

if [ ! -f "$PW_ENV" ]; then
  (umask 077; printf 'RESTIC_PASSWORD=%s\n' "$(openssl rand -hex 32)" >"$PW_ENV")
  chmod 600 "$PW_ENV"
  log "restic.env создан — скопировать пароль в менеджер паролей владельца"
fi
set -a
# shellcheck disable=SC1090
source "$PW_ENV"
set +a

[ "${1:-}" = --drill ] && { drill; exit 0; }
if [ "${1:-}" = --images-only ]; then
  backup_docker_images || fail docker-images "$?"
  exit 0
fi

exec 9>"$STAGE/.server-backup.lock" || fail lock 1
if ! flock -n 9; then
  log "backup already running; duplicate invocation skipped"
  exit 0
fi
backup_slot=$(( $(date +%s) / 86400 ))
slot_file="$STAGE/.server-backup.slot"
if [ -f "$slot_file" ]; then
  read -r previous_slot previous_status <"$slot_file" || fail slot-state 1
  [[ $previous_slot =~ ^[0-9]+$ && $previous_status =~ ^(attempt|ok)$ ]] || fail slot-state 1
  if [ "$previous_slot" -ge "$backup_slot" ]; then
    log "backup slot=$previous_slot status=$previous_status; duplicate invocation skipped"
    [ "$previous_status" = ok ] && exit 0
    fail duplicate-slot 75
  fi
fi
# Record before external effects: an interrupted attempt must not run twice.
printf '%s attempt\n' "$backup_slot" >"$slot_file.next" && mv -f -- "$slot_file.next" "$slot_file" || fail slot-state 1

# Снимок cron и свежий docker-бэкап.
crontab -l >"$STAGE/crontab-root.txt" 2>>"$LOG" || :
stage_manifests
stage_host_dumps

curl -s --max-time 10 -o /dev/null https://storage.yandexcloud.net
preflight_rc=$?
if [ "$preflight_rc" -ne 0 ]; then
  log "preflight: S3 недоступен rc=$preflight_rc"
  fail preflight "$preflight_rc" 3
fi

timeout 3600 "${NICE_PREFIX[@]}" "$RESTIC" cat config --retry-lock 30m >/dev/null 2>&1
config_rc=$?
log "config rc=$config_rc"
if [ "$config_rc" -ne 0 ]; then
  run_step init "${NICE_PREFIX[@]}" "$RESTIC" init --retry-lock 30m
  init_rc=$?
  if [ "$init_rc" -ne 0 ]; then
    fail init "$init_rc" 2
  fi
else
  config_rc=0
fi

# One scheduler: produce Docker dumps before the same server snapshot.
run_step docker-stage bash "${BK_DOCKER_SCRIPT:-/root/workspaces/tools/scripts/pm2/docker-backup.sh}"
docker_rc=$?
# Preserve the ordinary server backup even if fresh Docker staging fails.
[ "$docker_rc" -eq 0 ] || log "Docker staging failed; uploading prior DB dumps"
backup_docker_images
images_rc=$?
[ "$images_rc" -eq 0 ] || log "Docker images failed; ordinary server upload continues"

# Hold the producer's existing lock through inventory, upload, recovery and cleanup.
exec 8>/root/backups/docker/.docker-backup.lock || fail docker-lock 1
flock -w 360 8 || fail docker-lock 1
docker_proof=$(mktemp -d /tmp/restic-docker-proof.XXXXXX) || fail docker-inventory 1
trap 'rm -rf -- "$docker_proof"' EXIT

paths=(
  /root/workspaces /root/.claude /root/.config
  /root/.pm2 /root/.codex
  /root/.gemini /root/.kimi /root/.kimi-code /root/.mcp-auth /root/.clasprc.json /root/.twcrc /root/.railway
  /root/.northflank /root/.copilot /root/.azure-devops /root/.git-templates /root/.holmes /root/.semgrep /root/.vim
  /root/.dbclient /root/bin /root/netplan-backup
  /root/CLAUDE.md /root/AGENTS.md /root/GEMINI.md /etc /data/minio
  /root/nginx-proxy-manager /var/lib/docker/volumes "$STAGE"
  /root/.claude.json /root/.bashrc /root/.profile /root/.gitconfig /root/.gitignore_global
  /root/.mc /root/.docker /root/.gnupg /root/.beads /root/.dolt /root/.opencode
  /root/.agents /root/ecosystem.config.js /var/www /opt/actions-runner/.runner
  /root/actions-runner-2/.runner /home/claude /home/gitmirror/repos /home/gitmirror/archived-repos
  # Y3: единственная копия refs миграции org→labs (bd dcfg-48s4h.3) — вне исключённого .tmp.
  /root/workspaces/projects/.tmp/repo-migration-backups
)
paths+=(/root/.tmux*)
[ -d /var/lib/docker/volumes ] && [ ! -L /var/lib/docker/volumes ] || fail docker-inventory 1
# Selected writable container layers are not included by the Docker volume path.
docker_upper_dirs=()
for container in hiddify-manager-hiddify-1 proxy-manager-app-1 3x-ui; do
  upper_dir=$(docker inspect -f '{{index .GraphDriver.Data "UpperDir"}}' "$container" 2>>"$LOG") \
    || fail docker-inventory 1
  [[ $upper_dir == /var/lib/docker/overlay2/*/diff ]] && [ -d "$upper_dir" ] && [ ! -L "$upper_dir" ] \
    || fail docker-inventory 1
  paths+=("$upper_dir")
  docker_upper_dirs+=("$upper_dir")
  log "docker-layer container=$container path=$upper_dir"
done
# The stable DB stage replaces growing dated tar archives; old archives stay untouched.
docker_snapshots=()
docker_snapshot=/root/backups/docker/current
if [ -d "$docker_snapshot" ] && [ ! -L "$docker_snapshot" ] \
  && compgen -G "$docker_snapshot/*.gz" >/dev/null; then
  docker_snapshots+=("$docker_snapshot")
fi
if [ "${#docker_snapshots[@]}" -gt 0 ]; then
  paths+=("${docker_snapshots[@]}")
  for docker_snapshot in "${docker_snapshots[@]}"; do
    docker_manifest "$docker_snapshot" >"$docker_proof/${docker_snapshot##*/}.before" \
      || fail docker-inventory 1
  done
else
  log "Docker DB dump inventory empty; direct Docker paths still included"
fi

backup_paths=()
for path in "${paths[@]}"; do
  [ -e "$path" ] && backup_paths+=("$path")
done

run_step unlock "${NICE_PREFIX[@]}" "$RESTIC" unlock --retry-lock 30m

backup_json="$docker_proof/backup.jsonl"
timeout -k 30s 3600 "${NICE_PREFIX[@]}" "$RESTIC" backup --json --tag server --group-by host,tags --one-file-system \
  --exclude-caches --exclude node_modules --exclude .venv --exclude venv \
  --exclude __pycache__ --exclude .cache --exclude .repowise \
  --exclude '*.pyc' --exclude /root/workspaces/system/archives --exclude /root/.pm2/logs \
  --exclude /root/.claude/file-history --exclude /root/.claude/paste-cache \
  --exclude /root/.claude/projects --exclude /root/.claude/jobs \
  --exclude /root/.codex/sessions --exclude /root/.codex/archived_sessions --exclude /root/.codex/.tmp \
  --exclude /root/.codex/tmp --exclude /root/.codex/packages --exclude /root/.codex/cache \
  --exclude /root/.codex/mcp-runners --exclude /root/.codex/generated_images \
  --exclude '/root/.codex/thread_history_*.sqlite*' \
  --exclude '/root/.codex/logs_*.sqlite*' \
  --exclude '/root/.codex/state_*.sqlite*' \
  --exclude /root/.gemini/tmp --exclude /root/.kimi-code/bin --exclude /root/.kimi-code/cache \
  --exclude /root/.kimi-code/logs --exclude /root/.kimi-code/sessions --exclude /root/.kimi-code/search-index \
  --exclude '*/.worktrees' --exclude /root/workspaces/projects/.agent-work \
  --exclude /root/workspaces/projects/.tmp/hh-clean \
  --exclude /root/workspaces/projects/.tmp/cs-check \
  --exclude /root/workspaces/projects/.tmp/cs-clean \
  --exclude /root/workspaces/projects/.tmp/hh-clean-work \
  --exclude /root/workspaces/projects/.tmp/mplan-docs \
  --exclude /root/workspaces/projects/.tmp/sanitize-dev \
  --exclude '/root/workspaces/projects/.tmp/*.log' \
  --exclude '/root/workspaces/projects/.tmp/dump_session.py' \
  --exclude '/root/workspaces/projects/.tmp/gitlinks.txt' \
  --exclude '/root/workspaces/projects/.tmp/live.txt' \
  --exclude '/root/workspaces/projects/.tmp/mirror.txt' \
  --exclude '/root/workspaces/projects/.tmp/r1.tsv' \
  --exclude '/root/workspaces/projects/.tmp/r2.tsv' \
  --exclude '/root/workspaces/projects/.tmp/sess-s1.txt' \
  --exclude '/root/workspaces/projects/.tmp/sess-s2.txt' \
  --exclude '/root/workspaces/projects/.tmp/sess-s3.txt' \
  --exclude '/root/workspaces/projects/.tmp/sess-s4.txt' \
  --exclude '/root/workspaces/projects/.tmp/sess-s5.txt' \
  --exclude '/root/workspaces/projects/.tmp/t-new.txt' \
  --exclude '/root/workspaces/projects/.tmp/t-old.txt' \
  --exclude '/root/workspaces/projects/.tmp/opencode-jsonc-20261104.snapshot' \
  --exclude '/root/workspaces/projects/.tmp/opencode-jsonc-20261104b.snapshot' \
  --read-concurrency 1 --limit-upload "${BK_LIMIT_UPLOAD:-5120}" --retry-lock 30m \
  "${backup_paths[@]}" >"$backup_json" 2>>"$LOG"
backup_rc=$?
log "backup rc=$backup_rc"
case "$backup_rc" in 0) ;; *) fail backup "$backup_rc" ;; esac
snapshot_id=$(jq -er 'select(.message_type == "summary") | .snapshot_id | select(test("^[0-9a-f]{8,64}$"))' "$backup_json") \
  || fail snapshot-receipt 1
timeout -k 30s 3600 "${NICE_PREFIX[@]}" "$RESTIC" snapshots "$snapshot_id" --json --retry-lock 30m \
  >"$docker_proof/snapshot.json" 2>>"$LOG" || fail snapshot-receipt 1
snapshot_id=$(jq -er 'select(length == 1) | .[0].id | select(test("^[0-9a-f]{64}$"))' "$docker_proof/snapshot.json") \
  || fail snapshot-receipt 1
for path in /var/lib/docker/volumes "${docker_upper_dirs[@]}"; do
  jq -e --arg path "$path" '.[0].paths | index($path) != null' "$docker_proof/snapshot.json" >/dev/null \
    || fail snapshot-receipt 1
  log "snapshot-path verified snapshot=$snapshot_id path=$path"
done
log "backup snapshot=$snapshot_id"

# Y1: сверка зеркала. Воскресенье — полный `restic ls --recursive` по дереву S3;
# остальные дни — число репозиториев из top-level metadata последнего снимка (без чтения данных).
mirror_local=$(ls -d "$BK_MIRROR_DIR"/*.git 2>/dev/null | wc -l)
if [ "$(date +%u)" = 7 ]; then
  mirror_s3=$(timeout 3600 "${NICE_PREFIX[@]}" "$RESTIC" ls --recursive latest --tag server "$BK_MIRROR_DIR" 2>>"$LOG" \
    | grep -Ec '(\.git)?/HEAD$')
else
  mirror_s3=$(timeout 3600 "${NICE_PREFIX[@]}" "$RESTIC" ls latest --tag server "$BK_MIRROR_DIR" 2>>"$LOG" \
    | grep -cE '/[^/]+\.git/?$')
fi
log "mirror-check s3=$mirror_s3 local=$mirror_local"
if [ "$mirror_s3" -lt "$mirror_local" ]; then
  fail mirror-check "$((mirror_local - mirror_s3))"
fi

forget_args=()
[ "$run_hour" = 03 ] && forget_args=(--prune --max-repack-size 512M)
run_step forget "${NICE_PREFIX[@]}" "$RESTIC" forget --tag server --group-by host,tags --keep-within 24h --keep-daily 3 --keep-weekly 2 "${forget_args[@]}" --retry-lock 30m
forget_rc=$?
case "$forget_rc" in 0|3) ;; *) fail forget "$forget_rc" ;; esac

check_rc=skip
# Y2b (owner 21.11): метаданные ЕЖЕНЕДЕЛЬНО (вс 03:30); данные 1/4 — 1-е вс месяца.
if [ "$run_hour" = 03 ] && [ "$(date +%u)" = 7 ]; then
  check_args=()
  if [ "$(date +%-d)" -le 7 ]; then
    check_args=(--read-data-subset=1/4)
  fi
  run_step check "${NICE_PREFIX[@]}" "$RESTIC" check "${check_args[@]}" --retry-lock 30m
  check_rc=$?
  case "$check_rc" in 0|3) ;; *) fail check "$check_rc" ;; esac
else
  log "check=skip (не вс 03:30)"
fi
if [ "$(date +%u)" = 7 ] && [ "$run_hour" = 03 ]; then
  DRILL=/tmp/restic-drill
  DRILL_FILES=(/root/CLAUDE.md /root/workspaces/tools/ecosystem.config.js /root/workspaces/git-dirs/agent-contour.git/HEAD)
  drill_includes=()
  for drill_file in "${DRILL_FILES[@]}"; do drill_includes+=(--include "$drill_file"); done
  rm -rf "$DRILL"
  run_step restore "${NICE_PREFIX[@]}" "$RESTIC" restore latest --tag server --target "$DRILL" \
    "${drill_includes[@]}" --retry-lock 30m
  restore_rc=$?
  if [ "$restore_rc" -ne 0 ]; then
    rm -rf "$DRILL"
    fail restore "$restore_rc"
  fi
  for drill_file in "${DRILL_FILES[@]}"; do
    if ! cmp -s "$DRILL$drill_file" "$drill_file"; then
      log "restore-drill FAIL $drill_file"
      rm -rf "$DRILL"
      fail restore 1
    fi
  done
  log "restore-drill ok (${#DRILL_FILES[@]} files)"
  rm -rf "$DRILL"
  [ "$(date +%-d)" -le 7 ] && drill
fi

# Y1: размер снимка берём из summary в backup.jsonl, без `restic stats --mode raw-data`.
stats_size=$(jq -er 'select(.message_type == "summary") | .total_bytes_processed | select(. != null) | tostring' "$backup_json" 2>>"$LOG") \
  || { log "stats size unavailable"; stats_size=unknown; }
log "SUMMARY docker_rc=$docker_rc images_rc=$images_rc backup_rc=$backup_rc forget_rc=$forget_rc check_rc=$check_rc stats=${stats_size:-unknown}"
[ "$docker_rc" -eq 0 ] || fail docker-stage "$docker_rc"
docker_retention_rc=0
if [ "${#docker_snapshots[@]}" -gt 0 ]; then
  docker_recovery_and_retention "$snapshot_id" "$docker_proof"
  docker_retention_rc=$?
fi
log "docker-retention rc=$docker_retention_rc"
[ "$docker_retention_rc" -eq 0 ] || fail docker-retention "$docker_retention_rc"
[ "$images_rc" -eq 0 ] || fail docker-images "$images_rc"
date +%s >"$LAST_OK" || fail last-ok 1
printf '%s ok\n' "$backup_slot" >"$slot_file.next" && mv -f -- "$slot_file.next" "$slot_file" || fail slot-state 1
if [ "$(date +%u)" = 7 ] && [ "$run_hour" = 03 ]; then
  send_telegram "✅ server-backup: неделя ок, snapshot latest, size ${stats_size:-unknown}, drill ok"
fi

exit 0
