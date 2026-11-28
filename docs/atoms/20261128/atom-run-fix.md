# Атом: исправить порядок ворот в atom-run

Файл: `/root/workspaces/tools/bin/atom-run` — единственный разрешённый.

Факт (проверено чтением файла): проверка `git diff` и `expect` стоит ДО запуска `cmd`, поэтому на любом атоме без уже готового диффа скрипт печатает `FAILED:no-diff` и команду не запускает.

Правка: переставить блоки в правильный порядок:
1. `todo/files/expect/cmd` — разбор и валидация (как есть).
2. `git status --porcelain -- files` → `FAILED:dirty-file`.
3. `timeout 900 bash -c "$command"` → `FAILED:cmd` при ненулевом коде.
4. `git diff -- files` → пуст → `FAILED:no-diff`; не совпал с `expect` (grep -Eq) → `FAILED:no-marker`.
5. `gate` (если задан) → `FAILED:gate`.
6. `ATOMRUN verdict=PASS …`.

Проверки (выполнить, процитировать вывод):
- `bash -n /root/workspaces/tools/bin/atom-run` → rc=0
- атом-пустышка `/root/workspaces/tools/docs/atoms/20261128/probe.md` (todo: probe-1 / files: README.md / expect: zzz-never / cmd: true) → `ATOMRUN verdict=FAILED:no-diff …`, rc=1
- повтор той же команды → снова `FAILED:no-diff`, rc=1

Запреты: не менять другие файлы, не запускать codex, не писать вне `/root/workspaces/tools/bin/`.