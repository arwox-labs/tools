# ТЗ dcfg-80rgm U1v2 — правила Codex и Claude: курьер ship → «GITHUB НАПРЯМУЮ» (копии файлов)
FILE: x/AGENTS.md
FILE: x/rules/owner-operations.md
FILE: x/skills/alignment.md
FILE: y/CLAUDE.md

Контекст: `x/` — копии `/root/.codex/{AGENTS.md, rules/owner-operations.md, skills/csb/references/alignment.md}`, `y/CLAUDE.md` — копия `/root/.claude/CLAUDE.md`. Курьер ship/ship-post отключён владельцем 17.10 (эпик dcfg-hrkh5), процесс PM2 `ship-post` удалён 18.10. Codex блокируется: его правила требуют `ship-post --submit`, которого нет.
5 Whys: Codex не может сдать атом → правила велят ship-post → после 17.10 обновили только законы Claude → Codex-зеркала остались. ADR: заменить ровно перечисленные фрагменты текстами ниже, всё остальное в файлах не трогать (в файлах есть чужие незакоммиченные правки — их сохранить).
Канон «GITHUB НАПРЯМУЮ» (`projects/CLAUDE.md:3`): своя ветка `codex/<atom>-*` от свежего `origin/main` → коммит → `git push -u origin <branch>` (pre-push gitleaks; `--no-verify` запрещён) → `gh pr create --base main` → `gh pr checks <N> --watch` в фоне → зелёные, а если GitHub CI не запустился — тесты атома на сервере и их вывод в теле PR → `gh pr merge <N> --merge --delete-branch` (репо только со squash — `--squash`) → `tools/bin/git-sync <repo-name>` → `bd close <atom> --reason "PR <N> MERGED + <check>"`.

## Замены (old — точная подстрока, new — замена)
x/AGENTS.md:
1. old `Live acceptance never blocks delivery: submit via ship-post, verify live after courier merge + git-sync as a separate child atom.` → new `Live acceptance never blocks delivery: deliver by GITHUB DIRECT, verify live after merge + git-sync as a separate child atom.`
2. old `run every Codex shell invocation of bd and ship with \`env BEADS_ACTOR=Codex\` so ship's child bd close inherits the same actor as Codex's own claim.` → new `run every Codex shell invocation of bd with \`env BEADS_ACTOR=Codex\` so every bd close carries the same actor as Codex's own claim.`
3. old `writes → delivery via \`ship-post --submit\`; reads via \`gh pr view\`.` → new `→ direct delivery by GITHUB DIRECT (\`/root/workspaces/projects/CLAUDE.md\` «GITHUB НАПРЯМУЮ», owner 17.10); \`gh issue\`, \`gh api\` writes are not delivery; reads via \`gh pr view\`.`
4. old `- any \`git … push\` → \`ship-post --submit <worktree> --atom <id> --tz <file#U> --evidence … --files …\`.` → new `- \`git push\` → only \`git push -u origin <own codex/* branch>\` by GITHUB DIRECT; force, mirror, branch delete and push to main stay denied.`
5. old `delivery steps belong to \`ship-post\`.` → new `delivery steps follow GITHUB DIRECT.`
6. old `The \`ship-post\` courier owns gitleaks before push, the verified private destination, PR, required CI and exact-head merge; the agent does not wait for these remote stages.` → new `The agent delivers it by GITHUB DIRECT: pre-push gitleaks, verified private destination, PR, CI watched only in background, merge, git-sync, bd close.`
7. Строка `- GIT-LOCAL (owner 06.10, spec:099 U2): …` целиком → `- GITHUB DIRECT (owner 17.10, epic dcfg-hrkh5; the ship/ship-post courier is off and must not be invoked): work only in the task's isolated worktree; after local acceptance commit own files only (trailers \`ТЗ: <file#U>\`, \`Atom: <id>\`), then \`git push -u origin <own codex/* branch>\` → \`gh pr create --base main\` → \`gh pr checks <N> --watch\` in background (if GitHub CI does not start: atom tests on the server, output in the PR body) → \`gh pr merge <N> --merge --delete-branch\` (\`--squash\` where the repo allows only squash) → \`/root/workspaces/tools/bin/git-sync <repo-name>\` → \`env BEADS_ACTOR=Codex bd close <id> --reason "PR <N> MERGED + <check>"\`. A repo without origin (e.g. /root/.codex): one local commit of own paths only (\`git add -- <paths>\`, never \`-A\`), then bd close with the SHA. Preserve private-destination, client-scope and production gates.`
8. old `The authorized ship invocation may perform its guarded \`--force-with-lease\` on the task's own branch and clean up its worktree/branch after verified merge; never repeat those internal steps manually or bypass host gates.` → new `Force pushes of any kind stay forbidden; never bypass host gates.`

x/rules/owner-operations.md:
9. Строка `- After local acceptance, invoke the existing \`/root/workspaces/tools/bin/ship-post --submit\` …` целиком → `- After local acceptance, deliver by GITHUB DIRECT (\`/root/workspaces/projects/CLAUDE.md\` «GITHUB НАПРЯМУЮ», owner 17.10; the ship/ship-post courier is off): own commit → \`git push -u origin <own codex/* branch>\` → \`gh pr create\` → CI in background or server tests in the PR body → \`gh pr merge\` → \`git-sync\` → \`bd close\` with PR number. Private-destination, secret scanning (pre-push gitleaks) and production gates remain. Local acceptance and remote delivery require separate evidence.`

x/skills/alignment.md:
10. Блок от `Deliver accepted scoped changes only through` до `Record ship's actual output, exit code and PR URL in the current Beads atom.` включительно → `Deliver accepted scoped changes by GITHUB DIRECT (/root/workspaces/projects/CLAUDE.md «GITHUB НАПРЯМУЮ», owner 17.10; the ship courier is off): own commit with trailers \`ТЗ: <file#U>\` and \`Atom: <id>\`, \`git push -u origin <own codex/* branch>\` (pre-push gitleaks), \`gh pr create --base main\`, CI watched in background or server test output in the PR body when GitHub CI does not start, \`gh pr merge\`, \`git-sync\`, then \`env BEADS_ACTOR=Codex bd close <id>\` with command, exit codes, output and PR URL.\nNever change shared git user.name or reassign a delegated Claude atom without authority.` (перенос строки `\n` — настоящий перевод строки).
11. Две строки `The only force-with-lease exception is ship's guarded internal push of this task's` и `own branch; this does not authorize a manual repeat or bypass of a host rejection.` → одна строка `There is no force-push exception; never bypass a host rejection.`

y/CLAUDE.md:
12. old `(safe-delete, ship-post, code-channel, deploy wrappers with backup and rollback)` → new `(safe-delete, git/gh by GITHUB НАПРЯМУЮ, code-channel, deploy wrappers with backup and rollback)`

## Запреты
Только 12 замен выше. Остальной текст, в том числе чужие правки, не менять. Не читать файлы вне списка.

## Готово, когда
`grep -c -E 'ship-post|tools/bin/ship|курьер|почтальон'` по 4 файлам = 0; `grep -c 'force-with-lease exception'` в x/skills/alignment.md = 0.
