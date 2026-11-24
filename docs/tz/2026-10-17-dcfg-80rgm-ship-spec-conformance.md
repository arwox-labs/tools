# TZ dcfg-80rgm.3 — courier ship: does the code follow spec 099 decisions? (owner 17.10)

Executor: sdk-agent read (Read, Grep, Glob only). Writes nothing. Worktree: /root/workspaces/tools.

## Goal
For each spec decision below, say IMPLEMENTED, PARTIAL, MISSING or REVERSED in the code, with file:line. A decision reversed or missing in code explains failures the spec already solved on paper.

## Inputs
- Spec (read-only): `/root/workspaces/projects/specs/099-ship-dev-prod/spec.md` lines 381-560 (v6, v7, v8, CR-ADR-27).
- Code: `bin/ship`, `bin/ship-post`, `bin/ship-promote`, `bin/git-auto-lib`, tests `bin/ship-test`, `bin/ship-test.d/*.sh`, `bin/ship-post-test`.

## Decisions to check
D1. ADR-26 / FR-033: atom PR merged with `gh pr merge --merge --match-head-commit`, no `--squash` in `bin/ship` and `bin/ship-promote`. Also: what does `bin/ship-test.d/u22-squash-only.sh` assert, and which spec line or commit message justifies it (grep `docs/`, `bin/ship-test.d/u22-squash-only.sh` header comments)?
D2. ADR-27 / FR-034 / CR-ADR-27: `ship-post --submit` runs `git merge-tree --write-tree` against `origin/<base>` and refuses with 50 before the atom enters the queue.
D3. ADR-28 / FR-035: one tracker task per atom and code for 10/20/24/40/50/80; no shared per-repo task.
D4. Temporary codes 23/70/75: marker only, no reopen, retried next pass. Is 130 (interrupt) handled as temporary or parked as INFRA?
D5. v8: INFRA park → incident; is there any code that closes the incident when all its atoms are delivered?
D6. Exact-head rule `ship-post` ~line 582 ("Accepted delivery never rebases") vs. `bin/ship` `locked_core` rebase branch: when `--expected-head` is set, is the branch ever brought up to date with `origin/<base>`?

## Output (plain text)
One line per decision: `Dn STATUS — file:line — one sentence`. Then `REVERSED/MISSING list:` with the decisions whose absence lets conflicts reach the courier.

## Done check
Every status has file:line in code and the spec line it is checked against. Unknown → UNVERIFIED.

## Prohibitions
Read only; no network; no secrets; do not read `~/.ssh`, `/etc`, `.beads`.
