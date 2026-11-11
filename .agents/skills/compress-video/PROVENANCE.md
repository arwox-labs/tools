# compress-video - provenance

Upstream: https://github.com/pixel-point/skills (`skills/compress-video`)
Author: Pixel Point, MIT License (see `LICENSE` in this directory).
Pinned commit: `aa105343f9ccae65615280001bad00d18de6d882`
Vendored: 2026-11-11, unmodified copy of `SKILL.md` + `references/` + `LICENSE`.

## Wiring into agents (one body, symlinks / one config line)

| Agent | Entry point |
|---|---|
| Claude Code | `/root/.claude/skills/compress-video` -> this directory |
| Codex | `/root/.codex/skills/compress-video` -> this directory |
| OpenCode | `/root/.agents/skills/compress-video` -> this directory |
| Kimi Code | `/root/.kimi-code/config.toml`: `extra_skill_dirs` += `/root/workspaces/tools/.agents/skills` |

## Prerequisite

`ffmpeg` and `ffprobe` on PATH (present: ffmpeg 6.1.1-3ubuntu5).

## Update

Re-clone upstream, copy `skills/compress-video` over, update the pinned commit
above, re-run the checks below.

## Checks

```sh
sha256sum /root/workspaces/tools/.agents/skills/compress-video/SKILL.md
readlink -e /root/.claude/skills/compress-video /root/.codex/skills/compress-video /root/.agents/skills/compress-video
python3 -c "import tomllib;print(tomllib.load(open('/root/.kimi-code/config.toml','rb'))['extra_skill_dirs'])"
```

## Not used

`npx skills add pixel-point/skills --skill compress-video` - the installer CLI is not
part of this contour; the body is vendored so every update stays reviewable.
