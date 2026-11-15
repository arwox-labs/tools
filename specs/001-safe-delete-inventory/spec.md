# Manual safe-delete inventory

Owner request: repair and review the existing safe deletion command, with manual initialization and a fast mode.
The inventory describes directories; it never authorizes deletion or bypasses any protected path/name, live canonicalization, symlink, recovery or concurrency check.
Users explicitly initialize one permitted directory root. Only directory metadata is collected; protected subtrees are recorded as excluded boundaries; symlinks are not followed. Fail incomplete scans honestly and preserve the preceding complete inventory.
Fast mode reuses an existing inventory for the same canonical root and reports reuse; it never claims a fresh full scan. Missing or incompatible state gives an actionable full-initialization instruction.
When deletion encounters directory paths absent from an initialized root inventory, emit manual-refresh guidance. An observed-drift percentage may be offered at 30 percent; it measures distinct encountered unknown directories against the baseline, not all unseen filesystem changes. Without inventory all existing deletion behavior continues.
No background scanning, watcher, auto-init, new package, policy edits, or mandatory initialization gate.
Accept on real disposable fixtures: initialization, fast reuse, unknown-directory guidance, denied protected name, symlink-boundary rejection, permitted deletion and recovery. Existing concurrent live edits remain intact.
