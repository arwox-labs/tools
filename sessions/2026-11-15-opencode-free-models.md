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

## Reconciliation root cause and correction

The installed release v2.2.7 declares SessionTable as session_v2, with model.providerID and model.id unchanged. Primary source: https://github.com/anomalyco/opencode/blob/v2.2.7/packages/core/src/session/sql.ts ; blob 8684925220d9edeecdb066ca1b2d82afe4f46359. Four wrapper queries still target the legacy session table. Existing test fixture accepted any query and concealed this incompatibility. The bounded correction changes those four reads and makes the fixture reject legacy table queries. No database migration, host policy change, credential change or new component. Acceptance remains a real wrapper run with exact provider/model reconciliation, affected regression and independent review, then verified delivery.

Behavioral correction evidence: stricter fixture before production correction: 62 failing checks, 42 passing, rc1. After installing the four-query correction, the original real wrapper operation completed rc0, run=0, retries=0, provider opencode-go, model opencode-go/longcat-2.5-free; requested marker shell check rc0. Installed bin/code-channel SHA256 e3a0f54c48d3ed88e27b321bbd20ed973e5e8f1ec37ce8c680f93f27764a3012 matches reviewed worktree bytes. Native metadata data was not exposed or copied. Earlier reconciliation failure is resolved; earlier pending statements describe historical checkpoints.

Final local checks: corrected regression completed rc0, PASS 102 checks; bash syntax and diff whitespace checks passed. Independent affected-diff reviewer found no issues in four query substitutions and the strict fixture guard. Real installed wrapper journal proves provider_expected=provider_actual=opencode-go, model_actual=longcat-2.5-free, rc=0, retries=0. Delivery verification remains the only current unfinished criterion.
