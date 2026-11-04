#!/bin/bash
# code-archive-two-sources-test: разделение репозиториев на двух владельцев
# GitHub (CA_GITHUB_BASES + шаблон CA_GITHUB_SRC) в bin/code-archive:
# независимость владельцев при сбое списка и при сокращении, дедупликация
# одинаковых имён, режим по имени, находящий владельца через gh api.
# Офлайн: списки — CA_LIST_DIR/<owner>.tsv, источники GitHub и приёмник
# GitLab — локальные каталоги mktemp; настоящие gh api и сеть не используются
# (gh подменён заглушкой только в сценарии e).
# Запуск: bash tests/code-archive-two-sources-test.sh
set -u

BIN="$(cd "$(dirname "$0")/.." && pwd -P)/bin/code-archive"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

LIST="$TMP/list" # CA_LIST_DIR: файлы <owner>.tsv
mkdir -p "$TMP/ownerA" "$TMP/ownerB" "$LIST"
printf 'GITLAB_MIRROR_TOKEN=fixture-token\n' > "$TMP/env"

seed(){ # bare-репозиторий с одним коммитом; в marker — содержимое $2
  local bare="$1" txt="$2" wk="$TMP/wk"
  git -c init.defaultBranch=main init -q --bare "$bare"
  rm -rf -- "$wk"
  git -c init.defaultBranch=main init -q "$wk"
  git -C "$wk" config user.email t@t
  git -C "$wk" config user.name t
  printf '%s\n' "$txt" > "$wk/marker"
  git -C "$wk" add marker
  git -C "$wk" commit -q -m "chore(seed): fixture" \
    || { echo "FIXTURE-ERROR: commit $bare" >&2; exit 2; }
  git -C "$wk" push -q "$bare" main \
    || { echo "FIXTURE-ERROR: push $bare" >&2; exit 2; }
}

seed "$TMP/ownerA/alpha.git" alpha-A
seed "$TMP/ownerA/dup.git"   dup-A
seed "$TMP/ownerB/beta.git"  beta-B
seed "$TMP/ownerB/dup.git"   dup-B

# Строки списка: <owner>\t<name>\t<pushed_at>\t<size_kb>\t<archived>.
# У дубля dup pushed_at разный у владельцев — победитель виден по состоянию.
printf '%s\t%s\t%s\t%s\t%s\n' \
  'ownerA' 'alpha' '2026-11-01T00:00:00Z' '10' 'false' \
  'ownerA' 'dup'   '2026-11-01T00:00:00Z' '10' 'false' > "$LIST/ownerA.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' \
  'ownerB' 'beta' '2026-11-01T00:00:00Z' '10' 'false' \
  'ownerB' 'dup'  '2026-11-02T00:00:00Z' '10' 'false' > "$LIST/ownerB.tsv"

run_ca(){ # --changed в изолированных каталогах сценария $1; список — $2
  local tag="$1" list_dir="${2:-$LIST}"
  env CA_ENV_FILE="$TMP/env" \
      CA_GITHUB_SRC="$TMP/%s" \
      CA_GITHUB_BASES="ownerA ownerB" \
      CA_GITLAB_BASE="$TMP/gl-$tag" \
      CA_REPOS_DIR="$TMP/repos-$tag" \
      CA_STATE_DIR="$TMP/state-$tag" \
      CA_LOG="$TMP/log-$tag.log" \
      CA_LAST_OK="$TMP/last-ok-$tag" \
      CA_LIST_DIR="$list_dir" \
      CA_NO_NOTIFY=1 \
      CA_NOTIFY_ENV="$TMP/no-notify-env" \
      CA_DRILL_DOW=8 \
      CA_FREE_MIN_KB=1 \
      "$BIN" --changed
}

# --- Сценарий d: список первого владельца недоступен ---
mkdir -p "$TMP/list-d"
printf '%s\t%s\t%s\t%s\t%s\n' \
  'ownerB' 'beta' '2026-11-01T00:00:00Z' '10' 'false' > "$TMP/list-d/ownerB.tsv"

# --- Сценарий e: режим по имени, офлайн-заглушка gh отвечает только за ownerB ---
mkdir -p "$TMP/stub-gh"
cat > "$TMP/stub-gh/gh" <<'STUBEOF'
#!/usr/bin/env bash
if [[ "${1:-}" == api && "${2:-}" == repos/ownerB/* ]]; then
  printf 'ownerB/%s\n' "${2#repos/ownerB/}"
  exit 0
fi
exit 1
STUBEOF
chmod +x "$TMP/stub-gh/gh"

run_named(){ # режим по имени со stub-gh в PATH
  local name="$1"
  env CA_ENV_FILE="$TMP/env" \
      CA_GITHUB_SRC="$TMP/%s" \
      CA_GITHUB_BASES="ownerA ownerB" \
      CA_GITLAB_BASE="$TMP/gl-e" \
      CA_REPOS_DIR="$TMP/repos-e" \
      CA_STATE_DIR="$TMP/state-e" \
      CA_LOG="$TMP/log-e.log" \
      CA_LAST_OK="$TMP/last-ok-e" \
      CA_NO_NOTIFY=1 \
      CA_NOTIFY_ENV="$TMP/no-notify-env" \
      CA_FREE_MIN_KB=1 \
      PATH="$TMP/stub-gh:$PATH" \
      "$BIN" "$name"
}

# --- Сценарий f: репозиторий уже в зеркале, pushed_at совпадает (ветка skip),
# remote github указывает на чужого владельца ownerA ---
mkdir -p "$TMP/list-f" "$TMP/state-f"
# У ownerA нет репозиториев: пустой список, чтобы проход не получил err:list-fetch.
: > "$TMP/list-f/ownerA.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' \
  'ownerB' 'gamma' '2026-11-01T00:00:00Z' '10' 'false' > "$TMP/list-f/ownerB.tsv"
git -c init.defaultBranch=main init -q --bare "$TMP/repos-f/gamma.git"
git --git-dir="$TMP/repos-f/gamma.git" remote add github "$TMP/ownerA/gamma.git"
printf '2026-11-01T00:00:00Z\n' > "$TMP/state-f/gamma.pushed_at"

# --- Сценарий a: оба владельца обработаны ---
rc_a=0; out_a="$(run_ca a 2>&1)" || rc_a=$?

# --- Сценарий b: сокращение списка только у ownerA ---
mkdir -p "$TMP/state-b"
printf '99\n' > "$TMP/state-b/list-count-ownerA"
rc_b=0; out_b="$(run_ca b 2>&1)" || rc_b=$?

# --- Сценарий d: сбой списка у первого владельца ---
rc_d=0; out_d="$(run_ca d "$TMP/list-d" 2>&1)" || rc_d=$?

# --- Сценарий e: режим по имени находит репозиторий у второго владельца ---
rc_e=0; out_e="$(run_named beta 2>&1)" || rc_e=$?

# --- Сценарий f: пропуск по pushed_at выравнивает remote на победителя ---
rc_f=0; out_f="$(run_ca f "$TMP/list-f" 2>&1)" || rc_f=$?

FAILS=0
N=0
check(){ # имя проверка... -> PASS/FAIL с номером
  local name=$1; shift
  N=$((N + 1))
  if "$@"; then echo "PASS $N $name"; else echo "FAIL $N $name"; FAILS=$((FAILS + 1)); fi
}

a_rc0(){ test "$rc_a" -eq 0; }
a_alpha(){ test -d "$TMP/repos-a/alpha.git"; }
a_beta(){ test -d "$TMP/repos-a/beta.git"; }
a_src_alpha(){ test "$(git --git-dir="$TMP/repos-a/alpha.git" remote get-url github)" = "$TMP/ownerA/alpha.git"; }
a_src_beta(){ test "$(git --git-dir="$TMP/repos-a/beta.git" remote get-url github)" = "$TMP/ownerB/beta.git"; }
a_summary(){ grep -qF 'ok=3 err=0 skipped=1' <<<"$out_a"; }
a_owner_field(){ grep -qF 'ownerA alpha ok' "$TMP/log-a.log" && grep -qF 'ownerB beta ok' "$TMP/log-a.log"; }
a_sources(){ grep -qF 'sources owners=ownerA ownerB' "$TMP/log-a.log"; }
a_last_ok(){ test -f "$TMP/last-ok-a"; }
c_dup_skipped(){ grep -qF 'skip:dup:ownerB' "$TMP/log-a.log"; }
c_dup_first_owner(){ test "$(git --git-dir="$TMP/repos-a/dup.git" show main:marker)" = "dup-A"; }
c_dup_pushed_at(){ test "$(cat "$TMP/state-a/dup.pushed_at")" = "2026-11-01T00:00:00Z"; }

b_rc_nonzero(){ test "$rc_b" -ne 0; }
b_shrunk_owner_a(){ grep -qF 'ownerA err:list-shrunk layer=github 99 to 2' <<<"$out_b"; }
b_no_err_owner_b(){ ! grep -qF 'ownerB err:' "$TMP/log-b.log"; }
b_owner_b_processed(){ test -d "$TMP/repos-b/beta.git"; }
b_owner_a_skipped(){ test ! -d "$TMP/repos-b/alpha.git"; }
b_summary(){ grep -qF '=== pass ' "$TMP/log-b.log" && grep -qF 'ok=2 err=1 skipped=0' "$TMP/log-b.log"; }
b_count_kept(){ test "$(cat "$TMP/state-b/list-count-ownerA")" = 99; }
b_last_ok_absent(){ test ! -f "$TMP/last-ok-b"; }
b_notify(){ grep -qF 'ownerA' "$TMP/state-b/notify.out" && grep -qF 'сократился' "$TMP/state-b/notify.out"; }

d_rc_nonzero(){ test "$rc_d" -ne 0; }
d_fetch_owner_a(){ grep -qF 'ownerA err:list-fetch' <<<"$out_d"; }
d_no_err_owner_b(){ ! grep -qF 'ownerB err:' "$TMP/log-d.log"; }
d_owner_b_processed(){ test -d "$TMP/repos-d/beta.git"; }
d_summary(){ grep -qF '=== pass ' "$TMP/log-d.log" && grep -qF 'ok=1 err=1 skipped=0' "$TMP/log-d.log"; }
d_notify(){ grep -qF 'ownerA' "$TMP/state-d/notify.out" && grep -qF 'список репозиториев' "$TMP/state-d/notify.out"; }
d_last_ok_absent(){ test ! -f "$TMP/last-ok-d"; }

e_rc0(){ test "$rc_e" -eq 0; }
e_mirror(){ test -d "$TMP/repos-e/beta.git"; }
e_src_owner_b(){ test "$(git --git-dir="$TMP/repos-e/beta.git" remote get-url github)" = "$TMP/ownerB/beta.git"; }
e_journal(){ grep -qF 'beta ok' "$TMP/log-e.log"; }

f_rc0(){ test "$rc_f" -eq 0; }
f_src_owner_b(){ test "$(git --git-dir="$TMP/repos-f/gamma.git" remote get-url github)" = "$TMP/ownerB/gamma.git"; }
f_summary(){ grep -qF 'ok=0 err=0 skipped=1' <<<"$out_f"; }
f_no_err(){ ! grep -qF 'gamma err' "$TMP/log-f.log"; }
f_no_warn(){ ! grep -qF 'warn:remote' "$TMP/log-f.log"; }

check "a: код возврата 0" a_rc0
check "a: зеркало ownerA (alpha)" a_alpha
check "a: зеркало ownerB (beta)" a_beta
check "a: источник alpha из базы ownerA" a_src_alpha
check "a: источник beta из базы ownerB" a_src_beta
check "a: итог ok=3 err=0 skipped=1" a_summary
check "a: владелец — первое поле журнала" a_owner_field
check "a: строка sources owners в начале прохода" a_sources
check "a: last-ok записан" a_last_ok
check "c: повтор пропущен skip:dup:ownerB" c_dup_skipped
check "c: дубль взят у первого владельца ownerA" c_dup_first_owner
check "c: pushed_at дубля от ownerA" c_dup_pushed_at
check "b: код возврата ненулевой" b_rc_nonzero
check "b: err:list-shrunk только у ownerA" b_shrunk_owner_a
check "b: у ownerB ошибок нет" b_no_err_owner_b
check "b: ownerB всё равно обработан" b_owner_b_processed
check "b: ownerA пропущен" b_owner_a_skipped
check "b: проход дошёл до итога err=1" b_summary
check "b: baseline ownerA не сброшен" b_count_kept
check "b: last-ok не записан" b_last_ok_absent
check "b: уведомление о сокращении" b_notify
check "d: код возврата ненулевой" d_rc_nonzero
check "d: err:list-fetch у первого владельца ownerA" d_fetch_owner_a
check "d: у ownerB ошибок нет" d_no_err_owner_b
check "d: ownerB всё равно обработан" d_owner_b_processed
check "d: проход дошёл до итога ok=1 err=1" d_summary
check "d: уведомление о сбое списка" d_notify
check "d: last-ok не записан" d_last_ok_absent
check "e: код возврата 0" e_rc0
check "e: зеркало beta создано" e_mirror
check "e: источник — база второго владельца ownerB" e_src_owner_b
check "e: журнал beta ok" e_journal
check "f: код возврата 0" f_rc0
check "f: remote github выровнен на победителя ownerB" f_src_owner_b
check "f: итог ok=0 err=0 skipped=1" f_summary
check "f: пропуск не превратился в ошибку" f_no_err
check "f: warn:remote не писался" f_no_warn

if [ "$FAILS" -eq 0 ]; then
  echo PASS
  exit 0
fi
echo FAIL
exit 1
