# safe-delete manual inventory

Task: dcfg-wu71w. Native Goal active. Start 2026-11-15T14:17:59Z; deadline 14:37:59Z.
Scope and acceptance: specs/001-safe-delete-inventory/spec.md. Plan and ordered units are adjacent.
Selected methods: KISS/YAGNI reuse the existing command; SoC separates observational inventory from authorization; ADR/MoSCoW records manual init as required, fast reuse and accurate refresh guidance as required, background scanning and authorization expansion as excluded.
Assumption for execution: owner ordered implementation after the recommended observational-map option; no new deletion authority is inferred.
Live tools checkout has preexisting uncommitted edits including bin/safe-delete. They are not this task's changes and must not be overwritten or committed. Implementation uses an isolated worktree from verified origin/main 07d177a88b7b15a266eff898b040381569faaebf.
No tests, implementation or deployment have been claimed complete.
