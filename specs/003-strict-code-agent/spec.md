# Require the installed code-agent executable

The lead must delegate live work through the regular executable at /root/workspaces/tools/bin/code-agent. This supersedes the dual-entry requirement of feature 002. Keep the current OpenCode runtime, settings, lock namespace and journal. The old live entry must exit with a nonzero status and print the canonical path before doing any work for every invocation, including help and audit. Archived snapshots remain unchanged. Restore data into a working copy and update its callers before use. Never launch a restored legacy wrapper.

Operational callers, hook decisions, tests, current guides and agent instructions must select the new path. Historical transcripts may continue to count historical helper activity. A passing migration requires the deployed canonical executable to function from another project's working directory without relying on PATH. Verify offline, including an invalid legacy audit that must never reach provider setup.
