# ТЗ v2 U1+U2 — tools/bin/goal-guard (атом dcfg-g1ubc)

v2 — причина: v1 лежало вне каталога исполнителя (external_directory deny) и требовало bd в тестах; добавлен потолок владельца 05.10 («задач 600–700, без бесконечных циклов»).

разведка — repowise (файл новый, связей нет). Индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

## Паспорт источников
- https://code.claude.com/docs/en/hooks §Stop — вход: `session_id`, `transcript_path`, `last_assistant_message`, `background_tasks` («Present only when at least one background task is running»); выход: «printing JSON `{"decision": "block", "reason": "..."}`».
- hooks-guide: «Claude Code overrides a Stop hook after it blocks eight times in a row without progress».
- Формат журнала (замер 05.10): запуск фона — `Task ID: <id>` (Workflow), `agentId: <id>` (Agent); завершение — `<task-id><id></task-id>`.

## Задача (один файл bin/goal-guard, ≤70 строк bash, chmod +x)
Читает JSON из stdin. Любая ошибка (нет jq/bd, битый JSON) → `exit 0` без вывода (fail-open). Всегда `exit 0`.
Первая строка после shebang: `# goal-guard — Stop-хук Claude/Codex: не даёт остановиться, пока атомы bd своей сессии in_progress (dcfg-g1ubc).`
Порядок:
1. `sid` = `.session_id`; `sid4` = первые 4 символа; пусто → exit 0.
2. `(.background_tasks // []) | length` > 0 → exit 0.
3. `.last_assistant_message` содержит `Контрольная точка` → exit 0.
4. Если `.transcript_path` — файл: по `tail -n 3000` id запусков (`Task ID: X`, `agentId: X`) минус id завершений (`<task-id>X</task-id>`); остаток не пуст → exit 0.
5. Потолок: файл `${GOAL_GUARD_STATE:-/tmp}/goal-guard-$sid` хранит число блоков; ≥ `${GOAL_GUARD_MAX:-20}` → exit 0.
6. `ids` = `cd /root/workspaces/projects && bd list --status in_progress --limit 0 --json | jq -r --arg s "-$sid4]" '.[]|select(.title|contains($s))|.id'`; пусто → exit 0.
7. Иначе увеличить счётчик шага 5 и напечатать `jq -nc --arg r "..." '{decision:"block",reason:$r}'`, reason: `goal-guard: атомы сессии в работе: <ids через пробел>. Закрой каждый (bd close с командой и выводом) или остановись строкой «Контрольная точка: <шаг владельца>».`

## Проверка исполнителя (один прогон, только внутри каталога tools; bd не вызывать)
- `bash -n bin/goal-guard` → rc 0
- b) `echo '{"session_id":"40d1zz","background_tasks":[{"tool_use_id":"t","command":"x","start_time_unix_ms":1}]}' | bin/goal-guard` → пустой вывод
- c) `echo '{"session_id":"40d1zz","last_assistant_message":"Контрольная точка: логин"}' | bin/goal-guard` → пустой вывод
- e) файл `./.gg-e.jsonl` со строкой `Task ID: abc123`; вход с `"transcript_path":"./.gg-e.jsonl"` → пустой вывод
- g) `mkdir -p ./.gg-state && echo 20 > ./.gg-state/goal-guard-40d1zz`; `GOAL_GUARD_STATE=./.gg-state` и вход `{"session_id":"40d1zz"}` → пустой вывод
Ожидание 5/5; затем удалить `./.gg-e.jsonl` и `./.gg-state`. Проверки с bd (блок на живом атоме) делает verifier.
