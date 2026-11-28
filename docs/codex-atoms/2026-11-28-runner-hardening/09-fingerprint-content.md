# Атом tools-detect3: отпечаток дерева должен учитывать содержимое правок

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Коммит и PR делает лид.

## Привязка

Твой атом: **`tools-detect3`**. Книговодство ведёт лид: не вызывай `bd`, не создавай Goal, не запускай git. В конце артефакта укажи `atom=tools-detect3`.

## Дефект (воспроизведён)

Сейчас отпечаток считается так:
```
before=$(git -C "$project" status --porcelain --untracked-files=no 2>/dev/null | sha256sum | awk '{print $1}')
```
Это хеш **списка путей**, а не содержимого. Если файлы уже были изменены до прогона, исполнитель правит их дальше — список путей не меняется, отпечаток совпадает, и запускатель выдаёт ложный провал:
```
RUNNER role=builder … rc=1 … nochange=1
```
при фактическом изменении `git diff --stat → 2 files changed, 79 insertions(+), 52 deletions(-)`.

## Правка

Замени обе строки (до и после прогона) на отпечаток, включающий содержимое и новые файлы:
```
before=$( { git -C "$project" status --porcelain -uall 2>/dev/null; git -C "$project" diff 2>/dev/null; } | sha256sum | awk '{print $1}')
```
и так же для `after`. Больше ничего не менять.

## Acceptance Criteria

- [ ] `bash -n bin/codex-role && echo SYNTAX_OK`
- [ ] `grep -c 'status --porcelain -uall' bin/codex-role` → 2
- [ ] `grep -c 'git -C "$project" diff 2>/dev/null' bin/codex-role` → 2
- [ ] `grep -c 'status --porcelain --untracked-files=no' bin/codex-role` → 0
- [ ] `git diff --stat bin/codex-role` (только чтение)

## Запреты

Не коммитить, не пушить, не менять другие файлы, не править `/root/.codex`, не читать `secrets/`.