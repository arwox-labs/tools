# ТЗ dcfg-80rgm U1 — правила Codex: курьер ship → «GITHUB НАПРЯМУЮ»

Цель: Codex сдаёт готовый атом сам (git push своей ветки → gh pr create → gh pr merge), а не через `ship-post --submit`. Курьер ship/ship-post отключён владельцем 17.10 (эпик dcfg-hrkh5); его файлы `tools/bin/ship*` остаются для отката.
Метод: 5 Whys — Codex блокирован (dcfg-z0sy5), потому что его правила требуют `ship-post --submit` и зарегистрированный worktree; курьер выключен, а правила не обновлены (закон обновили только для Claude, PR 420). ADR: заменить строки о курьере каноническим текстом, ничего больше не менять.

## Канон (вставлять смысл, не изобретать)
`projects/CLAUDE.md:3` «GITHUB НАПРЯМУЮ»: своя ветка `codex/<атом>-*` от свежего `origin/main` → коммит → `git push -u origin <ветка>` (pre-push запускает gitleaks; `--no-verify` запрещён) → `gh pr create --base main` → `gh pr checks <N> --watch` в фоне → зелёные, а если CI не запустился — тесты атома на сервере и их вывод в теле PR → `gh pr merge <N> --merge --delete-branch` → `tools/bin/git-sync <repo>` → `bd close <атом> --reason "PR <N> MERGED + <проверка>"`. Force-push, push в main, mirror, удаление веток на origin — запрещены.
Маршруты (формат `projects/.claude/rules/permission-routes.md:13,16,21`):
- `gh pr create|merge` → direct delivery by «GITHUB НАПРЯМУЮ»; `gh issue`, `gh api` writes are not delivery; reads via `gh pr view`.
- `git push` → only `git push -u origin <own codex/* branch>`; force, mirror, branch delete and push to main stay denied.
- `git -C <worktree> …` → run git from the worktree path; delivery steps follow «GITHUB НАПРЯМУЮ».

## Файлы и строки
1. `/root/.codex/AGENTS.md`: :14 (BEADS_ACTOR «bd and ship» → «bd»), :48, :51, :56 (маршруты → канон выше), :80-82 (курьер владеет gitleaks/PR/merge, `ship-post --submit`, «authorized ship invocation … force-with-lease» → канон; force-with-lease исключение удалить, force запрещён).
2. `/root/.codex/rules/owner-operations.md`: :11 `ship-post --submit` → канон.
3. `/root/.codex/skills/csb/references/alignment.md`: :85-121 блок ship (вызов `tools/bin/ship`, «ship performs commit, gitleaks, push, PR…», BEADS_ACTOR для ship, «Record ship's output», исключение force-with-lease) → канон.
4. `/root/workspaces/projects/.codex-kit/templates/global-AGENTS.md`: :5 упоминание доставки курьером → канон.

## Запреты
Не трогать: `tools/bin/ship*`, архив `docs/tz|plans|research|reports|csb-updates`, `/etc/**`, `~/.ssh`, `auth.json`, `*.toml` в `~/.codex`, `.env`, `.beads`, секреты. Без rm -rf, force-push, --no-verify. Менять только перечисленные строки; остальной текст файлов не переписывать. Не запускать push/PR — только правка файлов.

## Готово, когда
`grep -n -E 'ship-post|tools/bin/ship|\bship\b|курьер|почтальон' <4 файла>` → пусто; `git -C /root/workspaces/projects diff --stat .codex-kit` — 1 файл. Вывести таблицу «файл:строка было → стало».
