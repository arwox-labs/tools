#!/bin/sh
# AUTO-GITHUB (owner 08.11) - the ONE implementation of "every commit reaches GitHub by itself".
#
# Two hook entry points call this same file instead of carrying their own copy:
#   1. /root/workspaces/projects/.githooks/post-commit  - global core.hooksPath, covers every repository
#      that has no local override.
#   2. /root/workspaces/tools/git-hooks/dispatch        - the post-commit branch, covers repositories whose
#      local core.hooksPath points at the shared dispatcher (agent-contour, tools).
# Git runs exactly one hooks directory per repository, so the two entry points never fire together.
#
# It can never block a commit: git ignores the exit status of post-commit, and every failure is recorded.
# Opt out for one commit: GIT_AUTOPUSH_OFF=1. Log: /tmp/git-autopush.log.

[ -n "$GIT_AUTOPUSH_OFF" ] && exit 0

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || exit 0
[ -n "$branch" ] || exit 0
[ "$branch" = "data/live" ] && exit 0

gdir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
[ -d "$gdir/rebase-merge" ] && exit 0
[ -d "$gdir/rebase-apply" ] && exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || root=?
git remote get-url origin >/dev/null 2>&1 || exit 0

if ! timeout 120 git push -u origin HEAD >>/tmp/git-autopush.log 2>&1; then
  printf 'autopush FAILED %s %s %s\n' "$(date -u +%FT%TZ)" "$root" "$branch" >>/tmp/git-autopush.log 2>/dev/null
fi
exit 0
