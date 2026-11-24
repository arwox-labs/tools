# ТЗ dcfg-80rgm U2b — навык csb: курьер ship → «GITHUB НАПРЯМУЮ»
FILE: .claude/skills/csb/references/core.md
FILE: .claude/skills/csb/references/autopilot.md
FILE: .claude/skills/csb/references/routing.md
FILE: .claude/skills/csb/references/stages.md

Цель: в справочниках csb нет предписаний доставлять через ship / ship-post / «почтальона» / «курьера» и не осталось `tools/bin/ship` как инструмента. Курьер отключён владельцем 17.10 (эпик dcfg-hrkh5). Действующий закон — `CLAUDE.md:3` «GITHUB НАПРЯМУЮ»: своя ветка `claude|codex/<атом>-*` от свежего `origin/main` → коммит → `git push -u origin <ветка>` (pre-push gitleaks) → `gh pr create --base main` → `gh pr checks <N> --watch` в фоне → `gh pr merge <N> --merge --delete-branch` → `tools/bin/git-sync <repo>` → `bd close <атом> --reason "PR <N> MERGED + <проверка>"`.
5 Whys: csb ведёт агента к стадии 14 по старому правилу «атом кончается локальным коммитом, доставка — почтальон» → csb не обновили после 17.10. ADR: в каждом месте заменить роль курьера на «GitHub напрямую» коротко, в языке и формате файла; таблицы оставить валидными (то же число ячеек).

## Правки (найти по тексту)
1. `core.md`: пункт `5) GIT-ЛОКАЛЬНО …` (≈:12), строка `★ ОБЯЗАТЕЛЬНЫЕ …` (≈:28), стадия `14 СОХРАНЕНИЕ …` (≈:49) — где сказано, что отгрузку/push/PR делает ship/ship-post/почтальон, или ★ включает `ship` → «доставка — сам агент по «GitHub напрямую» (`CLAUDE.md`)»; ★ `ship` → `доставка GitHub напрямую`.
2. `autopilot.md` строка таблицы `| 14 СОХРАНЕНИЕ | … | отгрузка — почтальон ship-post, не агент |` (≈:34) → последняя ячейка `доставка — сам агент: push → gh pr create → merge («GitHub напрямую»)`.
3. `routing.md` строка `| git, GitHub, PR | … | tools/bin/ship, compound-engineering:ce-worktree | …` (≈:44) → `git, gh («GitHub напрямую»), compound-engineering:ce-worktree`; строка L1c (≈:10) — если упоминает ship как доставку, заменить так же.
4. `stages.md` строки ≈:27, :33, :40, :55, :57 — где ship/почтальон/курьер описан как доставка или ★-пункт → «GitHub напрямую»; строка-анти-рационализация `| «Запущу ship / подожду CI, так надёжнее» | …` (≈:57) → `| «Подожду CI на переднем плане» | Запрещено: \`gh pr checks <N> --watch\` только в фоне, тем временем следующий атом; доставка — сам агент по «GitHub напрямую». |`.

## Запреты
Только эти 4 файла, только строки про доставку. Не трогать `SKILL.md`, прочие справочники, `tools/bin/ship*`, `/etc`, `~/.ssh`, `.env`, `.beads`, секреты. Без rm -rf, force-push, --no-verify.

## Готово, когда
`grep -c -E 'ship-post|tools/bin/ship|курьер|почтальон|\bship\b'` по 4 файлам = 0.
