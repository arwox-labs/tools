# Атом D: деградация и галлюцинации (read-only)

Цель: найти реальные случаи деградации моделей и галлюцинаций в данных сессий.

Источники (только чтение):
- `/root/.local/share/opencode/opencode.db` через `sqlite3 "file:...?mode=ro"` (таблицы session_v2, part, session_part).
- `/root/.local/share/opencode/log/opencode.log` (36 МБ) — последние 5000 строк.

Шаги:
1. Ошибки моделей: в part ищи `model-resolution|unknown variant|Model not found|provider.*error|rate.?limit|429|context.*length|token.*limit` (WHERE data LIKE, LIMIT 200 на запрос). Сгруппируй по типу и модели, приведи 3 дословных примера с session id.
2. Циклы и повторы: сессии, где один и тот же атом/запрос повторяется ≥3 раз (ищи по title/session metadata или по одинаковым кускам данных частей). Признак галлюцинации: агент заявляет done без вывода команды — ищи в частях `UNVERIFIED|FALLBACK:` напечатанные самим агентом (не RUNNER).
3. Compaction: сколько событий сжатия контекста (ищи `compact|summariz` в частях/логе), по каким сессиям, как часто. Частый compaction = контекст раздут.
4. Из лога: последние ошибки/warn по моделям и плагинам (grep -iE 'error|warn' | tail -50), сгруппируй.
5. Плагины-гейты: `/root/.config/opencode/plugins/codex-first/index.js` и `detect.js` — прочитай, подтверди или опровергни 7 дыр из `/root/workspaces/tools/docs/codex-audit/20261128/README.md` (раздел 2) с file:line.

Артефакт: таблица: тип деградации, число случаев, пример с session id/файл:строка, влияние. Печатай в stdout.

Проверки:
- Каждый тип подтверждён ≥1 дословным примером из БД/лога (команда + вывод).
- По 7 дырам README: вердикт подтверждено/опровергнуто с цитатой кода.

Запреты: не читать auth.json, ~/.codex/*.toml, .env, secrets/; не писать файлы; не делать full scan без LIMIT по таблице part (168230 строк, 1.5 ГБ).