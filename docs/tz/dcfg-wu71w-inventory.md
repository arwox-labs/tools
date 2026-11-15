# safe-delete inventory implementation

Goal: implement specs/001-safe-delete-inventory/spec.md and plan.md using the existing command. You are a bounded executor, not an orchestrator; do not create Goals, tasks, workers, PRs, commits or dispatch other agents.
FILE: bin/safe-delete
FILE: bin/safe-delete-rerun-test
Allowed changes: only those two files. Read them and existing focused tests first. Keep English instruction/comment text; preserve existing comments unchanged. KISS, YAGNI, SoC, least code; no wrapper, service, installed dependency, permission changes or guard weakening.
Implement manual init [--fast] <root>, observational directory metadata only. Existing safety guards remain authoritative on every deletion. Never grant deletion permission from the inventory. Do not follow symlinks, read credential contents, or traverse protected subtrees. Explicitly report incomplete scans; atomically replace only successful inventory. --fast reuses existing compatible state and says reused; absent/corrupt state must give clear full-init guidance.
No mandatory initialization or auto-init. Without an initialized map preserve the old CLI. Unknown directories encountered by normal delete commands should produce advisory refresh guidance; any 30-percent figure must mean distinct observed unknown directory paths / initialized directory count, not unseen changes. Do not add extra status commands or options beyond necessary init/--fast.
Write failing focused acceptance before implementation in the existing rerun test. Test on disposable test roots only, using the existing SAFE_DELETE_ROOTS/BK test contract. Include clean allowed deletion+restore and protected-name/symlink refusals. Do not touch real fixtures from dcfg-so22w or the live /root/workspaces/tools checkout.
Do not run the full large stress suite during authoring. Run the focused existing rerun suite and bash syntax check once, rerunning only failed checks after a demonstrated correction. Retain exact evidence of baseline, final checks, changed files, limitations and runtime. No secret values or raw environment dumps.
Do not delete task evidence or worktrees. Return a concise factual report, not a success claim based only on edited files.
Test: bash bin/safe-delete-rerun-test
