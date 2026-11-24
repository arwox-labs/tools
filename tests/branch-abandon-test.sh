#!/usr/bin/env bash
# Exercise the installed wrappers against a private bare origin per case.
set -uo pipefail
bin=$(cd -- "$(dirname -- "$0")/../bin" && pwd -P) || exit 1
root=$(mktemp -d /tmp/branch-abandon.XXXXXXXX) || exit 1
trap 'rm -r -- "$root" </dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
pass=0 fail=0

die() { printf '%s\n' "$*" >&2; exit 1; }
same() { [[ $1 == "$2" ]] || die "$3: expected [$2], got [$1]"; }
remote() { git --git-dir="$origin" for-each-ref --format='%(objectname)' "refs/heads/$1"; }

fixture() {
    unset SAFE_DELETE_AGENT GIT_AUTOPUSH_OFF GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
    export SAFE_DELETE_BK="$dir/backup" SAFE_DELETE_GH=false
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=0
    export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 GIT_TEMPLATE_DIR="$dir/template"
    mkdir "$dir/template" "$dir/hooks" "$dir/bin"
    # Never contact GitHub. Only the PR cases provide a matching head or base.
    cat > "$dir/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ ${1:-} == pr && ${2:-} == list ]] || exit 1
while (($#)); do
    if [[ $1 == "${pr_side:-}" && ${2:-} == "$test_branch" ]]; then echo 42; fi
    shift
done
GH
    chmod +x "$dir/bin/gh"
    export PATH="$dir/bin:$PATH" test_branch="$br" pr_side=''
    git init -q --bare -b main "$origin"
    git init -q -b main "$repo"
    cd -- "$repo"
    git config user.name Test
    git config user.email test@example.invalid
    git config core.hooksPath "$dir/hooks"
    git remote add origin "$origin"
    git commit -q --allow-empty -m base
    git push -u origin main
}

topic() {
    git switch -qc "$br"
    if [[ $1 == unique ]]; then
        echo topic > topic
        git add topic
        git commit -qm topic
    fi
    git push -qu origin "$br"
    git switch -q main
}

invoke() {
    rc=0
    "$@" > "$dir/output" 2>&1 || rc=$?
}
refuse_branch() {
    local before reason=$1
    shift
    before=$(git rev-parse "refs/heads/$br")
    invoke "$bin/safe-delete" branch "$repo" "$br" "$@"
    same "$rc" 2 'safe-delete exit'
    same "$(remote "$br")" "$before" 'remote branch'
    same "$(git rev-parse --verify "refs/heads/$br")" "$before" 'local branch'
    if [[ -n $reason ]]; then
        grep -Eiq "$reason" "$dir/output" || die 'refused for a different reason'
    fi
}

verify_failure() {
    topic unique
    local tip
    tip=$(git rev-parse "$br")
    export real_git
    real_git=$(command -v git)
    export verify_probe="$dir/verify-called"
    cat > "$dir/bin/git" <<'GIT'
#!/usr/bin/env bash
args=("$@")
while (($#)); do
    case $1 in
        -C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--shallow-file|--attr-source)
            (($# >= 2)) || break
            shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
if [[ ${1:-} == bundle && ${2:-} == verify ]]; then
    echo rejected > "$verify_probe"
    exit 1
fi
exec "$real_git" "${args[@]}"
GIT
    chmod +x "$dir/bin/git"
    invoke "$bin/safe-delete" branch "$repo" "$br" --abandon
    [[ -f $verify_probe ]] || die 'wrapper did not attempt git bundle verify'
    ((rc != 0)) || die 'wrapper accepted failed bundle verification'
    same "$(remote "$br")" "$tip" 'remote branch after verification failure'
    same "$(git rev-parse "$br")" "$tip" 'local branch after verification failure'
}

archive() {
    topic unique
    local tip ledger record tag bundle checksum deleted
    tip=$(git rev-parse "$br")
    invoke "$bin/safe-delete" branch "$repo" "$br" --abandon
    same "$rc" 0 'safe-delete exit'
    same "$(remote "$br")" '' 'remote branch after abandon'
    ledger="$SAFE_DELETE_BK/ledger.tsv"
    # Match this exact object and tip. Restore by the actual deleted-row number.
    record=$(awk -F '\t' -v obj="$repo:$br" -v sha="$tip" '
        $2=="branch" && $3==obj && $4==sha {
            if ($8=="backup-ok") { b=NR; tag=$5; file=$6; sum=$7 }
            if ($8=="deleted" && b && $5==tag && $6==file && $7==sum) d=NR
        }
        END { if (!(b && d>b)) exit 1; print tag "\t" file "\t" sum "\t" d }
    ' "$ledger") || die 'missing matching backup-ok and deleted rows'
    IFS=$'\t' read -r tag bundle checksum deleted <<< "$record"
    [[ $tag == archive/* ]] || die "invalid archive tag: $tag"
    same "$(git --git-dir="$origin" rev-parse "refs/tags/$tag^{commit}")" "$tip" 'archive tag tip'
    [[ $bundle == *.bundle && -s $bundle ]] || die "missing bundle: $bundle"
    git bundle verify "$bundle" >/dev/null 2>"$dir/verify" || die "$(cat "$dir/verify")"
    git bundle list-heads "$bundle" | awk -v sha="$tip" '$1==sha {found=1} END {exit !found}' ||
        die 'bundle does not contain the abandoned tip as a head'
    same "$(sha256sum < "$bundle" | cut -d' ' -f1)" "$checksum" 'ledger SHA-256'
    if [[ $1 == restore ]]; then
        invoke "$bin/safe-delete" restore "$deleted"
        same "$rc" 0 'restore exit'
        same "$(remote "$br")" "$(awk -F '\t' -v n="$deleted" 'NR==n {print $4}' "$ledger")" 'restored tip'
    fi
}

revert_env() {
    topic unique
    git merge -q --no-ff "$br" -m merge
    git push -q origin main
    local merge export_line branch
    merge=$(git rev-parse HEAD)
    branch="fix/codex/revert-$(git rev-parse --short HEAD)"
    cat > "$dir/hooks/post-commit" <<'HOOK'
#!/bin/sh
printf '%s %s\n' "$(git rev-parse HEAD)" "${GIT_AUTOPUSH_OFF-unset}" >> "$hook_log"
HOOK
    chmod +x "$dir/hooks/post-commit"
    export hook_log="$dir/hook.log"
    export_line=$(grep -n 'GIT_AUTOPUSH_OFF' "$bin/safe-revert" |
        grep -E '^[0-9]+:[[:space:]]*export[[:space:]]+GIT_AUTOPUSH_OFF=1([[:space:]#;]|$)') || export_line=''
    invoke "$bin/safe-revert" "$repo" "$merge"
    if [[ $rc == 2 ]] && grep -Eq 'нет доверенных данных PR для origin|принадлежность merge не подтверждена данными PR' "$dir/output"; then
        [[ ! -e $hook_log ]] || die 'post-commit ran despite PR refusal'
        same "$(git rev-parse HEAD)" "$merge" 'HEAD after PR refusal'
        echo 'INFO revert_env: PR data refused; environment checked by grep only'
    else
        same "$rc" 0 'safe-revert exit'
        same "$(git branch --show-current)" "$branch" 'revert branch'
        same "$(git rev-parse HEAD^)" "$merge" 'revert parent'
        same "$(git rev-parse 'HEAD^{tree}')" "$(git rev-parse "$merge^1^{tree}")" 'reverted tree'
        same "$(cat "$hook_log")" "$(git rev-parse HEAD) 1" 'post-commit observation'
        echo 'INFO revert_env: post-commit observed GIT_AUTOPUSH_OFF=1'
    fi
    same "$(remote "$branch")" '' 'remote revert branch'
    [[ -n $export_line ]] || die 'grep found no export GIT_AUTOPUSH_OFF=1 in safe-revert'
}

run_case() {
    local name=$1 br=$2 kind=$3 dir="$root/$1" repo="$root/$1/repo" origin="$root/$1/origin.git"
    mkdir -- "$dir" || exit 1
    (
        set -e
        fixture >"$dir/setup" 2>&1
        case $kind in
            default) topic unique; refuse_branch '' ;;
            abandon|restore) archive "$kind" ;;
            verify_failure) verify_failure ;;
            merged) topic merged; refuse_branch '' --abandon ;;
            protected)
                if [[ $br == main ]]; then git switch -q --detach; else topic unique; fi
                refuse_branch '' --abandon ;;
            foreign) topic merged; export SAFE_DELETE_AGENT=claude; refuse_branch 'чужая|foreign|agent mismatch' --abandon ;;
            worktree) topic unique; git worktree add -q "$dir/linked" "$br"; refuse_branch 'зачекаутена|checked out|worktree' --abandon ;;
            pr) topic unique; export SAFE_DELETE_GH=true pr_side="$4"; refuse_branch 'открытые PR|open (PR|pull request)' --abandon ;;
            invalid)
                topic unique
                before=$(git --git-dir="$origin" show-ref)
                invoke "$bin/safe-delete" branch "$repo" "$4" --abandon
                same "$rc" 2 'invalid ref exit'
                same "$(git --git-dir="$origin" show-ref)" "$before" 'origin refs' ;;
            revert) revert_env ;;
        esac
    ) >"$dir/check" 2>&1
    local status=$?
    if ((status == 0)); then
        cat "$dir/check"
        printf 'PASS %s\n' "$name"
        pass=$((pass+1))
    else
        printf 'FAIL %s: ' "$name"
        if [[ -s $dir/check ]]; then cat "$dir/check"; else cat "$dir/setup"; fi
        if [[ -s $dir/output ]]; then cat "$dir/output"; fi
        fail=$((fail+1))
    fi
}

for br in codex/topic claude/topic opencode/topic feat/codex/topic fix/claude/topic chore/opencode/topic; do
    run_case "default_${br//\//_}" "$br" default
done
run_case abandon codex/topic abandon
run_case restore codex/topic restore
run_case failed_bundle_verify codex/topic verify_failure
run_case merged_no_bundle codex/topic merged
for br in main dev master develop release/1; do run_case "protected_${br//\//_}" "$br" protected; done
run_case foreign_agent codex/topic foreign
run_case linked_worktree codex/topic worktree
run_case open_pr_head codex/topic pr --head
run_case open_pr_base codex/topic pr --base
run_case invalid_ref codex/topic invalid 'codex/topic..bad'
run_case protected_HEAD codex/topic invalid HEAD
run_case revert_env codex/topic revert
printf 'итог: PASS %d, FAIL %d\n' "$pass" "$fail"
((fail == 0))
