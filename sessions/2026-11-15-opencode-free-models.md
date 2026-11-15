# OpenCode model selection — dcfg-2mx04

Owner authorized publishing the scoped selector/configuration/test fix to arwox-labs/tools and automatic GitHub delivery. No credentials or personal configuration are included.

Goal: existing code-channel accepts the explicitly approved free/default and BitrixGPT alternatives; arbitrary models remain rejected. Personal connection and exhausted Go allowance must not prevent an approved free model call. The default changes only on owner instruction.

Plan: use the existing selector/configuration; extend a finite alternative list only where required; preserve existing validation and all unrelated restrictions; add regression coverage to the existing test; verify real execution and deliver the reviewed scoped diff. Parent coordinator owns native Goal and Beads dcfg-2mx04; no executor creates either.

Acceptance: approved override succeeds; unlisted override fails before execution; existing tests pass; real configured call returns its marker; exact merged files match installed runtime. Rollback restores only the saved pre-change versions of affected files.

Status: preparation checkpoint; implementation and acceptance pending.

## Verification checkpoint

Independent report-only review found no scoped correctness defect; five product files, tests and global JSONC baseline diff inspected. Valid Bitrix 5.6/6.0, arbitrary model rejection and malformed allowlists have regression coverage. Directory wildcard broadening is intentional; review alone does not prove all directories. Real OpenCode 2.2.7 calls returned GLOBAL_FREE_READY from /root and BITRIX6_READY through the installed personal provider, both rc0. File editing produced DIRECTORY_WRITE_READY in a disposable task fixture. No paid Go or SDK verification used.

Selected architecture: retain existing code-channel and native global OpenCode config; explicit finite model alternatives, no automatic paid fallback. Kimi is future integration only; its current authentication was not changed. Other host sandbox permissions are outside this patch.

Regression evidence: TMPDIR=<private task scratch> timeout 60s bash bin/code-channel-test completed rc0, PASS 102 checks; existing guard, fallback and permit cases retained. Independent report-only reviewer returned no findings. Product diff check passed.

## Live acceptance limit

All 102 regression checks and GitHub tools-smoke passed. A real OpenCode 2.2.7 wrapper run completed inference and its requested marker check, but reconciliation returned rc23: expected provider opencode-go, actual unknown. Direct native model calls work; the wrapper remains incomplete. Do not merge as an end-to-end fix until native session reconciliation is corrected and verified by a real wrapper run. The prerequisite metadata inspection was denied by current host policy; no bypass attempted.
