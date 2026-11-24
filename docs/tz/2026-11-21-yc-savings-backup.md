# ТЗ 2026-11-21 — Yandex Cloud savings: бэкап (Y1/Y2/Y3)

Ветка `codex/yc-savings-Y123`, репозиторий `/root/workspaces/tools`.
Атом подготовлен как патч-варианты; ветка НЕ запушена, PR НЕ создан (по заданию).

## Что и зачем

Факт до правки: egress S3 = 8.26 ГБ/день = 13.87 ₽/день (53% расходов YC).
Главный потребитель — `restic stats --mode raw-data latest --tag server` при каждом
из 8 прогонов в сутки: raw-data читает все сырые блоки снимка (12.394 GiB, лог:
`[0:02] 100.00% 1/1 snapshots, 262370 blobs, 12.480 GiB`). Результат использовался
только для строки SUMMARY и Telegram «size».

### Y1 — один прогон в сутки, размер без чтения данных
- `ecosystem.config.js`: `cron_restart: '30 */3 * * *'` → `'30 3 * * *'` (8 → 1 прогон/сутки).
- `server-backup.sh`: `restic stats --mode raw-data` удалён; размер берётся из уже
  сохраняемого `$docker_proof/snapshot.json` (`snapshots <id> --json`, поле
  `total_file_size`) через `jq -er '.[0].total_file_size | select(. != null) | tostring'`;
  при недоступности — `unknown`, прогон не падает. Никакого S3-чтения ради размера.
- Slot-логика: `backup_slot=$(( $(date +%s) / 10800 ))` → `/ 86400` (суточный слот),
  иначе единственный ночной прогон блокировался бы как «duplicate invocation».
- mirror-check: `restic ls --recursive` (чтение деревьев) остаётся только в воскресенье
  (`date +%u` = 7); в остальные дни — `restic ls latest` (top-level metadata, без
  рекурсивного чтения) против локального числа `*.git`.

### Y2 — check: метаданные еженедельно, данные ежемесячно
- В 03:30: будни/суббота — `restic check` без флагов (только метаданные).
- Воскресенье не первое вс месяца — тоже только метаданные (раньше был subset n/4).
- 1-е воскресенье месяца (`+%u`=7 и `+%-d`≤7) — `restic check --read-data-subset=1/4`
  (~17 ГБ вместо ~68 ГБ/мес轮换ом 4 частей).
- restore-drill без изменений: 2+1 файла еженедельно (вс 03:30), ~100 МБ проба — 1-е вс месяца.

### Y3 — исключить то, что нечего восстанавливать
- `--exclude '*/.worktrees'` (оба дерева: projects/.worktrees 2.5 GiB/115615 файлов,
  tools/.worktrees 1.7 GiB/31556) — код каждого worktree-коммита уже пушится
  post-commit-хуком/code-sync в GitHub/GitLab, ценность S3-копии нулевая.
- `--exclude /root/workspaces/projects/.agent-work` (1.0 GiB/12314).
- `.tmp` (0.6 GiB/5221): blanket-`--exclude .tmp` терял единственную копию refs
  миграции org→labs (bd dcfg-48s4h.3 open), поэтому применён поимённый список
  excludes мусора `.tmp/*` + paths-массивом явно добавлен
  `/root/workspaces/projects/.tmp/repo-migration-backups` (restic `--include`
  внутри исключённого дерева не срабатывает — надёжнее отдельный path).
- DRILL_FILES (`/root/CLAUDE.md`, `ecosystem.config.js`, git-dirs HEAD) вне исключённых
  деревьев — restore-drill не ломается.
- Retention (`--keep-within 24h --keep-daily 3 --keep-weekly 2`) НЕ менялся.

## Ожидаемая экономия
Egress S3: 8.26 ГБ/день → ~0.6–1 ГБ/день (1 прогон/сутки; stats убран; recursive ls
раз в неделю; read-data раз в месяц). ~12.5–13 ₽/день ≈ 380–400 ₽/мес.
Дополнительно: меньше запросов LIST/GET, быстрее ночной прогон, storage роста нет
(исключения перестают пополнять бакет; старые дубли worktrees сживаются retention'ом).

## Откат
Один коммит на ветке; откат = `git revert <commit>` либо ручное возвращение:
`cron_restart: '30 */3 * * *'`, `backup_slot / 10800`, старый блок `restic stats
--mode raw-data`, прежняя строка mirror-check, прежний Sunday subset n/4, удаление
новых excludes и paths-записи repo-migration-backups. После отката — `pm2 reload
ecosystem.config.js` и удалить файл слота `$STAGE/.server-backup.slot`.

## Тесты
`scripts/tests/server-backup-night-selfcheck.sh` (offline, restic/pm2/curl — заглушки):
policy-only (python unittest): slot=86400 и нет 10800; нет `"$RESTIC" stats`;
cron_restart='30 3 * * *'; excludes .worktrees/.agent-work/.tmp + путь
repo-migration-backups в paths; retention argv без изменений; суточные слоты.
Stub-suite: stats не вызывается (SUMMARY stats=<число> из snapshot.json); будний
mirror-check без --recursive; воскресный — с --recursive; будний check без
read-data-subset; 1-е вс месяца — `check --read-data-subset=1/4`.

## Известный дефект теста (на момент атома)
Проверка `[g2]` («1-е вс месяца → check с --read-data-subset=1/4») падает: env-переменная
`STUB_FORCE_DOM`, экспортированная перед `run_backup`, не попадает в date-заглушку,
потому что `run_backup` собирает собственный env-список и `STUB_FORCE_DOM="${STUB_FORCE_DOM:-8}"`
в него не включён (или включён, но тест перезаписывается параллельным писателем в репозитории —
во время атома файлы ветки несколько раз откатывались другим процессом).
Минимальная правка для зелёного прогона: добавить в env-список `run_backup` строку
`STUB_FORCE_DOM="${STUB_FORCE_DOM:-8}" \` между `STUB_JQ_VALUE=...` и `PATH=...`.
Код продакшн-скрипта от этого не зависит: условие `date +%u`=7 && `date +%-d`≤7 проверено
отдельным offline-экспериментом (см. вывод ниже).
