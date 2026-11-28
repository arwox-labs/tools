Созданы только [bin/pm2-inspect](/root/workspaces/tools/bin/pm2-inspect) и [tests/pm2-inspect-test.sh](/root/workspaces/tools/tests/pm2-inspect-test.sh). Скрипт исполняемый; вывод ограничен полями `id`, `name`, `status`, `uptime`, `restarts`. При отсутствии `jq` он завершится с кодом 2.

Проверки `bash -n` для обоих файлов и тест на поддельных данных прошли. Тест подтвердил, что вывод не содержит env, args, путь к скрипту или контрольные секретные строки. Реальные `pm2-inspect ls` и `describe hh-cabinet-bridge` не запускал.
