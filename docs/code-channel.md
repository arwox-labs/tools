# Канал кода

`bin/code-channel` — единственный путь записи кода для Claude и Codex. Голые `opencode run` и `codex exec` запрещены.

## Вызов

- `bin/code-channel auto <проект> <ТЗ-файл>` — активный воркер, при доказанном сбое провайдера — один переход к другому.
- `bin/code-channel audit <проект> <ТЗ-файл>` — аудит без изменений на активном воркере.
- `bin/code-channel <go|sdk> <проект> <ТЗ-файл> [--model <m>]` — явный воркер без failover.
- `bin/code-channel use <go|sdk> "<цитата владельца>"` — мгновенное переключение активного воркера: пишет `state/code-channel/active` и `use.log`, без правки конфига.
- `bin/code-channel --plan` печатает `<id> <model>` активного воркера, например `go opencode-go/longcat-2.5-free`.
- `bin/code-channel --help` — справка, включая пути к конфигу, permit и этой странице.

## Воркеры

| id | состояние | модель / параметр |
| --- | --- | --- |
| `go` | enabled, active (owner 26.10) | OpenCode CLI; free `opencode-go/longcat-2.5-free` for code, audit and session continuation; no automatic paid Go fallback |
| `sdk` | включён | SDK-воркер: `bin/sdk-agent code` (audit: `sdk-agent read`), модель `claude-haiku-5-5`; бюджет 0.50 USD за прогон (потолок 2.00), общий дневной cap 22.00 USD (`/root/CLAUDE.md`) |

Других воркеров в лестнице нет. Лестница — ровно `go`, `sdk`, обе записи `enabled: true`.

## Failover по доказательствам

Слово владельца переключает активного воркера мгновенно; автоматического переключения по кругу нет. Сбой провайдера даёт доказательство: rc 124, строка `Upstream request failed:`, `channel-canary: down` или истёкшее время прогона (`CC_EVIDENCE_SECONDS`, по умолчанию 30 с). Только по доказательству `auto` вызывает другого воркера ровно один раз за направление (go→sdk или sdk→go). Без доказательства канал выходит с сырым rc и никого не переключает. Если упали оба, канал пишет permit и выходит с rc 32:

```json
{"rc":32,"go_rc":N,"sdk_rc":N,"stderr":["..."],"canary":"channel-canary: down","ts":1700000000}
```

Permit: `state/code-channel/permit.json`, путь переопределяется `CODE_CHANNEL_PERMIT`. «Ключи выдаются по доказательствам»: без permit и доказательств ключ другого воркера не выдаётся.

## Parallel runs

Замок — на каталог проекта: `bin/code-channel` делает `cd -- "$project"` и берёт `flock` на хеш `$PWD`, поэтому N параллельных прогонов требуют N разных каталогов проекта (worktree). Второй запуск в том же каталоге выходит с rc 25 «worktree занят». Read-only аудиты одного репозитория тоже идут каждый в своём worktree. Все N вызовов — одним сообщением, в фоне (`/root/CLAUDE.md`, PARALLEL HELPERS).

## Конфиг

`config/code-channel.json` stores `id`, `enabled`, `model`, `resume_model`/`audit_model` (equal to `model`), optional `allowed_models`, and `fallback_model` (empty for go); array order defines the ladder. The default changes only on owner instruction. Explicit `go --model <provider/model>` accepts the default or an approved `allowed_models` entry: `opencode-go/longcat-2.5-free`, `opencode/longcat-2.5-free`, `bitrixgpt/bitrix/bitrixgpt-5.6-agent`, or `bitrixgpt/bitrix/bitrixgpt-6.0-agent`. The SDK route is unchanged. `config/opencode-channel.json` добавляет агента `developer` (mode `primary`, TDD, правки только в `FILE:` ТЗ) и `audit`; go-код запускается с `--agent developer`, аудит — с `--agent audit`.

Промпты `developer` и `audit` не копируют запреты, а ссылаются на единственный источник `sdk-agent/system-prompt.md`:

```json
"prompt": "{file:../sdk-agent/system-prompt.md}"
```

Документация OpenCode:

- «Specify a custom system prompt file for this agent with the `prompt` config. The prompt file should contain instructions specific to the agent’s purpose.» — <https://opencode.ai/docs/agents/#prompt>.
- «This path is relative to where the config file is located. So this works for both the global OpenCode config and the project specific config.» — <https://opencode.ai/docs/agents/#prompt>.

Путь `../sdk-agent/system-prompt.md` считается от `config/opencode-channel.json`, поэтому Go-воркер в коде и аудите получает те же System bans, Secrets и Deletion (`rm -rf`, `safe-delete`), что и SDK-воркер. Верхнеуровневый `instructions` (<https://opencode.ai/docs/rules/#using-opencodejson>; «The recommended approach is to use the `instructions` field in `opencode.json`») добавляет файл всем агентам и считается от другого каталога, а `prompt` — только агентам Go-воркера и от каталога конфига, поэтому выбран `prompt`.

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
- The invocation uses `opencode --standalone run …` without external plugins.
- Только для процесса opencode заданы `OPENCODE_DISABLE_MODELS_FETCH=1` и `OPENCODE_DISABLE_AUTOUPDATE=1`, поэтому список моделей и обновления не тянутся из сети.
- `OPENCODE_DISABLE_CLAUDE_CODE` не ставится: запреты `/root/CLAUDE.md` (System bans, Secrets, Deletion) уже приходят в промпт `developer` из `sdk-agent/system-prompt.md`, а `.claude` оставлен ради глобальных правил и навыков.

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
| 32 | обе формы упали по доказательствам; см. permit |
| 124 | таймаут самого исполнителя (канал своих таймеров не ставит, owner 12.10) |

Где значение кода не описано выше, используйте только номер и `см. stderr`.

## Рекурсия и журнал

Внутри исполнителя задан `CODE_CHANNEL_ACTIVE`: любой вызов канала — exit 30. При ошибке не повторяйте канал: прочитайте stderr и permit, исправьте причину, затем один повтор. Исполнитель режимов `auto|audit` не делает git add/commit: локальный коммит, push и PR делает `code-channel delivery <worktree> <ТЗ>` (ship-post закрыт 22.10).

Журнал: `state/code-channel/runs.jsonl` — поля `provider_expected`, `provider_actual`, `model_actual`, `rc`, `retries`, `session`. Permit: `state/code-channel/permit.json` — доказательства обоих воркеров для решения ведущего.

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
