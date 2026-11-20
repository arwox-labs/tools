---
title: Introduce the code-agent command
type: feature
date: 2026-11-20
issue: tools-aaj
---

## Product contract

Requirements: [Feature 002](../../specs/002-code-agent/spec.md).

The lead delegates coding through the installed code-agent wrapper. OpenCode is its underlying CLI. Existing code-channel callers keep their exit codes, argument handling and state. The public command is singular. The owner chose code-agent; code-worker is a reserved naming alternative only.

## Architecture and scope

Expose two names for one executable in bin/. Use a relative link if both names resolve support files correctly, or a minimal exec entry point that preserves argv, exit status and signals. Keep internal filenames, CODE_CHANNEL settings, lock identity, journals and runtime configuration stable. Both names must pass the same dispatch checks, including guarded paths and subcommands. Account for either name exactly once in a transcript. Direct OpenCode execution is not an alternate lead workflow.

Leave archive/, historical specs, old plans and other projects untouched. Put the recovery instruction in the live agent instructions, with a pointer from the active guide where useful. An agent restoring an archive must preserve the original, recognize code-channel as legacy, use an old wrapper only if recovery requires it, and migrate active calls in the restored working copy to the installed code-agent before resuming development. Verify the restored command resolves to the current installation.

## Ordered work

1. Inspect the existing implementation, current usage, guard, accounting and active callers in the isolated worktree. Check which files resolve paths relative to the executable and distinguish historical evidence from operational routing.
2. Introduce the canonical executable and preserve the legacy interface. Update consuming checks, emitted guidance, help, registry and active documentation; resolve direct-OpenCode instructions. Use the existing offline mechanisms and preserve compatibility for installed local consumers.
3. Add regression coverage for parity, guard, transcript accounting, and the documentation contract. Keep automated tests offline and isolated from the live service.
4. Review the diff independently, including old and new spellings in paths, the deployment boundary and the preserved archives. Ship only task-owned files from the isolated topic branch.

## Acceptance and delivery

Run bash bin/code-agent-compat-test and bash bin/code-channel-test, plus the affected existing offline guard and accounting checks. The focused suite must demonstrate matching offline --plan output or semantic result, argument/error behavior and exit status, equal guard decisions for each name, and one counted helper call per invocation. Verify that the active guide and registry select the installed code-agent and that the recovery rule is visible from the repository instructions. Verify git diff --exit-code origin/main...HEAD -- archive docs/tz and confirm that the only specs change is the new feature contract; then run git diff --check. A reviewed PR and checks on the submitted revision establish repository delivery. Verify availability in the launch checkout separately; apply only the accepted delta when existing unrelated edits can be preserved. A live provider invocation is unnecessary for a dispatch-name change.

## Rollback

Revert the topic change as a unit, preserving the previous wrapper executable, configuration, journals and archived data. On the live checkout, reverse only the applied task delta.
