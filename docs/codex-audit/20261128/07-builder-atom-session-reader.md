Созданы [session-reader](/root/workspaces/tools/bin/session-reader) и [session-reader-test.sh](/root/workspaces/tools/tests/session-reader-test.sh). Reader использует `sqlite3` из Python, read-only URI, `query_only` и параметризованные запросы.

Тест прошёл: JSON для списка и одной сессии корректен, запись блокируется, `py_compile` завершается успешно.Файлы исполняемые; других файлов не создавал.
