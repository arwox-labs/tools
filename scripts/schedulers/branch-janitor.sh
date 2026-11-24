#!/usr/bin/env bash
# branch-janitor: remove zombie remote branches (merged into origin base, older than 7 days)
# through /root/workspaces/tools/bin/safe-delete only.
# usage: branch-janitor.sh [dry|run]   (default dry)
set -uo pipefail

mode=${1:-dry}
case $mode in
  dry) do_delete=0 ;;
  run) do_delete=1 ;;
  *) echo "usage: branch-janitor.sh [dry|run]" >&2; exit 1 ;;
esac

repos=${JANITOR_REPOS:-/root/workspaces/projects/incidents:/root/workspaces/tools}
age_limit=$((7 * 24 * 3600))
wrapper=/root/workspaces/tools/bin/safe-delete
now=$(date +%s)
hard_error=0
t_cand=0 t_del=0 t_ref=0

repo_of() {
  local url=$1 p
  url=${url%.git}
  if [[ $url =~ ^git@[^:]+:(.+)$ ]]; then p=${BASH_REMATCH[1]}
  elif [[ $url =~ ^https?://[^/]+/(.+)$ ]]; then p=${BASH_REMATCH[1]}
  elif [[ $url =~ ^ssh://[^/]+/(.+)$ ]]; then p=${BASH_REMATCH[1]}
  else return 1; fi
  [[ $p == */*/* ]] || [[ $p =~ ^[^/]+/[^/]+$ ]] || return 1
  printf '%s\n' "$p"
}

IFS=: read -r -a repo_list <<<"$repos"
for repo in "${repo_list[@]}"; do
  [[ -n $repo ]] || continue
  cand=0 deleted=0 refused=0 open_pr=0
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "repo=$repo error=not-a-git-repo" >&2
    hard_error=1
    continue
  fi
  if ! git -C "$repo" fetch -q origin 2>/dev/null; then
    echo "repo=$repo error=fetch-failed" >&2
    hard_error=1
    continue
  fi

  base=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || base=
  if [[ -z $base ]]; then
    for b in main master; do
      if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null; then
        base="origin/$b"
        break
      fi
    done
  fi
  if [[ -z $base ]]; then
    echo "repo=$repo warn=no-base skip" >&2
    echo "repo=$repo candidates=0 deleted=0 refused=0 skipped_open_pr=0"
    continue
  fi

  url=$(git -C "$repo" remote get-url origin 2>/dev/null) || url=
  rr=$(repo_of "${url:-}") || rr=

  while read -r br; do
    br=${br#origin/}
    [[ -n $br ]] || continue
    [[ $br == dev || $br == develop || $br == release/* ]] && continue
    [[ $br =~ ^(codex|claude|opencode)/ ]] || [[ $br =~ ^(feat|fix|chore)/(codex|claude|opencode)/ ]] || continue
    ct=$(git -C "$repo" log -1 --format=%ct "refs/remotes/origin/$br" 2>/dev/null) || continue
    [[ -n $ct ]] || continue
    (( now - ct > age_limit )) || continue
    cand=$((cand + 1))

    open=0
    if [[ -n $rr ]]; then
      h=$(gh pr list --repo "$rr" --head "$br" --state open --json number -q '.[].number' 2>/dev/null) || h=
      b=$(gh pr list --repo "$rr" --base "$br" --state open --json number -q '.[].number' 2>/dev/null) || b=
      [[ -z $h && -z $b ]] || open=1
    else
      echo "warn: repo of origin not parsed: ${url:-none}" >&2
    fi
    if ((open)); then
      open_pr=$((open_pr + 1))
      continue
    fi

    if ((do_delete)); then
      if SAFE_DELETE_AGENT= SAFE_DELETE_GH=true "$wrapper" branch "$repo" "$br" >/dev/null 2>&1; then
        echo "deleted: $repo $br"
        deleted=$((deleted + 1))
      else
        echo "refused: $repo $br"
        refused=$((refused + 1))
      fi
    else
      echo "[dry] would delete: $repo $br (age $(( (now - ct) / 86400 ))d)"
    fi
  done < <(git -C "$repo" branch -r --merged "$base" 2>/dev/null)

  echo "repo=$repo candidates=$cand deleted=$deleted refused=$refused skipped_open_pr=$open_pr"
  t_cand=$((t_cand + cand)); t_del=$((t_del + deleted)); t_ref=$((t_ref + refused))
done

echo "total candidates=$t_cand deleted=$t_del refused=$t_ref mode=$mode"
exit $hard_error