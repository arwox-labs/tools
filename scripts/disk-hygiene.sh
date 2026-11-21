#!/bin/bash
# Ежедневная гигиена диска. Только безопасные операции: ничего из /root вручную не удаляет.
# Всё, что требует удаления файлов вне docker/apt, только пишет ПРЕДУПРЕЖДЕНИЕ в лог.
LOG=/var/log/disk-hygiene.log
log() { echo "[$(date -Iseconds)] $1" | tee -a "$LOG"; }

log "--- старт, свободно: $(df -h / | awk 'NR==2{print $4}')"

docker container prune -f  >/dev/null 2>&1
docker image prune -f      >/dev/null 2>&1
docker builder prune -f    >/dev/null 2>&1
docker volume prune -f     >/dev/null 2>&1
log "docker: контейнеры/образы/сборка/тома — очищены"

apt-get clean 2>/dev/null
log "apt: кэш пакетов очищен"

journalctl --vacuum-size=200M >/dev/null 2>&1
log "journal: оставлено не более 200 МБ"

if /usr/local/sbin/db-hygiene.sh >/dev/null 2>&1; then
  maintenance_rc=0
  log "базы агента: обслуживание прошло"
else
  maintenance_rc=$?
  log "ПРЕДУПРЕЖДЕНИЕ: обслуживание баз агента завершилось с rc=$maintenance_rc"
fi

for p in /root/backups/logsweep-*; do
  [ -d "$p" ] || continue
  log "ПРЕДУПРЕЖДЕНИЕ: $p = $(du -sh "$p" 2>/dev/null | cut -f1) — архив логов, не чистится, нет allowlist"
done

log "--- готово, свободно: $(df -h / | awk 'NR==2{print $4}')"
exit "$maintenance_rc"
