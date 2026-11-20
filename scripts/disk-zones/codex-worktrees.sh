#!/bin/bash
# Классификация worktree-ов Codex (зона codex-wt) для disk-rotate.
# spec:090 C3 / ADR-090-7 + CR-01. Только dry-run: ничего не удаляет.
#
# Для каждого подкаталога $DZ_CODEX_WT с .git выполняет проверки по порядку;
# первая проваленная задаёт state. Пишет строку в $DZ_ZONES_TSV.
set -u

DZ_CODEX_WT=${DZ_CODEX_WT:-/root/workspaces/projects/.worktrees/codex}
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_BD=${DZ_BD:-bd}

# Реальная уборка этой зоной не выполняется (CR-01: только dry-run).
if [ "${ZONE_MODE:-}" != dry-run ]; then
  echo "codex-worktrees: only ZONE_MODE=dry-run supported (got '${ZONE_MODE:-}')" >&2
  exit 2
fi

mkdir -p "$(dirname "$DZ_ZONES_TSV")"

ts=$(date +%Y-%m-%dT%H:%M:%S)

wt_guard() { # wt name -> 0, если ветка <зона>/<имя> и worktree связан с общим репозиторием
  local wt=$1 name=$2 branch zbase gitdir common top
  zbase=$(basename "$(dirname "${wt%/}")")
  branch=$(git -C "$wt" symbolic-ref --short -q HEAD 2>/dev/null) || return 1
  case $zbase in
    codex|claude) [ "$branch" = "$zbase/$name" ] || return 1 ;;
    *) [ "$branch" = "codex/$name" ] || [ "$branch" = "claude/$name" ] || return 1 ;;
  esac
  common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  gitdir=$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  case $gitdir in "$common"/worktrees/?*) [ -d "$gitdir" ] || return 1 ;; *) return 1 ;; esac
  top=$(git -C "$wt" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || return 1
  git --git-dir="$common" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $top"
}

classify() { # wt -> задаёт глобальные STATE, CLASS
  local wt=$1 name id status ltmp procbusy lrc
  STATE=kept-not-merged
  CLASS=И
  # 1. HEAD — предок origin/main (локальный ref, без fetch)
  git -C "$wt" merge-base --is-ancestor HEAD origin/main 2>/dev/null || return
  # 2. ignored содержимое не удаляем; ошибки status тоже оставляют worktree.
  if ! status=$(git -C "$wt" status --porcelain --ignored 2>/dev/null); then
    STATE=kept-dirty
    return
  fi
  if printf '%s\n' "$status" | grep -q '^!! '; then
    STATE=kept-ignored
    return
  fi
  if [ -n "$(printf '%s\n' "$status" | sed 's/^...//' | awk -F/ '
      { ok=0
        for (i=1;i<=NF;i++) if ($i=="node_modules"||$i==".venv"||$i=="__pycache__"||$i=="dist") ok=1
        if (!ok) print }')" ]; then
    STATE=kept-dirty
    return
  fi
  # 3. id атома из имени каталога (или codex/<атом>-<описание>) и статус закрыт
  name=$(basename "$wt")
  id=$(printf '%s' "$name" | sed -nE 's/^(dcfg-[a-z0-9.]+)$/\1/p')
  if [ -z "$id" ]; then
    id=$(printf '%s' "$name" | sed -nE 's/^(dcfg-[a-z0-9]+(\.[a-z0-9]+)*)-(.+)$/\1/p')
    if [ -z "$id" ]; then
      STATE=kept-no-atom
      return
    fi
    if ! wt_guard "$wt" "$name"; then
      STATE=kept-wt-mismatch
      return
    fi
  fi
  if ! status=$("$DZ_BD" show "$id" --json 2>/dev/null) \
     || ! jq -e --arg id "$id" 'any(.[]; .id == $id and .status == "closed")' <<<"$status" >/dev/null 2>&1; then
    STATE=kept-atom-open
    return
  fi
  # 4. Свободен только при rc=1 и нулевой длине обоих потоков.
  ltmp=$(mktemp -d /tmp/codex-wt-lsof.XXXXXX) || { STATE=kept-lsof-error; return; }
  lsof +D "$wt" >"$ltmp/out" 2>"$ltmp/err"
  lrc=$?
  cat "$ltmp/err" >&2
  procbusy=$(readlink /proc/*/cwd 2>/dev/null | grep -F "${wt%/}" || true)
  if [ -n "$procbusy" ]; then
    STATE=kept-busy
  elif [ "$lrc" -eq 1 ] && [ ! -s "$ltmp/out" ] && [ ! -s "$ltmp/err" ]; then
    STATE=candidate
    CLASS=У
  elif [ "$lrc" -eq 0 ] && [ -s "$ltmp/out" ]; then
    STATE=kept-busy
  else
    STATE=kept-lsof-error
  fi
  rm -f -- "$ltmp/out" "$ltmp/err"
  rmdir -- "$ltmp"
}

for wt in "$DZ_CODEX_WT"/*/; do
  [ -d "$wt" ] || continue
  [ -e "$wt/.git" ] || continue   # .git файл (worktree) или каталог (клон)
  classify "$wt"
  size=$(du -sm "$wt" 2>/dev/null | awk '{print $1}')
  size="${size:-0}"
  if [ "$STATE" = candidate ]; then
    after=0; freed=$size; rc=0
  else
    after=$size; freed=0; rc=1
  fi
  printf '%s\tcodex-wt\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "${wt%/}" "$CLASS" "$size" "$after" "$freed" "$rc" "$STATE"
done >>"$DZ_ZONES_TSV"

printf '%s\tcodex-wt\t-\t-\t-\t-\t-\t0\trun-done\n' "$ts" >>"$DZ_ZONES_TSV"
exit 0
