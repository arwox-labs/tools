# ТЗ dcfg-80rgm U2a — законы projects: курьер ship → «GITHUB НАПРЯМУЮ»
FILE: AGENTS.md
FILE: docs/LAWS-PROCEDURES.md
FILE: .claude/rules/routes.json
FILE: .claude/workflows/code-atom.js

Цель: в этих файлах нет предписаний доставлять через ship / ship-post / «почтальона» / «курьера». Курьер отключён владельцем 17.10 (эпик dcfg-hrkh5). Действующий закон — `CLAUDE.md:3` «GITHUB НАПРЯМУЮ»: агент сам доставляет свой атом — своя ветка `claude|codex/<атом>-*` от свежего `origin/main` → коммит → `git push -u origin <ветка>` (pre-push gitleaks, `--no-verify` запрещён) → `gh pr create --base main` → `gh pr checks <N> --watch` в фоне → `gh pr merge <N> --merge --delete-branch` → `tools/bin/git-sync <repo>` → `bd close <атом> --reason "PR <N> MERGED + <проверка>"`. Force-push, push в main — запрещены.
5 Whys: агенты получают противоречивые законы → зеркала не обновили после PR 420 → правка только `CLAUDE.md` и `permission-routes.md`. ADR: каждую строку о курьере заменить короткой ссылкой на «GITHUB НАПРЯМУЮ» (`CLAUDE.md`) в стиле и языке файла; остальной текст не трогать.

## Правки (найти по тексту, номера строк ориентир)
1. `AGENTS.md` строка `- GITHUB БЕЗ ВОПРОСОВ (owner 09.10, all agents): …` (≈:11) → заменить всю строку на: `- GITHUB DIRECT (owner 17.10, epic dcfg-hrkh5; replaces GITHUB БЕЗ ВОПРОСОВ and the ship-post courier, which is off): the agent delivers its own atom by «GITHUB НАПРЯМУЮ» in \`CLAUDE.md\` — own \`claude|codex/<atom>-*\` branch → \`git push -u origin <branch>\` (pre-push gitleaks) → \`gh pr create --base main\` → \`gh pr merge <N> --merge --delete-branch\` → \`git-sync\` → \`bd close\`; asking the owner "send to GitHub?" is forbidden.` (в тексте строки не должно остаться слов ship-post/courier кроме «ship-post courier, which is off» — допустимо заменить на «the old courier, which is off», чтобы grep `ship-post` дал 0).
   Строка `- SHIP DEV/PROD (spec:099, …` (≈:18) → `- DEV/PROD (spec:099, owner 04.10): if origin has a \`dev\` branch, the atom's PR targets \`dev\` (\`gh pr create --base dev\`, worktree from fresh \`origin/dev\`) and the live copy stays on prod; otherwise \`main\`.` — сохранить остальной смысл исходной строки, если он не про курьера.
2. `docs/LAWS-PROCEDURES.md`: в строке с `→ \`tools/bin/ship\`` (≈:114) заменить `\`tools/bin/ship\`` на `доставка по «GitHub напрямую» (\`CLAUDE.md\`)`; в строке с `почтальон \`tools/bin/ship-post\`` (≈:151) фрагмент `push, PR, merge — почтальон \`tools/bin/ship-post\`` → `push, PR, merge — сам агент по «GitHub напрямую» (\`CLAUDE.md\`)`.
3. `.claude/rules/routes.json`: только поле `route` трёх объектов:
   - id `gh-write` → `"direct delivery by «GITHUB НАПРЯМУЮ» (\`CLAUDE.md\`, owner 17.10); \`gh issue\`, \`gh api\` writes are not delivery; reads via \`gh pr view\`."`
   - id `push` → `"only \`git push -u origin <own claude|codex/* branch>\` by «GITHUB НАПРЯМУЮ»; force, mirror, branch delete and push to main stay denied."`
   - id `git-c-worktree` → `"run git from the worktree path given by \`git worktree list\`; never \`cd …;\` chains; delivery steps follow «GITHUB НАПРЯМУЮ»."`
   JSON валиден.
4. `.claude/workflows/code-atom.js` строка `git add/commit/push не выполнять: коммит делает ship/ship-post.` (≈:26) → `git add/commit/push не выполнять: коммит и доставку делает главный агент по «GitHub напрямую».`

## Запреты
Только эти 4 файла и только эти строки. Не трогать `CLAUDE.md`, `tools/bin/ship*`, архив docs, `/etc`, `~/.ssh`, `.env`, `.beads`, секреты. Без rm -rf, force-push, --no-verify.

## Готово, когда
`grep -c -E 'ship-post|tools/bin/ship|курьер|почтальон'` по 4 файлам = 0; routes.json валиден; code-atom.js синтаксически цел.
