# Атом: atom-run — обёртка запуска атома с механическими воротами

Цель: создать ровно один файл `/root/workspaces/tools/bin/atom-run` (bash, chmod +x).

Формат атома-входа (первые строки файла):
- `todo: <id>` — обязателен. Нет строки → `FAILED no-todo`.
- `files: <путь> [путь…]` — обязателен. Перед запуском `git -C <project> status --porcelain -- <files>` обязан быть пуст → иначе `FAILED dirty-file`.
- `expect: <regex>` — обязателен. После запуска `git -C <project> diff -- <files>`: пуст → `FAILED no-diff`; не содержит regex (grep -Eq) → `FAILED no-marker`.
- `cmd: <команда>` — обязателен. Один запуск через `timeout 900`, без повторов.
- `gate: <команда>` — опционален. После приёмки по диффу; ненулевой код → `FAILED gate`.

usage: `atom-run <atom-file> --project DIR`.
Печатать ровно одну итоговую строку:
`ATOMRUN verdict=PASS todo=<id> files=<n> marker=ok gate=<ok|none>`
`ATOMRUN verdict=FAILED:<reason> todo=<id> files=<n> detail=<кратко>`
exit: 0 PASS, 1 FAILED, 2 ошибка аргументов. Никаких повторов запуска.

Проверки, выполнить и процитировать вывод:
1. `bash -n bin/atom-run` → rc=0.
2. Создай атом-пустышку `/root/workspaces/tools/docs/atoms/20261128/probe.md`:
   todo: probe-1 / files: README.md / expect: zzz-never / cmd: true
   запусти `bin/atom-run docs/atoms/20261128/probe.md --project /root/workspaces/tools` → `ATOMRUN verdict=FAILED:no-diff …`, rc=1.
3. Повтори ту же команду → снова `FAILED:no-diff`, rc=1 (повтор не становится PASS).
4. Атом без строки `todo:` → `FAILED:no-todo`.

Запреты: не трогать другие файлы; не запускать codex; не писать вне `/root/workspaces/tools/bin/`.