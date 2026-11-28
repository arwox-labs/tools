# Атом dcfg-m2wn: уточнить маркеры отказа в codex-role

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Никаких git-коммитов: коммит и PR делает лид.

## Привязка

Твой атом: **`dcfg-m2wn`** (Beads, P1). Книговодство ведёт лид: не вызывай `bd`, не создавай Goal, не запускай git. В конце артефакта укажи `atom=dcfg-m2wn`.

## Дефект (воспроизведён этой сессией)

Детект отказа — строка вида:

```
if grep -qiE 'Не могу|Остановился|не могу менять|read-only file system|Отказ' "$artifact"; then
```

Артефакт успешной работы содержал фразу «CBM-индекс не обновился: хост отказал `chmod 0700`», сработал `Отказ` без учёта регистра, и запускатель вернул `rc=1 refusal=1` при полностью выполненной работе: `=== Results: 316 passed, 0 failed ===`, `GATE: PASS`.

## Правка

1. Замени шаблон на набор, который не ловит слово «отказал» внутри предложения:
```
if grep -qiE 'Не могу|^[[:space:]]*Остановился|не могу менять|read-only file system|^[[:space:]]*Отказ' "$artifact"; then
```
2. Больше ничего не менять: ни строку запуска, ни таймауты, ни формат RUNNER.

## Проверки (выполнить, вывод привести дословно)

- `bash -n bin/codex-role && echo SYNTAX_OK`
- `printf 'Исправлено. хост отказал chmod 0700\nGATE: PASS\n' > /tmp/probe-ok.md; grep -qiE 'Не могу|^[[:space:]]*Остановился|не могу менять|read-only file system|^[[:space:]]*Отказ' /tmp/probe-ok.md && echo FALSE_POSITIVE || echo OK_NO_MATCH`
- `printf 'Отказ: файл вне песочницы\n' > /tmp/probe-bad.md; grep -qiE 'Не могу|^[[:space:]]*Остановился|не могу менять|read-only file system|^[[:space:]]*Отказ' /tmp/probe-bad.md && echo REFUSAL_DETECTED`
- `printf 'Не могу менять файл\n' > /tmp/probe-bad2.md; grep -qiE 'Не могу' /tmp/probe-bad2.md && echo REFUSAL_DETECTED`
- `grep -n 'grep -qiE' bin/codex-role` → одна строка с новым шаблоном

## Запреты

Не коммитить, не пушить, не менять другие файлы, не запускать живые КИНТ/Битрикс24, не читать `secrets/`.