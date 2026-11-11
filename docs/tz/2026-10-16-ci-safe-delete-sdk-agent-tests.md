# TZ dcfg-b52sn — tools CI runs safe-delete and sdk-agent tests

Why: owner 16.10 forbade local test runs by the lead; the only test gate is GitHub CI on the courier PR. `.github/workflows/tools-smoke.yml` runs `bin/code-channel-test` (line 32) but not `bin/safe-delete-test` nor `bin/sdk-agent-test`.
Index: not needed (one YAML file). Principles: KISS, minimal diff.

## U1 — .github/workflows/tools-smoke.yml
Skills: caveman:surgical-patch (one file), ponytail:ponytail (minimal change)
1. Right after the step `- run: bash bin/code-channel-test`, add two steps with the same indentation:
   `- run: bash bin/safe-delete-test`
   `- run: bash bin/sdk-agent-test`
2. Change nothing else in the file. Do not edit or run any test file.

Files: `.github/workflows/tools-smoke.yml`
