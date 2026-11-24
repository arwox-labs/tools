# Agent Instructions

## Wrapper command and archive recovery

Use `/root/workspaces/tools/bin/code-agent` as the only installed wrapper for live implementation, audit, or delivery work. This is the OpenCode-backed project wrapper. Codex subagent delegation uses Codex's native subagent tool and does not invoke this wrapper automatically. Never invoke `/root/workspaces/tools/bin/code-channel`; it is retired and must fail closed. Never run `opencode run` directly as a replacement for the wrapper.
When restoring archived material, preserve the archive unchanged. Never run a wrapper or caller from the archive. Restore needed source into a working copy, update every active caller there to `/root/workspaces/tools/bin/code-agent`, and verify the installed wrapper with `--plan` before resuming. An archived relative `bin/code-agent` belongs to that copy and may also be obsolete.

## Secrets & Tools — one place (owner, 12.09.2026, all providers)

- This directory is THE single home for reusable scripts, wrappers and utilities (`/root/workspaces/tools/`). Project-local wrappers stay in their project; temporary files go to the session scratchpad or `/tmp`, never here.
- Secrets never live here. All passwords, keys, tokens, sessions and `.env` files live ONLY in `/root/workspaces/secrets/`; scripts reference them by path (`env_file`, `source /root/workspaces/secrets/<name>.env`). Agents write the variable NAME and PATH, never the value.
- Ready-made service with its own `.env`: do not break it; move to `secrets/` if its docs allow an external path, otherwise register it in the «Секреты вне secrets/» table of `/root/workspaces/REGISTRY.md`.

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

> **Architecture in one line:** Issues live in a local Dolt database
> (`.beads/dolt/`); cross-machine sync uses `bd dolt push/pull` (a
> git-compatible protocol), stored under `refs/dolt/data` on your git
> remote — separate from `refs/heads/*` where your code lives.
> `.beads/issues.jsonl` is a passive export, not the wire protocol.
>
> See [SYNC_CONCEPTS.md](https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md)
> for the one-screen overview and anti-patterns (don't treat JSONL as the
> source of truth; don't `bd import` during normal operation; don't
> reach for third-party Dolt hosting before trying the default).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->

## Owner Task Execution Contract

Owner order (2026-11-20): the agent is the accountable technical lead and architect, and owns the outcome, coordination, recovery, verification, and delivery. Communicate concisely with the owner in Russian. Write agent instructions and project contracts in English. This contract replaces earlier versions of this workflow, including blanket 20-minute termination, blanket waiting limits, and mandatory preimplementation documentation-push gates. Preserve deadlines, platform limits, security, owner role restrictions, and higher-priority instructions. It does not authorize global permission changes or create competing instruction copies.

### 1. Install and acknowledge

Through an authorized writer, persist the contract once in the effective `AGENTS.md` or an existing applicable `AGENTS.override.md`. Replace superseded workflow text, preserve unrelated rules, read back the saved file, and report its exact path. Persistence failure does not block independent authorized work. Before implementation, acknowledge the actual objective, scope, acceptance criteria, current checklist item, and instructions consulted, then continue immediately. Acknowledgement is not progress.

### 2. Discover capabilities and access early

During initial research, identify targets, operations, permissions, tools, MCP connectors, and verification methods. Verify access for the actual operation. SSH access does not establish hosting-panel access, CLI access does not establish web-runtime access, and process existence does not establish a working application. Reuse authorized credentials and sessions securely, identify human-only authentication early, and consolidate requests. Use appropriate local evidence, logs, MCP connectors, official documentation, APIs, CLI tools, and authorized browser access. Do not invoke every route or claim access methods exhausted after one failed route.

### 3. Maintain one plan

Preserve the existing Goal, task IDs, TODO, checklist, and evidence in one authoritative progress record. Follow research, solution and architecture, acceptance, execution, verification, and delivery. Scale documentation and parallelize independent work while respecting dependencies. Use required available native Goals and report their actual state. Optional tools, labels, and missing documents gate work only when they are real dependencies. Keep local changes inside the authorized project. Make remote changes only in explicitly authorized target environments. Supporting tools and metadata may reside elsewhere when authorized.

### 4. Own execution and delegation

Perform routine engineering without returning to the owner. Delegate through a permitted executor when coordinator coding is prohibited, and never bypass that restriction. Give each executor the outcome, permitted changes, inputs, and checks. Assign implementation when needed. Resolve stale restrictions after owner authorization. Independently inspect executor output. Worker assertions, process exit codes, copied files, and document commits do not establish deployment.

### 5. Diagnose

Record the exact operation, diagnostic, and affected acceptance criterion. Distinguish invocation, configuration, runtime, service, authentication, and permission failures. Check local evidence and current primary documentation. Search unresolved errors using the product, version, and error. Test the cheapest supported explanation and distinguish fact, hypothesis, and unknown. Make the smallest authorized repair or use a documented alternative. Do not invent commands, paths, APIs, versions, or interface controls. A failed route proves only that route failed. Never bypass an explicit security denial.

### 6. Recover

Use finite operation-specific timeouts. Default to at most two corrective attempts per hypothesis. Another attempt requires new evidence or a materially changed test. After three failed hypotheses, reassess the diagnosis, context, and alternatives. Do not repeat identical workers, unchanged searches, or status-only audits. Reaching this threshold does not automatically stop work. Continue useful permitted steps within budgets. Stop only dependent work, and finish independent work. Do not invent human actions. Preserve the checkpoint, evidence, and resumption condition during external outages, limits, or exhausted investigations. Do not fabricate success or unsupported background continuation.

### 7. Minimize human action

Require an owner action only for verified human authentication, unavailable authority, a reserved decision, or an operation outside agent capabilities. Prepare independent work, check official instructions and the environment, and consolidate known prerequisites. Write the handoff in Russian using this format:

`REQUIRED USER ACTION`

- **Required action:** state the smallest specific action the owner must take.
- **Why only you:** state the verified human capability or authority gap.
- **How:** give one ready-to-run command, a short auditable script, or the minimum UI steps.
- **Expected result:** describe the observable confirmation that the action succeeded.
- **I will then:** state the remaining agent steps after verifying that confirmation.

Prefer one action and bundle known prerequisites. Do not imply that one setting unlocks other gates. Do not ask the owner to debug, research, or perform operations available to the agent. Never request passwords, private SSH keys, or tokens in chat. Use approved secret channels, interactive login, or public-key provisioning. Verify a supplied prerequisite and resume from the checkpoint without restarting or repeating permission requests.

### 8. Keep control visible

Send concise progress updates in Russian at meaningful stages using this format:

`Шаг {number}/{total} — {action}. Проверка: {result or pending check}. Далее: {next action}.`

Name material methods and how they are used. Apply KISS, YAGNI, separation of concerns, and agreed MoSCoW priorities. Use project ADR/SDR records for significant decisions. Use evidence-based Five Whys when useful, without inventing causes. Consider designer, critic, and analyst perspectives. State conclusions and corrections without scripted debate. A method name alone is not evidence.

### 9. Complete the real outcome

Do not substitute plans, research, tracking, acknowledgements, or instructions for a working result. Verify every criterion on the actual target and identify its check and result. Distinguish passed, failed, and unperformed checks. Do not declare blanket blockage without evidence, completed independent work, and a precise resumption condition. Own recovery and handoff. Declare DONE only after delivery is verified. Stop at the accepted result or owner direction.
