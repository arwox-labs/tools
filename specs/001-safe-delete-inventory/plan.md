# Implementation plan

Use the existing command, argument handling, permitted-root checks, backups and ledger. Keep inventory handling separate from deletion authorization; add the least state and logic required. Prefer Bash/coreutils already used; use an installed standard-library runtime only when clearly simpler. Do not create a separate wrapper or service.
Implement init with --fast as a reuse option, not a relaxed security option. Keep stored paths safely delimited, reject corrupt state, make state replacement atomic, and avoid following directory symlinks. Counters/logs must be accurate.
Review existing command and regression tests first. Write focused acceptance tests before behavior changes in an existing safe-delete test file; do not run any live destructive operation. Add deterministic tests for the new modes and for unchanged guards.
Deliver a scoped tools PR, review and run relevant existing tests. Before live installation preserve/check the actual dirty preimage and apply only this task delta; do not replace unrelated concurrent edits. Roll back only this delta if integration verification fails.
