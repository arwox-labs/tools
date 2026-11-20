# Канал кода

`bin/code-channel` — единственный путь записи кода для Claude и Codex. Голые `opencode run` и `codex exec` запрещены.

## Вызов

- `bin/code-channel auto <проект> <ТЗ-файл>` — активный воркер.
- `bin/code-channel audit <проект> <ТЗ-файл>` — аудит без изменений на активном воркере.
- `bin/code-channel go <проект> <ТЗ-файл> [--model <m>]` — явный воркер без failover.
- `bin/code-channel use go "<цитата владельца>"` — выбор активного воркера: пишет `state/code-channel/active` и `use.log`, без правки конфига.
- `bin/code-channel --plan` печатает `<id> <model>` активного воркера для задач разработки.
- `bin/code-channel --help` — справка, включая путь к конфигу и этой странице.

## Воркеры

| id | состояние | модель / параметр |
| --- | --- | --- |
| `go` | enabled, active | OpenCode CLI. Модель разработки показывает `--plan`, для аудита действует параметр `audit_model` |

## Сбой исполнителя

Канал запускает активную модель из `config/code-channel.json`. При ошибке провайдера используйте stderr и журнал запуска. Повтор и переход на настроенную запасную модель зависят от параметров OpenCode. Ошибка возвращается вызывающему процессу.

## Parallel runs

Замок — на каталог проекта: `bin/code-channel` делает `cd -- "$project"` и берёт `flock` на хеш `$PWD`, поэтому N параллельных прогонов требуют N разных каталогов проекта (worktree). Второй запуск в том же каталоге выходит с rc 25 «worktree занят». Read-only аудиты одного репозитория тоже идут каждый в своём worktree. Все N вызовов — одним сообщением, в фоне (`/root/CLAUDE.md`, PARALLEL HELPERS).

## Конфиг

`config/code-channel.json` stores `id`, `enabled`, `model`, optional `resume_model`/`audit_model`, optional `allowed_models`, and `fallback_model`; array order defines the ladder. Use `code-channel --plan` for the configured development model and `audit_model` for audit. The default changes only on owner instruction. Explicit `go --model <provider/model>` accepts the configured default or a configured `allowed_models` entry. `config/opencode-channel.json` adds `developer` (mode `primary`, TDD, edits only `FILE:` task lines) and `audit`; code runs with `--agent developer`, audits with `--agent audit`.

Prompts `developer` and `audit` use `config/code-channel-system-prompt.md`:

```json
"prompt": "{file:./code-channel-system-prompt.md}"
```

Документация OpenCode:

- «Specify a custom system prompt file for this agent with the `prompt` config. The prompt file should contain instructions specific to the agent’s purpose.» — <https://opencode.ai/docs/agents/#prompt>.
- «This path is relative to where the config file is located. So this works for both the global OpenCode config and the project specific config.» — <https://opencode.ai/docs/agents/#prompt>.

The path is relative to `config/opencode-channel.json`. The worker gets the shared system bans, secrets, and deletion rules. OpenCode's top-level `instructions` applies to all agents, while `prompt` is scoped to these channel agents.

## MCP

Go-воркеру MCP не нужны: код он читает обычными `grep`/`read`. Глобальный конфиг OpenCode (`~/.config/opencode/opencode.jsonc`) определяет серверы `vibecode`, `context7`, `repowise`, `codebase-memory-mcp`; каждый стартует отдельный процесс (~0.2–0.3 GB на воркер). В `config/opencode-channel.json` все четыре выключены через `"enabled": false`.

Документация OpenCode:

- «You can also disable a server by setting `enabled` to `false`. This is useful if you want to temporarily disable a server without removing it from your config.» — <https://opencode.ai/docs/mcp-servers/#enable>.
- «Configuration files are **merged together**, not replaced. Settings from the following config locations are combined. Later configs override earlier ones only for conflicting keys. Non-conflicting settings from all configs are preserved.» — <https://opencode.ai/docs/config/#locations>.
- «Custom config is loaded between global and project configs in the precedence order.» — <https://opencode.ai/docs/config/#custom-path>. Поэтому `OPENCODE_CONFIG=config/opencode-channel.json` накладывается на глобальный конфиг и выключает его MCP; проектный `opencode.json` загружается позже и может включить сервер обратно.

Проверка без вызова модели:

```bash
OPENCODE_CONFIG=config/opencode-channel.json opencode mcp list
```

## Ленивый старт Go-воркера

Go-запуск не тратит время на то, что воркеру не нужно:

- `config/opencode-channel.json` выключает `snapshot`, `lsp` и `autoupdate` (`false`). Snapshots — undo для TUI; воркер коммитит обычным git. LSP и проверка обновлений в неинтерактивном прогоне не нужны.
- Для TeamoRouter обёртка передаёт OpenCode флаг `--standalone`.
- OpenCode 2.2.7 session reconciliation reads `session_v2` (`model.providerID` and `model.id`), including resume-session lookup.
- Только для процесса opencode заданы `OPENCODE_DISABLE_MODELS_FETCH=1` и `OPENCODE_DISABLE_AUTOUPDATE=1`, поэтому список моделей и обновления не тянутся из сети.
- `OPENCODE_DISABLE_CLAUDE_CODE` is not set. The shared prompt provides system bans, secrets, and deletion rules, while `.claude` remains available for global rules and skills.

## Коды выхода

| код | значение |
| --- | --- |
| 3 | неверный вызов, выключенный воркер или конфиг |
| 15 | модель вне конфига или вне формата |
| 16 | нет изменений |
| 22 | audit изменил файлы |
| 23 | сверка провайдера или модели |
| 25 | worktree занят другим запуском |
| 26 | правки вне `Files:` ТЗ |
| 27 | loop-guard: строка вывода повторилась |
| 28 | switch-lock: активный канал не включён в лестнице |
| 29 | TZ `Test:` line STALLED in test-once |
| 30 | рекурсия |
| 31 | TZ `Test:` line failed after the helper |
| 124 | таймаут самого исполнителя (канал своих таймеров не ставит, owner 12.10) |

Где значение кода не описано выше, используйте только номер и `см. stderr`.

## Рекурсия и журнал

Внутри исполнителя задан `CODE_CHANNEL_ACTIVE`: любой вызов канала — exit 30. При ошибке не повторяйте канал: прочитайте stderr и журнал, исправьте причину, затем следуйте лимитам повторов из текущего плана. Исполнитель режимов `auto|audit` не делает git add/commit: доставку выполняет `code-channel delivery <worktree> <ТЗ>`.

Журнал: `state/code-channel/runs.jsonl` — поля `provider_expected`, `provider_actual`, `model_actual`, `rc`, `retries`, `session`.

## Пролонгация

- Результат прогона неполный — новый файл ТЗ, а не перезапуск того же.
- Имя — `<дата>-<атом>-v2-<суть>.md`, в том же worktree; исходное ТЗ не правится.
- Первая строка нового ТЗ — «Сделано (не трогать): …»: факты прогона N — строка журнала `code-channel: … run=… t=…` и список изменённых файлов; дальше только остаток работы.
- Не больше двух прогонов на атом.
- Второй worktree и второй процесс канала на тот же атом запрещены.

## Чек-лист запуска

- Атом взят: `bd update <атом> --claim`.
- Путь проекта и путь к ТЗ — абсолютные (иначе rc 3 «project must be absolute path»).
- На этом worktree нет живого процесса канала.
- ТЗ: 1–2 файла, ≤100 строк правки, проверка одной командой.
- Вызов один: Bash `run_in_background: true` без параметра timeout (у фоновых команд локальной сессии лимита нет — code.claude.com/docs/en/tools-reference); результат по уведомлению.
