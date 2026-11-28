Для `pm2 jlist` и `pm2 describe` найдены прямые совпадения с глобальными `shell deny` на строках **526** и **528**. Для `git checkout … && git push` есть несколько возможных совпадений. Конкретное правило по одному сообщению `Permission denied: shell` определить нельзя.

В [opencode.jsonc](/root/.config/opencode/opencode.jsonc:439) **208 правил `permissions` с эффектом `deny` или `ask`**. Из них 167 глобальных `deny`, 36 глобальных `ask` и 5 агентных `deny`. Ещё один `deny` находится отдельно в `policies`. Подсчёт сделан по объектам разобранного JSONC, включая строки с несколькими объектами. Аудит выполнен только чтением. Команды PM2, Git и `bd` не запускались.

## Сопоставление с отказами

| Наблюдение | Что подтверждает конфигурация |
|---|---|
| `pm2 jlist` | Дословно `{ "action": "shell", "resource": "pm2 jlist*", "effect": "deny" }`. Совпадает и с командой без аргументов. [opencode.jsonc:526](/root/.config/opencode/opencode.jsonc:526) |
| `pm2 describe` | Дословно `{ "action": "shell", "resource": "pm2 describe*", "effect": "deny" }`. Совпадает и с командой с именем процесса. [opencode.jsonc:528](/root/.config/opencode/opencode.jsonc:528) |
| Часть `git checkout …` | Общего запрета на `git checkout` нет. Запрещены три паттерна `"git checkout .*"`, `"git checkout -- .*"` и `"git checkout *opencode*"`. Без аргумента после `checkout` выбрать совпадение нельзя. [opencode.jsonc:502](/root/.config/opencode/opencode.jsonc:502) · [503](/root/.config/opencode/opencode.jsonc:503) · [510](/root/.config/opencode/opencode.jsonc:510) |
| Часть `git push` | Если эта часть проверялась отдельно и была **ровно** `git push`, она совпадает с `{ "action": "shell", "resource": "git push*", "effect": "deny" }`. Позднее разрешены, в частности, `"git push -u origin *"` и `"git push origin *"`. После них снова стоят запреты для определённых флагов и refspec с `:`. В конфиге порядок описан словами «Последнее совпадение побеждает». [opencode.jsonc:449](/root/.config/opencode/opencode.jsonc:449) · [452](/root/.config/opencode/opencode.jsonc:452) · [471](/root/.config/opencode/opencode.jsonc:471) · [484](/root/.config/opencode/opencode.jsonc:484) |
| Цепочка целиком | Специального правила на `&&` нет. В самом файле есть оговорка «Разбор цепочек команд в bash-шаблонах не подтверждён замером». Если проверялась вся строка, паттерн с началом `git push` сам по себе не объясняет отказ строки, начинающейся с `git checkout`. Для точной атрибуции нужны исходная строка со всеми аргументами, роль агента и запись решения OpenCode. [opencode.jsonc:304](/root/.config/opencode/opencode.jsonc:304) |

Роль имеет значение. Глобально задано `{ "action": "shell", "resource": "*", "effect": "allow" }` с последующими исключениями. У `audit` дополнительно есть собственное `{ "action": "shell", "resource": "*", "effect": "allow" }`. Комментарий рядом описывает намерение наследовать глобальные ограничения. Фактический порядок применения агентного и глобального списков в отказавшей сессии не проверялся. Агент по умолчанию — `"default_agent": "build"`. [opencode.jsonc:328](/root/.config/opencode/opencode.jsonc:328) · [330](/root/.config/opencode/opencode.jsonc:330) · [450](/root/.config/opencode/opencode.jsonc:450) · [773](/root/.config/opencode/opencode.jsonc:773)

## Полный реестр `deny` и `ask`

В реестре ниже все номера относятся к `/root/.config/opencode/opencode.jsonc`. В кавычках приведены **дословные значения `resource`**, включая пробелы, точки и `*`. Заголовок каждого блока указывает общие для него `action` и `effect`.

### Глобальные `shell deny` — 93

```text
452  "git push*"
454  "git -C * push *"
455  "git -c * push *"
456  "git --git-dir=* push *"
457  "git --work-tree=* push *"
458  "git --no-pager push *"
459  "*hooksPath*"
460  "*hookspath*"
461  "*--config-env*"
462  "*--no-verify*"
463  "bd dolt push*"
464  "gh repo delete*"
465  "gh api * DELETE*"
484  "*push *--force*"
485  "*push *--delete*"
486  "*push *--mirror*"
487  "*push *--all*"
488  "*push * -f*"
489  "git push *:*"
490  "git push * -f*"
491  "git push *--force*"
492  "git push *--delete*"
493  "git push *--all*"
494  "git push *--mirror*"
495  "git push *--no-verify*"
496  "gh pr edit*"
497  "gh pr comment*"
498  "git filter-repo*"
500  "git reset --hard*"
501  "git clean*"
502  "git checkout .*"
503  "git checkout -- .*"
504  "git worktree remove *--force*"
505  "git stash drop*"
506  "git stash clear*"
507  "git stash*"
508  "git revert*"
509  "git restore*"
510  "git checkout *opencode*"
511  "rsync --delete*"
513  "cat *secrets/*"
514  "head *secrets/*"
515  "tail *secrets/*"
516  "less *secrets/*"
517  "grep *secrets/*"
518  "cat *.env*"
519  "cat *auth.json*"
520  "printenv*"
521  "env"
524  "*/proc/*/environ*"
525  "pm2 env*"
526  "pm2 jlist*"
527  "pm2 prettylist*"
528  "pm2 describe*"
529  "pm2 show*"
531  "*/.ssh/*"
532  "*/etc/ssh/*"
533  "systemctl stop ssh*"
534  "systemctl disable ssh*"
535  "systemctl stop networking*"
536  "iptables -F*"
537  "iptables -X*"
538  "iptables -P*"
539  "nft flush*"
540  "ufw disable*"
541  "ufw reset*"
542  "netplan apply*"
543  "mkfs*"
544  "dd *"
545  "fdisk*"
546  "parted*"
547  "wipefs*"
548  "shred*"
549  "rm -rf /"
550  "rm -rf /etc*"
551  "rm -rf /usr*"
552  "rm -rf /var*"
553  "rm -rf /root"
554  "rm -rf /root/workspaces"
555  "rm -rf ~*"
556  "curl * | bash*"
557  "curl * | sh*"
558  "wget * | bash*"
559  "wget * | sh*"
561  "opencode run*"
562  "opencode debug*"
564  "tmux kill*"
565  "tmux new*"
566  "pm2 kill*"
567  "npm install -g*"
568  "npm i -g*"
569  "pnpm * -g*"
570  "pnpm *--global*"
```

### Глобальные `shell ask` — 36

Каждый паттерн ниже запрашивает подтверждение. Для PM2, `git checkout` и `git push` записей `ask` нет. Первый объект блока — `{ "action": "shell", "resource": "useradd*", "effect": "ask" }`. [opencode.jsonc:581](/root/.config/opencode/opencode.jsonc:581)

```text
581  "useradd*"
582  "usermod*"
583  "userdel*"
584  "passwd*"
585  "chpasswd*"
586  "visudo*"
587  "chmod -R*"
588  "chown -R*"
589  "reboot*"
590  "shutdown*"
591  "grub-*"
592  "update-initramfs*"
593  "modprobe*"
594  "sysctl -w*"
595  "apt upgrade*"
596  "apt-get upgrade*"
597  "apt full-upgrade*"
598  "apt dist-upgrade*"
599  "apt-get dist-upgrade*"
600  "do-release-upgrade*"
601  "docker rm*"
602  "docker system prune*"
603  "docker volume rm*"
604  "docker volume prune*"
605  "docker image prune*"
606  "docker compose down -v*"
607  "sqlite3 *"
608  "bd delete*"
609  "gh repo archive*"
610  "gh repo rename*"
611  "gh repo edit*"
612  "ufw allow*"
613  "ufw deny*"
614  "iptables -A*"
615  "iptables -I*"
616  "ip route*"
```

### Глобальные `skill deny` — 55

На строках 643–652 в одной строке файла записано несколько самостоятельных правил. Общее разрешение `"resource": "*", "effect": "allow"` стоит перед перечисленными исключениями. [opencode.jsonc:628](/root/.config/opencode/opencode.jsonc:628)

```text
629  "csb"
630  "contour-cycle"
631  "research-cycle"
632  "research-lite"
633  "speckit-*"
634  "beads"
635  "audit"
636  "verify"
637  "bd-slice"
638  "code-atom"
639  "incident-response*"
640  "observability*"
641  "cloud-infrastructure*"
642  "security-scanning*"
643  "incident-runbook-templates", "on-call-handoff-patterns", "postmortem-writing", "slo-implementation"
644  "distributed-tracing", "grafana-dashboards", "prometheus-configuration", "service-mesh-observability"
645  "cost-optimization", "hybrid-cloud-networking", "istio-traffic-management", "linkerd-patterns"
646  "mtls-configuration", "multi-cloud-architecture", "terraform-module-library", "use-railway"
647  "attack-tree-construction", "sast-configuration", "security-requirement-extraction"
648  "stride-analysis-patterns", "threat-mitigation-mapping"
649  "algorithmic-art", "arwox-tz-kp", "brand-guidelines", "canvas-design", "doc-coauthoring"
650  "docx", "pdf", "pptx", "xlsx", "import-memory", "internal-comms", "morning"
651  "slack-gif-creator", "theme-factory", "web-artifacts-builder", "mcp-builder", "skill-creator"
652  "agent-cognitive-system", "customize-opencode", "webapp-testing"
```

### Глобальные `edit deny` — 17

```text
658  "**/.env"
659  "**/.env.*"
660  "**/*.secrets*"
661  "**/.secrets*"
662  "**/secrets/**"
663  "**/.netrc"
664  "data/**"
666  "**/opencode.json"
667  "**/opencode.jsonc"
668  "**/.opencode/**"
669  "**/*.db"
670  "**/*.db-wal"
671  "**/*.db-shm"
673  "**/git-hooks/dispatch"
674  "**/bin/secret-gate*"
675  "**/.gitleaks*"
676  "**/config/secret-gate.*"
```

Для отдельных ролей есть точечные разрешения. Например, у `build` на строках 84–88 записаны `"action": "edit"`, `"resource": "/root/.config/opencode/opencode.jsonc"`, `"effect": "allow"`. Аналогичная запись есть у `worker` на строках 197–201. Поэтому глобальный список сам по себе не описывает все права конкретного агента. [opencode.jsonc:85](/root/.config/opencode/opencode.jsonc:85) · [198](/root/.config/opencode/opencode.jsonc:198)

### Два глобальных MCP-запрета и пять агентных запретов

| Область | Строки | Дословная цитата |
|---|---:|---|
| Глобально | 445 | `{ "action": "codebase-memory-mcp_index_repository", "resource": "*", "effect": "deny" }` |
| Глобально | 446 | `{ "action": "codebase-memory-mcp_delete_project", "resource": "*", "effect": "deny" }` |
| `verifier` | 232–234 | `"action": "edit"`, `"resource": "*"`, `"effect": "deny"` |
| `explore` | 245 | `{ "action": "edit", "resource": "*", "effect": "deny" }` |
| `prompt-engineer` | 260 | `{ "action": "edit", "resource": "*", "effect": "deny" }` |
| `analyst` | 295–297 | `"action": "edit"`, `"resource": "*"`, `"effect": "deny"` |
| `audit` | 319 | `{ "action": "edit", "resource": "*", "effect": "deny" }` |

Отдельная политика ограничивает провайдера — `{ "action": "provider.use", "resource": "teamorouter", "effect": "deny" }`. Она находится в `"policies"` и в число 208 не входит. [opencode.jsonc:680](/root/.config/opencode/opencode.jsonc:680)

## Плагины и хуки

В конфиге перечислены ровно три плагина — `"plugins": ["/root/.config/opencode/plugins/no-tails", "/root/.config/opencode/plugins/todo-gate", "/root/.config/opencode/plugins/codex-first"]`. У всех трёх в коде есть хук `"context"` и подписка на `"session.idle"`. Они добавляют инструкции в контекст и при выполнении своих условий отправляют в сессию корректирующий запрос. В просмотренном коде этих плагинов нет обработчика, возвращающего `Permission denied: shell` перед запуском команды. [opencode.jsonc:31](/root/.config/opencode/opencode.jsonc:31)

| Плагин | Что делает по коду |
|---|---|
| `no-tails` | Добавляет `event.system.push({ type: "text", text: LAW })`. На `session.idle` проверяет текст последнего ответа, открытые атомы своей сессии, незакоммиченные пути и другие рабочие деревья под `/tmp/`. Условие пропуска — `if (!tails.length && !atoms.length && !dirt)`. До пяти раз отправляет корректирующий запрос. Вызовы `bd` и Git обнаружены статическим чтением исходника. [index.js:16](/root/.config/opencode/plugins/no-tails/index.js:16) · [33](/root/.config/opencode/plugins/no-tails/index.js:33) · [38](/root/.config/opencode/plugins/no-tails/index.js:38) · [53](/root/.config/opencode/plugins/no-tails/index.js:53) · [59](/root/.config/opencode/plugins/no-tails/index.js:59) · [69](/root/.config/opencode/plugins/no-tails/index.js:69) · [76](/root/.config/opencode/plugins/no-tails/index.js:76) |
| `todo-gate` | Добавляет открытые TODO в контекст через `text: LAW + block`. Берёт последний завершённый вызов `todowrite` и выбирает `todo.status === "pending" \|\| todo.status === "in_progress"`. Если ответ объявляет завершение при открытых TODO, отправляет коррекцию. Лимит — `MAX_CORRECTIONS = 5`. [index.js:5](/root/.config/opencode/plugins/todo-gate/index.js:5) · [9](/root/.config/opencode/plugins/todo-gate/index.js:9) · [18](/root/.config/opencode/plugins/todo-gate/index.js:18) · [31](/root/.config/opencode/plugins/todo-gate/index.js:31) · [41](/root/.config/opencode/plugins/todo-gate/index.js:41) · [detect.js:12](/root/.config/opencode/plugins/todo-gate/detect.js:12) |
| `codex-first` | Добавляет правило о подтверждении работы отчётом `RUNNER`. На `session.idle` проверяет условие `(didEdits(messages) \|\| delegated(messages)) && !ranCodex(messages) && !sawFallback(messages)`. Распознаёт `rc=0` и `rc=29` в выводе инструмента. После трёх коррекций один раз отправляет текст `HALT` через `ctx.session.prompt({ sessionID, text: HALT })`. Это объясняет сообщение `STAGE HALTED` на уровне диалога. [index.js:9](/root/.config/opencode/plugins/codex-first/index.js:9) · [12](/root/.config/opencode/plugins/codex-first/index.js:12) · [19](/root/.config/opencode/plugins/codex-first/index.js:19) · [33](/root/.config/opencode/plugins/codex-first/index.js:33) · [detect.js:21](/root/.config/opencode/plugins/codex-first/detect.js:21) · [66](/root/.config/opencode/plugins/codex-first/detect.js:66) |

**Git-хуки.** В конфиге упомянут auto-push hook, а в `permissions` разрешены две точные формы — `"git config --global core.hooksPath /root/workspaces/projects/.githooks"` и `"git config --global --get core.hooksPath"`. Эти записи подтверждают разрешение команд. Фактическая установка хука из них не следует. В составе `skills/` также найден `skills/.git/hooks/pre-commit`, его содержимое и исполнение не проверялись. Отдельной верхнеуровневой секции `hooks` в JSONC нет. [opencode.jsonc:479](/root/.config/opencode/opencode.jsonc:479) · [481](/root/.config/opencode/opencode.jsonc:481) · [482](/root/.config/opencode/opencode.jsonc:482)

## MCP-серверы

Все четыре описаны в `mcp.servers` как `"type": "local"`. Статус ниже взят из `disabled` в этом файле. Запуск серверов не проверялся. [opencode.jsonc:376](/root/.config/opencode/opencode.jsonc:376)

| Сервер | Дословное значение `command` | Состояние в глобальном конфиге |
|---|---|---|
| `vibecode` | `["/root/workspaces/tools/vibecode-mcp/node_modules/.bin/mcp-vibe-api"]` | `"disabled": false` · [команда, строка 381](/root/.config/opencode/opencode.jsonc:381) · [флаг, 386](/root/.config/opencode/opencode.jsonc:386) |
| `context7` | `["/root/workspaces/tools/context7-mcp/node_modules/.bin/context7-mcp"]` | `"disabled": false` · [команда, 391](/root/.config/opencode/opencode.jsonc:391) · [флаг, 395](/root/.config/opencode/opencode.jsonc:395) |
| `repowise` | `["/root/.local/bin/repowise", "mcp", "--no-workspace"]` | `"disabled": true` · [команда, 400](/root/.config/opencode/opencode.jsonc:400) · [флаг, 403](/root/.config/opencode/opencode.jsonc:403) |
| `codebase-memory-mcp` | `["/root/.local/bin/codebase-memory-mcp"]` | `"disabled": true` · [команда, 407](/root/.config/opencode/opencode.jsonc:407) · [флаг, 411](/root/.config/opencode/opencode.jsonc:411) |

## Контекст, инструкции и отсутствующие настройки

| Что проверено | Результат |
|---|---|
| Автосжатие контекста | **Включено.** В `compaction` заданы `"auto": true`, `"keep": {` с `"tokens": 10000` и `"buffer": "35%"`. Для агента `compaction` отдельно задана `"model": "alibaba-token-plan/qwen3.8-flash#none"`. [opencode.jsonc:50](/root/.config/opencode/opencode.jsonc:50) · [53](/root/.config/opencode/opencode.jsonc:53) · [55](/root/.config/opencode/opencode.jsonc:55) · [365](/root/.config/opencode/opencode.jsonc:365) |
| Ограничение вывода инструментов | Отдельно от автосжатия задано `"tool_output": { "max_lines": 40, "max_bytes": 81920 }`. Это ещё одна причина, по которой агент может видеть сокращённый вывод. [opencode.jsonc:47](/root/.config/opencode/opencode.jsonc:47) |
| Подключённые инструкции | В массиве один файл — `"instructions": ["~/.config/opencode/AUTO-GITHUB-LAW.md"]`. Файл с этим именем присутствует в каталоге. `AGENTS.md` в этом массиве не указан. [opencode.jsonc:29](/root/.config/opencode/opencode.jsonc:29) |
| Поиск в интернете | В глобальных и агентных `permissions` нет отдельного правила `websearch` или `web_search`, в том числе `deny` или `ask`. Для `audit` явно разрешено получение страницы — `{ "action": "webfetch", "resource": "*", "effect": "allow" }`. Наличие поискового инструмента в конкретной сессии этим не установлено. [opencode.jsonc:325](/root/.config/opencode/opencode.jsonc:325) |
| `cli.json` | В файле 29 строк. После `$schema` присутствуют только `tabs`, `theme`, `diffs`, `session`, `mini`, `animations`. `"turn_summary": "show"` относится к интерфейсу. Вторых секций `permissions`, `plugins`, `hooks`, `mcp`, `compaction` или `instructions` здесь нет. [cli.json:1](/root/.config/opencode/cli.json:1) · [18](/root/.config/opencode/cli.json:18) · [28](/root/.config/opencode/cli.json:28) |
| Состав каталогов | Отдельного `agents/` в `/root/.config/opencode/` нет. Определения ролей находятся в `"agents": {` основного файла. В `plugins/` три перечисленных каталога. В `skills/` обнаружены 29 символьных ссылок, `creator-mode/` и `.git/`. Навыки не загружались. [opencode.jsonc:57](/root/.config/opencode/opencode.jsonc:57) |

**Итог по блокировкам.** Прямые кандидаты для двух отказов PM2 — строки 526 и 528. Для Git решают точная форма `checkout`, аргументы `push` и способ разбора `&&`. Штатный механизм `ask` задействован для 36 других shell-паттернов. Все три плагина подключены в конфигурации и корректируют ход сессии через `context` и `session.idle`. Автосжатие включено. Из четырёх MCP-серверов два включены глобально и два выключены.
