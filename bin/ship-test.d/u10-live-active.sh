# U10 (spec:099): skip:active живой копии без reload — defer, не err:live.
. "$bin/git-auto-lib"
bin="$d/bin"

cat > "$d/bin/git-sync" <<'EOF'
#!/usr/bin/env bash
printf '%s skip:active\n' "$1"
EOF
cat > "$d/bin/git-state" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$d/bin/git-sync" "$d/bin/git-state"

# u10-1: активная живая копия без reload не проверяет HEAD и сообщает defer.
out=$(ga_live_sync live sha 0 2>"$d/u10-1.err")
err=$(<"$d/u10-1.err")
[[ $out == '0 live' && $err == *'live:deferred active'* ]] && p u10-1 || f u10-1

# u10-2: --reload сохраняет fail-closed поведение.
out=$(ga_live_sync live sha 0 x 2>"$d/u10-2.err")
[[ ${out%% *} == 60 ]] && p u10-2 || f u10-2
