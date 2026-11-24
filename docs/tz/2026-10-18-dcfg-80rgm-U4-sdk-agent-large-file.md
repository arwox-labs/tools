# ТЗ dcfg-80rgm U4 (закрывает dcfg-b6enu частично) — sdk-agent code: правка файла >128 КБ
FILE: bin/sdk-agent
FILE: bin/sdk-agent-test

Цель: `sdk-agent code` применяет правки к файлу любого размера до лимитов ТЗ. Сейчас на `docs/PM2-PROCESSES.md` (143 202 байт) — `bin/sdk-agent: line 463: /usr/bin/jq: Argument list too long` → `cannot apply edits` (прогон 18.10, U2c).
5 Whys: отказ → jq не запустился → аргумент argv больше предела ядра MAX_ARG_STRLEN 128 КиБ → содержимое всех файлов передаётся строкой `--argjson s "$state"` → state копится в переменной оболочки. Корень — передача state через argv в функции применения правок (`cmd_code`, блок «Current state» и «Apply the edits in memory»: строки ≈444, ≈446, ≈451, ≈469).
ADR: state держать во временном файле (`mktemp` внутри уже используемого tmp-каталога или `$TMPDIR`, удаляется trap/в конце), читать через `jq --slurpfile ss "$state_f"` и в программе `($ss[0]) as $s | …`. Наращивание state (≈444/446) — тоже через файл (`--slurpfile` + `--rawfile c`, вывод перенаправить во второй tmp и `mv`). `--argjson s "$state"` в этих четырёх местах не остаётся. Поведение (создание, «not found», «old not unique», отказ на неуказанный путь) не меняется.

## Тест сначала (bin/sdk-agent-test, в стиле apply_* тестов: apply_setup / apply_edit_once)
Новый кейс `apply_large_file`: файл из списка FILE размером ≥200 000 байт, одна правка уникального фрагмента в конце → rc 0, фрагмент заменён, размер файла изменился ровно на разницу. Сначала прогнать — красный (Argument list too long), затем зелёный. Остальные кейсы не трогать и не ослаблять.

## Запреты
Только эти 2 файла. Модель, бюджет, лимиты, daily cap, проверка путей — не менять. Без rm -rf вне tmp, force-push, --no-verify, без push/PR. Платный движок в тесте не вызывать (тесты apply_* работают без движка).

## Готово, когда
`bash bin/sdk-agent-test` → все кейсы ok, failed 0, включая `apply_large_file`; `grep -c -- '--argjson s "\$state"' bin/sdk-agent` = 0; `bash -n bin/sdk-agent` rc 0.
