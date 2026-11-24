# ТЗ dcfg-80rgm U2 — законы projects и Claude: курьер ship → «GITHUB НАПРЯМУЮ»

Цель: в действующих правилах projects и Claude нет предписаний доставлять через ship/ship-post/«почтальона». Курьер отключён владельцем 17.10 (эпик dcfg-hrkh5); `projects/CLAUDE.md:3` уже содержит канон «GITHUB НАПРЯМУЮ» — ссылаться на него, не дублировать.
Метод: 5 Whys — PR 420 обновил только `CLAUDE.md` и `permission-routes.md`; остальные зеркала (AGENTS.md, LAWS-PROCEDURES, routes.json, csb, workflow) не обновлены → агенты получают противоречивые законы. ADR: каждую строку о курьере заменить ссылкой на «GITHUB НАПРЯМУЮ» (`projects/CLAUDE.md`) в том же стиле файла.

## Файлы и строки (репо /root/workspaces/projects, ветка `codex/dcfg-80rgm-u2-laws` от свежего origin/main, свой worktree)
1. `AGENTS.md`: :11 «GITHUB БЕЗ ВОПРОСОВ … ship-post courier» → «GITHUB НАПРЯМУЮ» краткой строкой со ссылкой; :18 «SHIP DEV/PROD … tools/bin/ship delivers» → правило dev-ветки без курьера: если у origin есть `dev`, PR атома идёт в `dev` (`gh pr create --base dev`), иначе в main.
2. `docs/LAWS-PROCEDURES.md`: :114 «→ tools/bin/ship» → «→ доставка по «GitHub напрямую»»; :151 «push, PR, merge — почтальон tools/bin/ship-post» → «push, PR, merge — сам агент по «GitHub напрямую»».
3. `.claude/rules/routes.json`: :16, :19, :24 поле `route` → тексты как в `.claude/rules/permission-routes.md:13,16,21`. JSON должен оставаться валидным (`jq . file`).
4. `.claude/workflows/code-atom.js`: :26 «коммит делает ship/ship-post» → «коммит и доставку делает главный агент по «GitHub напрямую»».
5. `.claude/skills/csb/references/core.md` :12, :28, :49; `autopilot.md` :34; `routing.md` :44 (`tools/bin/ship` → `git`/`gh` по «GitHub напрямую»); `stages.md` :40, :55, :57 — слова ship/почтальон/курьер в предписаниях → «GitHub напрямую».
6. `docs/PM2-PROCESSES.md`: :99-100 строки `ship-post`, `ship-post-events` → статус «отключён 17.10 (dcfg-hrkh5), файлы — откат».
7. `/root/.claude/CLAUDE.md` :120 (вне git; сначала копия через `tools/bin/safe-delete`-совместимый бэкап: `cp` в `/root/workspaces/projects/.agent-work/backup/claude-md-20261018.bak`): в списке обёрток «(safe-delete, ship-post, code-channel, …)» заменить `ship-post` на `git/gh by GITHUB НАПРЯМУЮ`. Больше ничего в файле не менять.

## Запреты
Не трогать: `CLAUDE.md` (строка 3 — канон), `tools/bin/ship*`, архив `docs/tz|plans|research|reports|csb-updates`, `docs/LAWS-DETAIL.md` (исторические отметки «ЗАМЕНЁН»), `/etc/**`, `~/.ssh`, `.env`, `.beads`, секреты. Без rm -rf, force-push, --no-verify, без push/PR (доставку делает главный агент). Менять только перечисленные строки.

## Готово, когда
`grep -c -E 'ship-post|tools/bin/ship|курьер|почтальон' <файлы 1-7>` → 0 у каждого; `jq empty .claude/rules/routes.json` rc 0; `node --check .claude/workflows/code-atom.js` rc 0; один коммит в ветке с трейлерами `ТЗ: tools/docs/tz/2026-10-18-dcfg-80rgm-U2-projects-laws.md#U2` и `Atom: dcfg-80rgm`. Вывести таблицу «файл:строка было → стало».
