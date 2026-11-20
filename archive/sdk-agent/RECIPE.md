# Claude Agent SDK — run recipe

Runs are paid (API key) and start only with the owner's permission. The wrapper
is `tools/bin/sdk-agent`; never call the engine directly.

## Daily cap

Daily cap 22.00 USD across all agents (`/root/CLAUDE.md`). Per-run budget is
0.50 USD by default, ceiling 2.00 USD. A run over the remaining cap is refused
with rc 6 before any budget is reserved. Every result is appended to
`tools/sdk-agent/runs.jsonl`.

## Prompt file (frozen prefix)

`sdk-agent/system-prompt.md` holds the role, TZ protocol, bans and output
format. The wrapper passes it with `--append-system-prompt-file` for `ask`,
`code`, `read` and `bench`; the per-run user text carries only the task and
file bodies. Keep the file free of dates and per-run values so the cached
prefix stays stable.

## Memory files stay out of the user message

The wrapper starts the engine with `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`. Source:
<https://code.claude.com/docs/en/env-vars.md> — "Set to `1` to prevent loading
any CLAUDE.md memory files into context, including user, project, and auto
memory files". Without it, `--exclude-dynamic-system-prompt-sections` moves the
memory files (`~/.claude/CLAUDE.md`, project `CLAUDE.md`/`AGENTS.md`) into the
first user message after the system-prompt cache breakpoint, so every run
re-writes them. With the switch, memory is not loaded at all and the stable
text comes from `system-prompt.md` inside the cached prefix.

`--bare` also skips CLAUDE.md discovery (help line: "skip ... CLAUDE.md
auto-discovery"), but it sets `CLAUDE_CODE_SIMPLE=1`: docs say it runs "with a
minimal system prompt and only the Bash, file read, and file edit tools" and
"disables auto-discovery of hooks, skills ...". That would drop the tools and
skills the wrapper relies on, so the env var is used instead.

## Cache bench

Three sequential read runs in the same worktree, fixed budget 0.05 USD and tag
`cache_bench`:

```
sdk-agent bench WORKTREE TZ1 TZ2 TZ3
sdk-agent bench-check --tag cache_bench
```

`bench-check` exits 0 only when the last 3 records tagged `cache_bench` are
success and runs 2-3 each have `cache_read/cache_write >= 10` (write 0 passes);
otherwise it exits 1 with a reason line. The first run is expected to write the
cache, so only runs 2-3 are graded.

## Tagging

`--tag NAME` (or `SDK_AGENT_TAG`) is recorded as `tag` in the runs log. `bench`
sets `cache_bench` itself.
