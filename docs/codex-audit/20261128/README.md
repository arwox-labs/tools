# Аудит 28.11: почему OpenCode жжёт лимиты и как включить роли Codex

Источник данных: `/root/.local/share/opencode/opencode.db`, таблицы `session_v2`, `session_part`, `session`,
`session_message`. Повторить: `sqlite3 -header -column opencode.db "<запрос из раздела>"`.

## 1. Замеры 30 последних сессий

| показатель | значение |
|---|---|
| input | 9 258 048 |
| output | 851 109 |
| cache_read | 581 749 698 |
| доля cache_read по дням | 87–98% |
| сессий на alibaba-token-plan | 29 из 30 |
| сессий на провайдере codex | 0 |

Худшая сессия `ses_df1320e30ffeXmkvex749WWOKO` («Bitrix24 Кинт интеграция», build): input 5 906 983,
cache_read 307 622 143 (×52), 74.6 ч. Вторая `de380f3f`: cache_read 87 297 219 (×121).

Дети-субагенты за 8 дней — 267 сессий: `alibaba/deepseek-v4.1-flash-1017 worker 143` (398 M cache_read),
`opencode-go/deepseek-v4.1-flash general 84`, `opencode-go/gpt-6-luna worker 55` (модель Codex, но через
провайдер OpenCode, не через `codex exec`), `alibaba/... tester 37`, `verifier 33+32`.

Вывод: утечка — не в цене модели, а в перечитывании растущего контекста лида и в том, что исполнители
запускаются OpenCode-субагентами, а не процессами Codex.

## 2. Дыры гейта Codex (файл:строка)

| # | файл:строка | цитата | следствие |
|---|---|---|---|
| 1 | `plugins/codex-first/index.js:8-10` | `event.system.push({ type: "text", text: LAW })` | только текст, не блокировка |
| 2 | `detect.js:25-26` | `/codex exec\|codex-atom/.test(toolText(part))` | достаточно упоминания (`which codex`) |
| 3 | `detect.js:29-30` | `/FALLBACK:/.test(outputText(part))` | агент сам печатает FALLBACK |
| 4 | `detect.js:33-35` | `["edit","write","apply_patch","patch"]` | правки через shell не видны |
| 5 | `index.js:28-32` | `if (count >= MAX_CORRECTIONS) continue` | после 3 замечаний гейт выключен |
| 6 | `index.js:3-4`, `opencode.jsonc:67` | `falling back to \`worker\` only after a recorded codex failure` | фолбэк разрешён текстом |
| 7 | `ROLE-MODELS.md:23`, `:58` | `worker / tester … alibaba`; «Codex (опционально)» | Codex не основной маршрут |

Структурная дыра: правку делает дочерняя сессия (`subagent`), а плагин смотрит сообщения родителя, поэтому
`didEdits` родителя не срабатывает.

## 3. Дубли программ до правки

`acc1-scripts/` и `scripts/pm2/` держали копии: `agent-download.sh`, `gdrive-download.sh`,
`gdrive-download.py` (байт-в-байт), `b244-fetch.sh` (210 и 218 строк — расхождение),
`auto-push.sh` (78 строк в `acc1-scripts` против 30 строк рабочего `/root/workspaces/projects/.githooks/auto-push.sh`).

Сделано (PR #568 в `arwox-labs/tools`): `scripts/pm2/{b244-fetch.sh,agent-download.sh,gdrive-download.sh,gdrive-download.py}`
— симлинки на `acc1-scripts/`; `git-hooks/shared/auto-push.sh` — симлинк на рабочий хук; в канон
`acc1-scripts/b244-fetch.sh` перенесена версия с позиционным `INPUT`.
Остаток: `acc1-scripts/auto-push.sh` — `safe-delete` отказал («используется», строка
`scripts/data/disk-rotate-deletions.tsv`), файл оставлен, обход не делался.
`drawio-ai-kit/` (46 MB, 1073 файла, вложенный `.git`) перенесён в `vendor/drawio-ai-kit` по spec:038.

## 4. Инструменты ролей Codex

`bin/codex-role` — 12 ролей, один изолированный `codex exec` на роль, артефакт
`NN-<role>-<atom>.md` в `docs/codex-audit/<дата>/`, машинный отчёт:
`RUNNER role=… model=… sandbox=… rc=… bytes=… atom_sha=… out=…`.
`/tmp` как каталог артефактов отклоняется (правило владельца 28.11).

`bin/codex-swarm` — рой с жёстким потолком 5 процессов в полёте, остановка при rc=29 (квота),
итог `SWARM total=… launched=… ok=… failed=… stopped=…`. `--parallel > 5` отклоняется.

| роль | модель | effort | sandbox |
|---|---|---|---|
| plan, critic, designer, analyst, reviewer, guard | gpt-6.2-astra | high | read-only |
| explorer, verifier, reporter | gpt-6-luna | low | read-only |
| builder, tester, integrator | gpt-6-luna | medium | workspace-write |

Обязательный флаг для неинтерактивного запуска: `-c approval_policy="never"`
(при глобальном `approval_policy = "on-request"` роли получали отказ на чтение файлов
и возвращали пустой артефакт).

## 5. Проверки

```
codex login status            -> Logged in using ChatGPT
codex-role --list             -> 12 строк + rc=0
codex-role guard …            -> RUNNER … rc=0 bytes=2268
codex-swarm … --parallel 3    -> SWARM total=4 launched=4 ok=4 failed=0 stopped=done
codex-swarm … --parallel 200  -> отказ: «не более 5 процессов на лида»
```

## 6. Границы

«200000 процессов Codex» не запускаются: потолок AGENTS.md (PROCESS DISCIPLINE п.2) — 5 процессов на
лида, и при ~300 MB RSS на процесс это 60 TB памяти. Квота выбирается плотно: рой держит 5 в полёте
до rc=29, очередь берёт следующие атомы.