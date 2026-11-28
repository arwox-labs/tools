# Атом C: избыточность конфигов и инструкций (read-only)

Цель: найти, что избыточно и жрёт лимиты в конфигурации агентов.

Источники (только чтение):
- `/root/.config/opencode/opencode.jsonc` (67.8 КБ) — структура: agents, mcp, plugins, permissions, providers, experimental.
- Цепочка инструкций: `/root/AGENTS.md`, `/root/workspaces/AGENTS.md`, `/root/workspaces/projects/AGENTS.md`, `/root/workspaces/projects/incidents/AGENTS.md`, `/root/.config/opencode/AGENTS.md`, `/root/.config/opencode/AUTO-GITHUB-LAW.md` (61.7 КБ суммарно).
- `/root/.config/opencode/ROLE-MODELS.md`, `/root/.config/opencode/skills/` (30), `/root/.claude/skills/` (26).

Шаги:
1. opencode.jsonc: перечисли agents (имя, model, mode), mcp-серверы (имя, enabled), plugins, число permissions-правил. Найди: агенты с одинаковой моделью/дубли, отключённые/неиспользуемые mcp, мёртвые permissions. Значения ключей/токенов НЕ печатай — только имена полей.
2. Дубли и противоречия правил между файлами инструкций: найди ≥5 конкретных пар с file:line и дословной цитатой (например одно правило разрешает, другое запрещает; одно и то же правило повторено в 2+ файлах). Отдельно: `/root/AGENTS.md` TEMPORARY OVERRIDE против остальных.
3. Навыки: список имён из обоих каталогов; какие реально вызывались — `sqlite3 "file:/root/.local/share/opencode/opencode.db?mode=ro"` по таблице part: grep имён навыков в данных частей (LIMIT-запросы, не_full scan по 1.5 ГБ — используй WHERE length(data) и LIMIT). Посчитай вызовы по имени, назови неиспользуемые.
4. Размер системного промпта: сумма байтов инструкций + оценка токенов (байты/4). Сколько это стоит на каждую сессию при 3845 сессиях.

Артефакт: таблица находок: файл:строка, цитата, класс (дубль/противоречие/мёртвое), цена в токенах если применимо. Печатай в stdout.

Проверки:
- `wc -c` по 6 файлам инструкций — сумма в отчёте.
- Каждая находка имеет file:line и цитату (без них не включай).

Запреты: не читать auth.json, ~/.codex/*.toml, .env, secrets/; значения apiKey/token не печатать; файлы не менять.