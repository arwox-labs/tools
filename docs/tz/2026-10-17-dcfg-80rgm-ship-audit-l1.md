# TZ dcfg-80rgm.2/.3 — courier ship: level-1 failure audit (owner 17.10)

Executor: sdk-agent read (Read, Grep, Glob only). Writes nothing. Worktree: /root/workspaces/tools.

## Goal
Find which few root causes produce most delivery failures of the courier (`bin/ship`, `bin/ship-post`, `bin/git-auto-lib`), with evidence from files.

## Inputs
- Failure markers: `state/ship-post/receipts/*/*/*.failed` (one exit code per file); the receipt log is the same path without `.failed`, plus `.log`.
- Parked incidents: `state/ship-post/incidents/{30,70,130}.atoms`, `state/ship-post/incidents/parked/*`.
- Code: `bin/ship` (exit codes line ~15, `locked_core` ~105-123, conflict check ~198-211), `bin/ship-post` (`remote_result` ~396, `record_failure` ~414, `park_atom` ~440, `ack_delivery` ~486, `deliver_one` ~533-586, `scan_repo` skip logic ~633-667), `bin/git-auto-lib` (`ga_ci_wait`).
- GitHub snapshot taken 17.10 by the lead (UNVERIFIED for you, use as hints, do not repeat as fact):
  - agent PRs created since 17.09: tools 252 merged / 14 open / 1 closed; arwox-v3-src 50 merged / 4 closed.
  - 12 of 14 open tools PRs are `mergeable=CONFLICTING`, 10 of them have no CI checks at all; the CI workflow `.github/workflows/tools-smoke.yml` runs only on `pull_request`.
  - INFRA-coded atoms dcfg-0aion, dcfg-h1vsg, dcfg-lhyko, dcfg-fm4p3.3, dcfg-fl9er.5, dcfg-c75sy.3: PR later MERGED.
  - arwox-biz: GitHub Actions disabled; PR 1 and 3 MERGEABLE with 0 checks (atoms arwb-i0h, arwb-zad).

## Questions (answer each with file:line or receipt path)
Q1. Table of all `.failed` markers: exit code → count → 2 example receipt paths → last meaningful log line (`ship: ...`, `GraphQL`, `fatal`, `error:`).
Q2. For codes 30, 70, 130: split by real cause (log line). Which of them are a merge conflict, a late CI, Actions disabled, "No commits between" (content already in main), an interrupt (130)?
Q3. In the code: why does a conflicting PR end as code 30 "CI не появился" instead of 50? Cite the lines (expected-head path without rebase, `mergeable` read right after PR create, `ga_ci_wait` appear deadline `GA_CI_APPEAR`).
Q4. Does any code path close a `[ship-post] INFRA exit N` incident after its atoms are delivered? Cite `ack_delivery` and `park_atom`.
Q5. When an atom has a `.failed` marker with 10, 50 or 80 on the same head SHA and the atom is closed again, will the courier ever retry? Cite `scan_repo` lines.
Q6. Group all failures into clusters by root cause in code. Give each cluster: name, codes, count, share of all `.failed`, file:line.

## Output (plain text, this order)
1. Q1 table. 2. Q2 split. 3. Q3-Q5 answers, each with file:line. 4. Q6 clusters, sorted by count. 5. Line `COVERAGE: top-3 clusters = N of M markers (P%)`.

## Done check
Every number comes from files you globbed or grepped; every claim has file:line or a receipt path; anything you could not check is marked UNVERIFIED.

## Prohibitions
Read only. No edits, no network calls for repository state, no secrets (`/root/workspaces/secrets`, `.env`, keys), do not read `~/.ssh`, `/etc`, `.beads`.
