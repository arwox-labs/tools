# Атом A: полная агрегация сессий OpenCode (read-only)

Цель: посчитать расход по ВСЕМ сессиям, не по выборке. База: `/root/.local/share/opencode/opencode.db`, только чтение: `sqlite3 "file:/root/.local/share/opencode/opencode.db?mode=ro" "<SQL>"`.

Шаги:
1. `PRAGMA table_info(session_v2);` — найди колонки токенов (tokens_input, tokens_output, cache/cache_read и т.п.) и времени. Все дальнейшие запросы строй по реальным колонкам.
2. Агрегаты по всем сессиям: count(*), sum(cost), sum по каждой токен-колонке. Отдельно: сессии с parent_id NOT NULL (субагенты) против корневых.
3. Группировка по модели/провайдеру (колонка model или metadata — смотри PRAGMA) и по дню: input, output, cache_read, доля cache_read.
4. Топ-20 сессий по cache_read: id, title, directory, input, cache_read, отношение cache_read/input, длительность.
5. Рост контекста: для 5 худших сессий покажи по частям (таблица part) накопление размера сообщений во времени (первые/средние/последние 10 частей, length(data) или аналог).

Артефакт: markdown-таблицы + каждый SQL дословно рядом с результатом. Файл создаёт запускаль, ты только печатаешь отчёт в stdout.

Проверки (выполни и процитируй вывод):
- `SELECT count(*) FROM session_v2;` — число должно войти в отчёт как sessions_total.
- Сумма по группам модели равна общей сумме токенов (допуск 0).

Запреты: не читать auth.json, ~/.codex/*.toml, .env; не писать в БД; не менять файлы. Только SELECT и PRAGMA.