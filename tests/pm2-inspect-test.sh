#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
inspect="$root/bin/pm2-inspect"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/jlist.json" <<'JSON'
[
  {"name":"hh-cabinet-bridge","pm_id":7,"pm2_env":{"status":"online","restart_time":2,"pm_uptime":1000,"env":{"TOKEN":"fixture-secret"},"args":["private-arg"],"pm_exec_path":"/private/path"}},
  {"name":"sample-worker","pm_id":8,"pm2_env":{"status":"stopped","restart_time":0,"pm_uptime":0}}
]
JSON
cat >"$tmp/pm2" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == jlist ]] || exit 64
cat "$PM2_FIXTURE"
MOCK
chmod +x "$tmp/pm2"
export PM2_BIN="$tmp/pm2" PM2_FIXTURE="$tmp/jlist.json"

bash -n "$inspect"
bash -n "${BASH_SOURCE[0]}"

ls_output=$("$inspect" ls)
grep -Fq 'hh-cabinet-bridge' <<<"$ls_output"
grep -Fq 'online' <<<"$ls_output"
grep -Fq 'sample-worker' <<<"$ls_output"
grep -Fq 'stopped' <<<"$ls_output"

json_output=$("$inspect" json)
grep -Fq '"name":"hh-cabinet-bridge"' <<<"$json_output"
for forbidden in '"env"' '"args"' '"pm_exec_path"' fixture-secret private-arg /private/path; do
  if grep -Fq "$forbidden" <<<"$json_output"; then
    printf 'FAIL: JSON output contains forbidden data: %s\n' "$forbidden" >&2
    exit 1
  fi
done

describe_output=$("$inspect" describe hh-cabinet-bridge)
for field in '"id":7' '"name":"hh-cabinet-bridge"' '"status":"online"' '"uptime":' '"restarts":2'; do
  grep -Fq "$field" <<<"$describe_output"
done
[[ $(jq -r '.name' <<<"$describe_output") == hh-cabinet-bridge ]]

printf 'ok pm2-inspect\n'
