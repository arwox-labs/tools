# Атом tools-detect2: маркеры отказа read-only роли

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Коммит и PR делает лид.

## Привязка

Твой атом: **`tools-detect2`**. Книговодство ведёт лид: не вызывай `bd`, не создавай Goal, не запускай git. В конце артефакта укажи `atom=tools-detect2`.

## Дефект (воспроизведён)

Прогон `verifier` вернул:
```
RUNNER role=verifier model=gpt-6-luna sandbox=read-only rc=0 bytes=195
```
а в артефакте: «Не выполнено: доступ к файловой системе только для чтения, поэтому команды shell недоступны. Правок не делал.»
Отказ снова засчитан как успех: текущий шаблон маркеров такую формулировку не ловит.

## Правка

В строке с `grep -qiE` для `read-only` роли замени шаблон на:
```
'^[[:space:]]*(Не могу|Не выполнено|Остановился|Отказ)|доступ к файловой системе только для чтения|read-only file system'
```
Больше ничего не менять.

## Acceptance Criteria

- [ ] `bash -n bin/codex-role && echo SYNTAX_OK`
- [ ] `printf 'Не выполнено: доступ к файловой системе только для чтения\n' > /tmp/p2.md; grep -qiE '^[[:space:]]*(Не могу|Не выполнено|Остановился|Отказ)|доступ к файловой системе только для чтения|read-only file system' /tmp/p2.md && echo DETECTED`
- [ ] `printf 'Исправлено. Хост отказал chmod 0700. GATE: PASS\n' > /tmp/p3.md; grep -qiE '^[[:space:]]*(Не могу|Не выполнено|Остановился|Отказ)|доступ к файловой системе только для чтения|read-only file system' /tmp/p3.md && echo FALSE_POSITIVE || echo OK_NO_MATCH`
- [ ] `grep -n 'Не выполнено' bin/codex-role` → одна строка
- [ ] `git diff --stat bin/codex-role` (только чтение)

## Запреты

Не коммитить, не пушить, не менять другие файлы, не править `/root/.codex`, не читать `secrets/`.