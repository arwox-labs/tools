# ТЗ dcfg-80rgm U3 — safe-delete branch: локальная ветка без origin удаляется после копии bundle
FILE: bin/safe-delete
FILE: bin/safe-delete-test

Цель: `bin/safe-delete branch <repo> <ветка>` удаляет локальную ветку, которой нет на origin и которая не слита, после того как сохранит её копию `git bundle` в `$BK` (как уже делает для веток на origin, `bin/safe-delete:435-443`). Сейчас отказ «нет на origin» (`bin/safe-delete:424-427`) блокирует уборку своих пробных веток `claude/hrkh5-glprobe3` (projects) и `claude/hrkh5-gitleaks-probe` (tools).
Метод: 5 Whys — отказ стоит, потому что без origin/merge нет копии работы; закон «НЕ ТОРМОЗИТЬ» (/root/CLAUDE.md): «Ложный = защищаемое уже сохранено (git-ref, копия)». ADR: сделать копию bundle (`git bundle create "$f" "refs/heads/$br" --not origin/main`, проверка `git bundle verify`), записать путь в лог, затем `update-ref -d`. Восстановление — `git fetch <bundle> <br>:<br>`; строку восстановления вывести в stdout.
SRE: проверка места (как :436-437), копия до удаления, проверка копии, откат = bundle.

## Файлы (репо /root/workspaces/tools, ветка `codex/dcfg-80rgm-u3-bundle` от свежего origin/main, свой worktree)
- `bin/safe-delete` — функция-ветка `branch)`, блок `if [[ -z $shah ]]` (:419-430): вместо `refuse "нет на origin: $br"` (оба места) — bundle-копия, verify, лог, удаление. Остальные отказы не менять: main/master/HEAD/codex/*, некорректное имя, открытые PR (head и base), `SAFE_DELETE_GH` некорректный, repo не под /tmp при GH=false.
- `bin/safe-delete-test` — тест-сначала (красный → зелёный), стиль существующих тестов файла:
  1. положительный: в /tmp-репо с origin, локальная ветка без origin → rc 0, ветки нет, bundle в `$SAFE_DELETE_BK` есть и `git bundle verify` ок, из него ветка восстанавливается;
  2. отрицательные (должны остаться отказом): `main`, `codex/x`, ветка с открытым PR (используя существующий мок gh тестов, если есть), имя `-x`.

## Запреты
Тесты не удалять и не ослаблять; существующие кейсы должны остаться зелёными. Не трогать `bin/ship*`, `/etc/**`, `~/.ssh`, `.env`, `.beads`, секреты. Без rm -rf вне /tmp, force-push, --no-verify, без push/PR. Не запускать safe-delete на живых репо — только в /tmp-тестах.

## Готово, когда
`bash bin/safe-delete-test` → итог без FAIL (вывести последнюю строку и число ok/failed); `bash -n bin/safe-delete` rc 0; один коммит в ветке с трейлерами `ТЗ: docs/tz/2026-10-18-dcfg-80rgm-U3-safe-delete-bundle.md#U3` и `Atom: dcfg-80rgm`. Вывести diff.
