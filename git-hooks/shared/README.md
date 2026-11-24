# shared: the machine-wide hooks, versioned

Copies of the hooks that are installed machine-wide from `/root/workspaces/projects/.githooks`
(`core.hooksPath` in the global git config). They run for every repository on this server, for every
agent and every model, because no model participates.

- `commit-msg` — agent+model tag and the `Agent:` trailer (owner law 24.11).
- `pre-commit` — staged gitleaks scan; the `data/` rule for the agent-contour work tree only.
- `pre-push` — branch guards (no direct push to `main`/`master`, no branch delete without an
  `archive/<branch>-*` tag, no non-fast-forward) followed by the gitleaks scan of the pushed commits.
- `post-commit` — calls `auto-push.sh`.
- `post-merge` — post-merge step.
- `auto-push.sh` — the single copy of the auto-push logic (`git push -u origin HEAD`); opt-out for one
  commit: `GIT_AUTOPUSH_OFF=1`.

## Deploy

Copy back to the live location and keep the mode:

```sh
cp -p /root/workspaces/tools/git-hooks/shared/* /root/workspaces/projects/.githooks/
```

Verify: `git config --global --get core.hooksPath` prints `/root/workspaces/projects/.githooks`.

## Relation to this repository's dispatcher

`/root/workspaces/tools/git-hooks/` is a second, separate dispatcher (`dispatch` + symlinks) used by
repositories whose local `hooksPath` points here. It does not replace the files in `shared/`; its
`commit-msg` and `post-commit` paths call the live machine-wide hooks in
`/root/workspaces/projects/.githooks` by absolute path. Its `pre-push` path carries its own copy of the
same branch guards and gitleaks scan — keep the two `pre-push` copies in step when either changes.