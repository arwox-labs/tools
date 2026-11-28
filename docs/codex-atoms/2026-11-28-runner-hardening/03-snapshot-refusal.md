# Атом dcfg-6des: codex-role — снапшот, runner_sha, setsid+kill, rc!=0 на отказ

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Никаких git-коммитов: ветку и коммит делает лид.

## Привязка

Твой атом: **`dcfg-6des`** (Beads, P1, open), создан лидом. Книговодство ведёт лид: не вызывай `bd`, не создавай Goal, не запускай git. В конце артефакта укажи `atom=dcfg-6des`.

## Что подтверждено этой сессией

- Запускатель правят во время исполнения: прогон упал с `line 122: unexpected EOF while looking for matching \`''`, потому что bash дочитывал изменённый файл.
- Отказ исполнителя засчитывается как успех: `RUNNER rc=0 bytes=407`, а в артефакте «Остановился до правок…». Приёмка не отличает отказ от результата.
- По таймауту дочерние процессы `codex exec` остаются жить.

## Правка (четыре точки, ничего больше)

Текущий файл — 120 строк, `bash -n` проходит. Строку запуска не переписывай целиком, добавляй минимально.

1. После `atom_sha=$(sha256sum ...)` добавь:
```
runner_sha=$(sha256sum "$0" | awk '{print $1}')
```
2. Перед строкой запуска `timeout "$timeout_s" codex exec ...` добавь снапшот-копию и запускай её через `bash`:
```
snapshot=$out/.runner-$runner_sha.sh
cp -f "$0" "$snapshot" && chmod +x "$snapshot"
```
Затем запускай `setsid timeout "$timeout_s" codex exec ...` (добавь `setsid` в начало команды, остальные аргументы не меняй) и сохрани pgid:
```
pgid=$!
```
Вместо прямого `rc=$?` после этой команды сделай ожидание с контролем: `wait $pgid; rc=$?`. При `rc -eq 124` сначала `kill -TERM -$pgid 2>/dev/null || true`, `sleep 5`, затем `kill -KILL -$pgid 2>/dev/null || true`. После завершения удали снапшот: `rm -f "$snapshot"`.
3. Добавь `runner_sha=%s` в обе строки RUNNER, где печатается `atom_sha` (строки rc=0 и rc!=0), и в строку `rc=124`.
4. Детект отказа. После проверки `[[ ! -s "$artifact" ]]` добавь: если артефакт содержит маркеры отказа (`Не могу`, `Остановился`, `не могу менять`, `read-only file system`, `Отказ`), печатать `RUNNER ... refusal=1` и `exit 1`. Регистр не важен: используй `grep -qiE`.

## Проверки (выполнить, вывод привести дословно)

- `bash -n bin/codex-role && echo SYNTAX_OK`
- `grep -c runner_sha bin/codex-role` → ≥ 2
- `grep -c setsid bin/codex-role` → ≥ 1
- `grep -c 'kill -TERM' bin/codex-role` → ≥ 1
- `grep -c refusal bin/codex-role` → ≥ 1
- `printf 'Остановился до правок\n' > /tmp/refusal-probe.md; bash bin/codex-role --list >/dev/null && echo LIST_OK` (проверка, что запускатель не сломан)
- `git diff --stat` (только чтение)

## Запреты

Не коммитить, не пушить, не менять другие файлы, не включать `secrets` в writable_roots, не запускать живые КИНТ/Битрикс24.