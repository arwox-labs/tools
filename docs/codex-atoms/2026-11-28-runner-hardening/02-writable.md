# Атом dcfg-7aew: codex-role — writable_roots, /dev/null, снятие книговодства

Файл один: `bin/codex-role` (репозиторий `/root/workspaces/tools`). Никаких git-коммитов: ветку и коммит делает лид.

## Привязка

Твой атом: **`dcfg-7aew`**, создан в Beads лидом (P1, open). Запись в Beads и Goal ведёт лид, они вне твоей песочницы: не вызывай `bd`, не создавай Goal, не ищи другие атомы. В конце артефакта укажи `atom=dcfg-7aew`.

## Что подтверждено этой сессией

- `grep -c writable_roots bin/codex-role` → `0`: набор записи песочницы не задан, поэтому роль не может писать в Beads и каталог отчётов и отказывается целиком.
- Роль возвращает текстовый отказ вместо работы, потому что её контракт требует книговодство, недоступное в песочнице.

## Правка (три точки, ничего больше)

1. В блоке формирования `prompt` (после строки `prompt=$(cat "$atom")`) добавь универсальную преамбулу для всех ролей:

```
prompt+=$'\n\nКниговодство ведёт лид: не вызывай bd, не создавай Goal, не запускай git-команды. Атом уже создан и закреплён за тобой, он указан в тексте задания. Пиши только перечисленные в задании файлы. Текстовый отказ без правок считается провалом атома.'
```

2. В строку запуска `codex exec` добавь явный набор записи и отключение stdin. Замени строку 90 так, чтобы она стала:

```
timeout "$timeout_s" codex exec -m "$model" -c model_reasoning_effort="$effort" \
    -c 'sandbox_workspace_write.network_access=true' \
    -c "sandbox_workspace_write.writable_roots=[\"$project\",\"$project/.agent-work\",\"/root/workspaces/projects/.beads\",\"/root/workspaces/tools/.beads\",\"/root/workspaces/tools/docs\",\"/root/workspaces/tools/state\",\"/root/.local/share/opencode/log\"]" \
    -s "$sandbox" --skip-git-repo-check -C "$project" "$prompt" \
    </dev/null >"$artifact" 2>"$artifact.err"
```

3. Остальное не трогать: роли, модели, effort, коды выхода, формат артефакта, guard пустого артефакта.

## Проверки (выполнить, вывод привести дословно)

- `bash -n bin/codex-role && echo SYNTAX_OK`
- `grep -c writable_roots bin/codex-role` → ≥ 1
- `grep -c secrets bin/codex-role` → 0 (путь `/root/workspaces/secrets` не должен появляться)
- `grep -c '</dev/null' bin/codex-role` → ≥ 1
- `git diff --stat` (только чтение)

## Запреты

Не коммитить, не пушить, не менять другие файлы, не включать `/root/workspaces/secrets`, `/root/.config`, `/root/.codex` в writable_roots, не запускать живые КИНТ/Битрикс24.