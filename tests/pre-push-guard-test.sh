#!/bin/bash
# pre-push branch guard: semantic ref check in git-hooks/dispatch.
#
# Fixtures never push main through the hook: direct push to main is refused by
# design, so a setup push would test the gate instead of the case under test.
# main is seeded into the bare origin by moving objects with a plain branch
# push (to a throwaway legacy name the hook accepts) and then pointing
# refs/heads/main at that commit with git update-ref. The hook only ever sees
# the pushes under test.
set -u
HOOKS="$(cd "$(dirname "$0")/../git-hooks" && pwd -P)"
G="$(mktemp -d -p /var/tmp)"
X="$(mktemp -d)"
trap 'rm -rf -- "$G" "$X"' EXIT
ok=0
fail=0
pass() { ok=$((ok+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1: $2"; }

git init -q --bare "$G/r.git"
git init -q --bare "$X/r.git"
git clone -q "$G/r.git" "$G/w"
cd "$G/w" || exit 1
echo a >f
git add f
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git branch -M main
err="$G/err"

# --- seed origin/main out of band -------------------------------------------
# A plain branch push transfers the objects; the ref is then pointed at that
# same commit, so nothing in this setup step is a direct push of main.
git branch claude/seedxy main
if ! git -c core.hooksPath="$HOOKS" push -q origin claude/seedxy 2>"$err"; then
	echo "setup: seeding objects failed: $(cat "$err")" >&2
	exit 1
fi
main_sha=$(git rev-parse main)
if ! GIT_DIR="$G/r.git" git update-ref refs/heads/main "$main_sha"; then
	echo "setup: seeding origin/main failed" >&2
	exit 1
fi
git -c core.hooksPath="$HOOKS" push -q origin --delete claude/seedxy 2>/dev/null
if [ "$(git ls-remote origin refs/heads/main | cut -f1)" != "$main_sha" ]; then
	echo "setup: origin/main not seeded" >&2
	exit 1
fi
git branch -D claude/seedxy >/dev/null 2>&1
git branch claude/xy
# ----------------------------------------------------------------------------

# 1. push_new
if git -c core.hooksPath="$HOOKS" push -q origin claude/xy 2>"$err"; then pass push_new; else bad push_new "rc=$? $(cat "$err")"; fi

# 2. fast_forward
git checkout -q claude/xy
echo b >>f
git -c user.name=t -c user.email=t@example.invalid commit -qam ff
if git -c core.hooksPath="$HOOKS" push -q origin claude/xy 2>"$err"; then pass fast_forward; else bad fast_forward "rc=$? $(cat "$err")"; fi

# 3. delete_no_tag
if git -c core.hooksPath="$HOOKS" push origin --delete claude/xy 2>"$err"; then
	bad delete_no_tag "push succeeded"
elif grep -q "no archive tag" "$err" && [ -n "$(git ls-remote origin refs/heads/claude/xy)" ]; then
	pass delete_no_tag
else
	bad delete_no_tag "rc=$? stderr=$(cat "$err")"
fi

# 4. non_ff
git reset -q --hard HEAD^
before=$(git ls-remote origin refs/heads/claude/xy | cut -f1)
if git -c core.hooksPath="$HOOKS" push --force origin claude/xy 2>"$err"; then
	bad non_ff "push succeeded"
elif grep -q "non-fast-forward" "$err" && [ "$(git ls-remote origin refs/heads/claude/xy | cut -f1)" = "$before" ]; then
	pass non_ff
else
	bad non_ff "rc=$? stderr=$(cat "$err")"
fi

# 5. delete_main
# origin/main is seeded out of band, so this asserts the protection itself:
# deleting the protected branch is refused even when its archive tag exists.
git -c core.hooksPath="$HOOKS" push -q origin "$main_sha:refs/tags/archive/main-20261022" 2>"$err"
if git -c core.hooksPath="$HOOKS" push origin :main 2>"$err"; then
	bad delete_main "push succeeded"
elif grep -q "delete of main refused" "$err" && [ -n "$(git ls-remote origin refs/heads/main)" ]; then
	pass delete_main
else
	bad delete_main "rc=$? stderr=$(cat "$err")"
fi

# 6. non_ff_seeded_main
# a direct push to main is refused by design, whatever the history looks like.
# A commit is required first: an unchanged main makes git say
# "Everything up-to-date" and never invokes the hook at all.
git checkout -q main
echo n >n
git add n
git -c user.name=t -c user.email=t@example.invalid commit -qm newmain
if git -c core.hooksPath="$HOOKS" push origin main 2>"$err"; then
	bad non_ff_seeded_main "push succeeded"
elif grep -q "direct push to main refused" "$err"; then
	pass non_ff_seeded_main
else
	bad non_ff_seeded_main "rc=$? stderr=$(cat "$err")"
fi

# 7. safe_delete_route
sha=$(git ls-remote origin refs/heads/claude/xy | cut -f1)
git -c core.hooksPath="$HOOKS" push -q origin "$sha:refs/tags/archive/claude-xy-20261022" 2>"$err" || bad safe_delete_route "tag push: $(cat "$err")"
if git -c core.hooksPath="$HOOKS" push -q --force-with-lease=refs/heads/claude/xy:"$sha" origin :refs/heads/claude/xy 2>"$err"; then
	if [ -z "$(git ls-remote origin refs/heads/claude/xy)" ]; then pass safe_delete_route; else bad safe_delete_route "branch still on remote"; fi
else
	bad safe_delete_route "rc=$? $(cat "$err")"
fi

# 8. tmp_exempt
git clone -q "$X/r.git" "$X/w"
cd "$X/w" || exit 1
echo a >f
git add f
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git -c core.hooksPath="$HOOKS" push -q origin HEAD:claude/yy 2>"$err" || bad tmp_exempt "branch push: $(cat "$err")"
if git -c core.hooksPath="$HOOKS" push -q origin --delete claude/yy 2>"$err"; then pass tmp_exempt; else bad tmp_exempt "rc=$? $(cat "$err")"; fi

# --- naming gate on NEW branches -------------------------------------------
cd "$G/w" || exit 1

# 9. gate_bad_name: feat/badname has no agent segment -> refused
git checkout -q -B feat/badname main
if git -c core.hooksPath="$HOOKS" push origin feat/badname 2>"$err"; then
	bad gate_bad_name "push succeeded"
elif [ "$(git ls-remote origin refs/heads/feat/badname | cut -f1)" = "" ] && grep -q "недопустимо" "$err"; then
	pass gate_bad_name
else
	bad gate_bad_name "rc=$? stderr=$(cat "$err")"
fi

# 10. gate_ok_name: feat/codex/ok-1 -> accepted, no warning
git checkout -q -B feat/codex/ok-1 main
if git -c core.hooksPath="$HOOKS" push -q origin feat/codex/ok-1 2>"$err"; then
	pass gate_ok_name
else
	bad gate_ok_name "rc=$? $(cat "$err")"
fi

# 11. gate_legacy_ok: codex/legacy-ok -> accepted WITH the legacy warning
git checkout -q -B codex/legacy-ok main
if git -c core.hooksPath="$HOOKS" push -q origin codex/legacy-ok 2>"$err"; then
	if grep -q "legacy branch name codex/legacy-ok accepted" "$err"; then
		pass gate_legacy_ok
	else
		bad gate_legacy_ok "no legacy warning on stderr"
	fi
else
	bad gate_legacy_ok "rc=$? $(cat "$err")"
fi

# 12. gate_protected_names: dev, develop, release/1.0 -> refused
prot_bad=
for b in dev develop release/1.0; do
	git checkout -q -B "$b" main
	if git -c core.hooksPath="$HOOKS" push origin "$b" 2>"$err"; then
		prot_bad="$prot_bad $b(pushed)"
	elif ! grep -q "direct push to $b refused" "$err"; then
		prot_bad="$prot_bad $b(wrong msg)"
	fi
done
if [ -z "$prot_bad" ]; then pass gate_protected_names; else bad gate_protected_names "$prot_bad"; fi

# 13. gate_skip_existing: updating an existing weird-named branch is not name-checked
GIT_DIR="$G/r.git" git update-ref refs/heads/weird/NAME "$main_sha" || bad gate_skip_existing "seed failed"
git checkout -q -B weird/NAME main
echo z >z
git add z
git -c user.name=t -c user.email=t@example.invalid commit -qm weird
if git -c core.hooksPath="$HOOKS" push -q origin weird/NAME 2>"$err"; then
	pass gate_skip_existing
else
	bad gate_skip_existing "rc=$? $(cat "$err")"
fi

# 14. gate_delete_protected: deleting main is refused although its archive tag matches
# The hook under test may be shared/pre-push (message "... refused: protected branch")
# or the dispatch symlink (message "... refused"); both must refuse and keep main.
git -c core.hooksPath="$HOOKS" push -q origin "$main_sha:refs/tags/archive/main-20261124" 2>"$err"
if git -c core.hooksPath="$HOOKS" push origin :main 2>"$err"; then
	bad gate_delete_protected "push succeeded"
elif grep -q "delete of main refused" "$err" && [ -n "$(git ls-remote origin refs/heads/main)" ]; then
	pass gate_delete_protected
else
	bad gate_delete_protected "rc=$? stderr=$(cat "$err")"
fi

echo "итог: PASS $ok, FAIL $fail"
[ "$fail" -eq 0 ]
