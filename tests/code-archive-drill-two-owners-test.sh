#!/bin/bash
# code-archive-drill-two-owners-test: drill находит HEAD репозитория,
# лежащего у ВТОРОГО владельца (CA_GITHUB_BASES + шаблон CA_GITHUB_SRC).
# Одиночная база (CA_GITHUB_BASE) на этот сценарий падает — это тоже проверяем.
# Офлайн: оба «владельца» — локальные каталоги с bare-репо, приёмник GitLab —
# локальный bare; настоящие GitLab/GitHub не используются.
# Запуск: bash tests/code-archive-drill-two-owners-test.sh
set -u

BIN="$(cd "$(dirname "$0")/.." && pwd -P)/bin/code-archive-drill"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

mkdir -p "$TMP/owner1" "$TMP/owner2" "$TMP/gl" "$TMP/state-two" "$TMP/state-one" "$TMP/repos-two" "$TMP/repos-one"
printf 'GITLAB_MIRROR_TOKEN=fixture-token\n' > "$TMP/env"

seed(){ # один и тот же коммит в gitlab-приёмник $1 и bare владельца $2
  local gl_bare="$1" own_bare="$2" wk="$TMP/wk"
  git -c init.defaultBranch=main init -q --bare "$gl_bare"
  git -c init.defaultBranch=main init -q --bare "$own_bare"
  rm -rf -- "$wk"
  git -c init.defaultBranch=main init -q "$wk"
  git -C "$wk" config user.email t@t
  git -C "$wk" config user.name t
  printf 'moved\n' > "$wk/marker"
  git -C "$wk" add marker
  git -C "$wk" commit -q -m "chore(seed): fixture" \
    || { echo "FIXTURE-ERROR: commit $gl_bare" >&2; exit 2; }
  git -C "$wk" push -q "$gl_bare" main || { echo "FIXTURE-ERROR: push $gl_bare" >&2; exit 2; }
  git -C "$wk" push -q "$own_bare" main || { echo "FIXTURE-ERROR: push $own_bare" >&2; exit 2; }
}

# Репозиторий moved есть у второго владельца; первый владелец его не имеет.
seed "$TMP/gl/moved.git" "$TMP/owner2/moved.git"

run_drill(){ # $1 = CA_GITHUB_BASES, $2 = тег сценария
  env CA_ENV_FILE="$TMP/env" \
      CA_GITHUB_SRC="$TMP/%s" \
      CA_GITHUB_BASES="$1" \
      CA_GITHUB_BASE="$TMP/owner1" \
      CA_GITLAB_BASE="$TMP/gl" \
      CA_REPOS_DIR="$TMP/repos-$2" \
      CA_STATE_DIR="$TMP/state-$2" \
      CA_LOG="$TMP/log-$2.log" \
      CA_DRILL_DIR="$TMP/drill-$2" \
      CA_DRILL_NAME=moved \
      "$BIN"
}

# Сценарий two: оба владельца перечислены — HEAD должен найтись у второго.
rc_two=0; out_two="$(run_drill 'owner1 owner2' two 2>&1)" || rc_two=$?
# Сценарий one: одиночная база (только первый владелец) — HEAD не находится.
rc_one=0; out_one="$(run_drill 'owner1' one 2>&1)" || rc_one=$?

FAILS=0
N=0
check(){ # имя проверка... -> PASS/FAIL с номером
  local name=$1; shift
  N=$((N + 1))
  if "$@"; then echo "PASS $N $name"; else echo "FAIL $N $name"; FAILS=$((FAILS + 1)); fi
}

two_rc0(){ test "$rc_two" -eq 0; }
two_ok(){ grep -qF 'drill:ok' "$TMP/log-two.log"; }
two_no_mismatch(){ ! grep -qF 'head-missing' "$TMP/log-two.log"; }
one_rc_nonzero(){ test "$rc_one" -ne 0; }
one_head_missing(){ grep -qF 'head-missing' "$TMP/log-one.log"; }

check "two: код возврата 0" two_rc0
check "two: в журнале drill:ok" two_ok
check "two: head-missing отсутствует" two_no_mismatch
check "one: одиночная база падает (код возврата ненулевой)" one_rc_nonzero
check "one: в журнале head-missing" one_head_missing

if [ "$FAILS" -eq 0 ]; then
  echo PASS
  exit 0
fi
printf -- '--- out_two ---\n%s\n--- out_one ---\n%s\n' "$out_two" "$out_one"
echo FAIL
exit 1
