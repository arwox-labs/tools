# Атом tools-0gh: --ignore-user-config в запускателе + маркеры read-only

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Коммит и PR делает лид.

## Привязка

Твой атом: **`tools-0gh`**. Книговодство ведёт лид: не вызывай `bd`, не создавай Goal, не запускай git. В конце артефакта укажи `atom=tools-0gh`.

## Два дефекта (воспроизведены)

1. Исполнитель блокируется сломанными навыками: `Маршрут CSB заблокирован: отсутствует /root/.codex/skills/csb/references/routing.md` (в каталоге есть `routes.md`, но не `routing.md`). Прогон закончился без правок, предыдущий — с `lfg` и `input-triage.md`.
   Проверено: `codex exec --ignore-user-config -m gpt-6-luna … 'Выведи PROBE_OK'` → `PROBE_OK`, блокировки нет.
2. Маркеры отказа read-only роли не ловят формулировку «Не выполнено: доступ к файловой системе только для чтения»: прогон дал `rc=0 bytes=195`.

## Правка (две точки, файл уже 150 строк, `bash -n` проходит)

1. В строке запуска добавь флаг `--ignore-user-config` рядом с `--skip-git-repo-check`. Порядок остальных аргументов не меняй:
```
    -s "$sandbox" --ignore-user-config --skip-git-repo-check -C "$project" "$prompt" \
```
2. В строке `grep -qiE` для `read-only` роли замени шаблон на:
```
'^[[:space:]]*(Не могу|Не выполнено|Остановился|Отказ)|доступ к файловой системе только для чтения|read-only file system'
```
Больше ничего не менять: отпечатки `nochange`, снапшот, таймауты, наборы записи.

## Acceptance Criteria

- [ ] `bash -n bin/codex-role && echo SYNTAX_OK`
- [ ] `grep -c 'ignore-user-config' bin/codex-role` → ≥ 1
- [ ] `grep -c 'Не выполнено' bin/codex-role` → 1
- [ ] `printf 'Не выполнено: доступ к файловой системе только для чтения\n' > /tmp/p2.md; grep -qiE '^[[:space:]]*(Не могу|Не выполнено|Остановился|Отказ)|доступ к файловой системе только для чтения|read-only file system' /tmp/p2.md && echo DETECTED`
- [ ] `printf 'Исправлено. Хост отказал chmod 0700. GATE: PASS\n' > /tmp/p3.md; grep -qiE '^[[:space:]]*(Не могу|Не выполнено|Остановился|Отказ)|доступ к файловой системе только для чтения|read-only file system' /tmp/p3.md && echo FALSE_POSITIVE || echo OK_NO_MATCH`
- [ ] `git diff --stat bin/codex-role` (только чтение)

## Запреты

Не коммитить, не пушить, не менять другие файлы, не править `/root/.codex`, не читать `secrets/`.