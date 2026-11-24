# ТЗ dcfg-80rgm U3b — safe-delete: имя bundle для ветки с «/»
FILE: bin/safe-delete
FILE: bin/safe-delete-test

Цель: копия bundle для ветки вида `claude/hrkh5-glprobe3` создаётся в `$BK` одним файлом, без подкаталога.
5 Whys: в блоке U3 (функция-ветка `branch)`, строка `kf="$BK/$(basename "$repo")-${br//\\//-}-$(date +%Y%m%d%H%M%S).bundle"`) шаблон `\\` ищет обратную косую, а не «/» → проверка: `br=claude/hrkh5-glprobe3; echo "${br//\\//-}"` → `claude/hrkh5-glprobe3` → путь `$BK/projects-claude/hrkh5-…bundle` в несуществующем каталоге → `fail "bundle не создан"`. Тест T88 `no_origin_bundle` использует имя без «/», поэтому дефект не виден.
ADR: заменить `${br//\\//-}` на `${br//\//-}` (так же, как в теге архива `archive/${br//\//-}-…` в этом же файле). Больше в `bin/safe-delete` ничего не менять.

## Тест сначала
В `bin/safe-delete-test` добавить кейс `no_origin_bundle_slash` по образцу `no_origin_bundle` (T88), но с веткой `claude/x-probe`: rc 0, ветки нет, в `$SAFE_DELETE_BK` есть ровно один `*.bundle` с `claude-x-probe` в имени, `git bundle verify` ок. Сначала красный, затем зелёный. Остальные кейсы не трогать.

## Запреты
Только эти 2 файла и эта строка + новый тест. Без rm -rf вне /tmp, force-push, --no-verify, push/PR. safe-delete на живых репо не запускать.

## Готово, когда
`bash bin/safe-delete-test` → `итог: PASS 91, FAIL 0` (или PASS N+1 от текущего 90, FAIL 0); `grep -c 'br//\\\\\\\\//' bin/safe-delete` = 0.
