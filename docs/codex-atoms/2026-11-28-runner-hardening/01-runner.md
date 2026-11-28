# Атом: запускатель задаёт writable_roots, не ждёт stdin, исполняет снапшот

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Никаких git-команд, ветка уже создана.

## Проблема (подтверждено сессией 2026-11-28)
1. Запускатель не задаёт `writable_roots` (`grep -c writable_roots bin/codex-role` → `0`), поэтому роль не может писать в Beads/каталог отчётов и отказывается целиком.
2. Процесс читает stdin: без `< /dev/null` `codex exec` ждёт ввода и падает `rc=124`.
3. Файл запускателя правят другие агенты во время исполнения: bash дочитывает изменённые байты → `line 92: -o/--output-last-message: No such file or directory`.

## Контракт (правки строго в bin/codex-role)
1. Вычислить `runner_sha=$(sha256sum "$0" | awk '{print $1}')` и вывести его в строке RUNNER как `runner_sha=…`.
2. Перед запуском скопировать себя в `$out/.runner-$runner_sha.sh` и исполнять **копию** (`bash "$snapshot" …`), чтобы живая правка файла не ломала текущий прогон. Копия удаляется после завершения.
3. Задать явный набор записи, без `secrets`:
   `-c 'sandbox_workspace_write.writable_roots=["<project>","<project>/.agent-work","/root/workspaces/projects/.beads","/root/workspaces/tools/.beads","/root/workspaces/tools/docs","/root/.local/share/opencode/log"]'`
   Значения подставлять через `$project`. Ни при каких условиях не включать `/root/workspaces/secrets`, `/root/.config`, `/root/.codex`.
4. Всегда подавать `</dev/null` в `codex exec`, чтобы процесс не ждал stdin.
5. Таймаут: при `rc=124` печатать строку RUNNER с `timeout=1` (как сейчас) и завершать дочерние процессы: запускать `codex exec` в своей группе (`setsid`) и по таймауту `kill -TERM -<pgid>`, затем `kill -KILL` через 5 с.
6. Существующее поведение не менять: роли, модели, effort, коды выхода, формат артефакта, guard пустого артефакта.

## Проверки (приведи дословно)
- `bash -n bin/codex-role`
- `grep -c 'writable_roots' bin/codex-role` → ≥ 1
- `grep -c 'setsid' bin/codex-role` → ≥ 1 и `grep -c 'dev/null' bin/codex-role` → ≥ 1
- `grep -c 'runner_sha' bin/codex-role` → ≥ 2
- `git diff --stat` (только чтение)

## Запреты
Никаких git-коммитов, пушей, правок других файлов, запуск живых КИНТ/Битрикс24. Не читать `secrets/`.