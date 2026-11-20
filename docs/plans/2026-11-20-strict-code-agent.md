# Strict code-agent cutover

Beads tools-d5m. Product contract: [Feature 003](../../specs/003-strict-code-agent/spec.md).

1. Move the current implementation to the canonical filename. Replace the old entry with a minimal refusal naming the absolute installed path. Preserve process status for canonical callers, existing state and configuration. Keep the archive unmodified.
2. Inspect operational invocations including canaries, hooks, scripts and jobs. Migrate live default commands and guide examples. Make agent-facing directions use the absolute canonical path when launched outside this repository. Preserve historical filenames and historical accounting where they carry data.
3. Change offline regression gates from alias parity to strict refusal. Exercise canonical help and plan, legacy audit refusal before a valid dispatch, guard behavior for both names, existing wrapper functionality and affected callers.
4. Verify current-branch CI and independent review, submit the scoped PR, and apply only the accepted delta to the live checkout preserving unrelated changes. Verify both installed paths from the projects cwd and the unchanged archive. Record any instructions outside this repository that still require migration with their exact scope.

Rollback is the inverse of this scoped patch, which would re-enable legacy dispatch and therefore requires owner authorization. Do not roll back the prohibition automatically.
