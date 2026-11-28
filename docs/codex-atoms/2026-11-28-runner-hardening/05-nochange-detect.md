# Атом dcfg-m2wn (шаг 2): детект отказа по факту правок, а не по словам

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Никаких git-коммитов: коммит и PR делает лид.

## Привязка

Твой атом: **`dcfg-m2wn`**. Книговодство ведёт лид: не вызывай `bd`, не создавай Goal, не запускай git (кроме `git -C … status --porcelain --untracked-files=no` внутри самого запускателя — это часть правки, а не твоя команда). В конце артефакта укажи `atom=dcfg-m2wn`.

## Дефект (воспроизведён дважды)

Текстовые маркеры ловят собственный отчёт: артефакт с цитатой `read-only file system` или `Остановился` даёт `refusal=1` при выполненной работе. Проверка на текущем артефакте:
```
grep -ci 'Не могу' artifacts/07-builder-04-refusal-markers.md → 1   (это цитата в отчёте)
new pattern → NEW_MATCH
```
Значит словесный детект нельзя чинить словами.

## Правка

1. Перед запуском для песочницы `workspace-write` сними отпечаток дерева:
```
before=$(git -C "$project" status --porcelain --untracked-files=no 2>/dev/null | sha256sum | awk '{print $1}')
```
2. После успешного (`rc=0`) прогона сними отпечаток снова. Если он равен `before` и роль пишущая (`workspace-write`), печатай
```
RUNNER role=… sandbox=… rc=1 bytes=… atom_sha=… runner_sha=… out=… nochange=1
```
и `exit 1`.
3. Текстовый детект оставь только для `read-only` ролей и сузь до строки-начала:
```
if [[ "$sandbox" == "read-only" ]] && grep -qiE '^(Не могу|Остановился до правок|Отказ по правилу)' "$artifact"; then
```
Для `workspace-write` текстовые маркеры не применяются вовсе.
4. Больше ничего не менять: строка запуска, таймауты, снапшот, наборы записи, формат остальных строк RUNNER.

## Acceptance Criteria

- [ ] `bash -n bin/codex-role && echo SYNTAX_OK`
- [ ] `grep -c 'nochange=1' bin/codex-role` → ≥ 1
- [ ] `grep -n 'git -C "$project" status --porcelain' bin/codex-role` → 2 строки (до и после)
- [ ] `grep -n "sandbox\" == \"read-only\" && grep -qiE" bin/codex-role` → 1 строка
- [ ] синтетика: `printf 'Остановился до правок\n' > /tmp/p1.md` — для `workspace-write` текстовый маркер не используется (проверь чтением кода, что ветка под условием `read-only`)
- [ ] `git diff --stat bin/codex-role` (только чтение)

## Запреты

Не коммитить, не пушить, не менять другие файлы, не запускать живые КИНТ/Битрикс24, не читать `secrets/`.