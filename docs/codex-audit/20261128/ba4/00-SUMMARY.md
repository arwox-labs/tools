# Аудит контура агентов — сводка проверенного (2026-11-28, ba-sanatory)

Все числа получены командами в этой сессии; непроверенное помечено UNVERIFIED.

## 1. Замеры OpenCode (БД read-only)

```
sqlite3 "file:/root/.local/share/opencode/opencode.db?mode=ro" \
 "select count(*), sum(tokens_input), sum(tokens_output), sum(tokens_cache_read), \
         sum(time_compacting is not null), count(distinct case when parent_id is not null then id end) from session_v2;"
```
Вывод: `3845|371116059|18450391|5830269381|0|618`

- Сессий 3845, из них субагентских 618.
- input 371 116 059, output 18 450 391, **cache_read 5 830 269 381** (94% входа — перечитывание кэша).
- **Автосжатие не срабатывало ни разу**: `time_compacting IS NOT NULL` = 0.
- Стоимость: `select round(sum(cost),2)` → `89.36`.

## 2. Конфигурация сжатия (после правки 28.11)

`/root/.config/opencode/opencode.jsonc:50-56`:

```
"compaction": { "auto": true, "keep": { "tokens": 10000 }, "buffer": "35%" }
```

Дока (opencode.ai/docs/config, раздел Compaction): «`buffer` is the share of the model's context window kept free before automatic compaction starts» — 35% означает старт сжатия раньше, чем дефолтные 15%.

Варианты моделей: `grep -c '#high'` → `0`, `grep -c '#low'` → `6`.

**Нативная компакция провайдера не включена**: `grep -c '"native"' opencode.jsonc` → `0`. Поддержка checkpoint-ов со стороны alibaba-token-plan не подтверждена документацией — оставлены локальные саммари (осознанное решение, не дефект).

## 3. Плагины принуждения — активированы штатной командой

`opencode reload` → `Configuration reloaded` (rc=0), без перезапуска сервера и без убийства живых сессий.

Лог `/root/.local/share/opencode/log/opencode.log:156257-156264` фиксирует загрузку `codex-first`, `no-tails`, `todo-gate` в 14:08:50Z (17:08 MSK) — то есть уже после правки файлов (13:10).

Статические проверки: три `node --input-type=module --check` → ok; `session.message` → `0`; события `message.updated`×6, `message.part.updated`×6, `session.idle`×3.

## 4. Codex-обёртки

`origin/main` tools = `31967d1`: `bin/codex-role:90` `-o "$artifact.last"`, `:94` `if [[ $rc -eq 0 && ( ! -s "$artifact.last" ) ]]; then rc=1; fi`; `bin/codex-atom:64,107` — аналогично. Диагностик пустого ответа больше не проглатывается.

Механический замер роллаутов (без чтения содержимого): файлов `*.jsonl` 806, объём 824M, за 7 дней 435, крупнейший 22 762 356 байт. Строк `RUNNER role=` в роллаутах: builder 12, explorer 72.

## 5. Цена системных инструкций

`wc -c` по 6 файлам цепочки инструкций: сумма `61725` байт ≈ `15431` токенов на каждый запрос — это и есть повторно подаваемый префикс, который кэшируется (cache_read), но остаётся самым тяжёлым фиксированным блоком.

## 6. Отказы, зафиксированные при аудите

- Атом B (роллауты Codex): Codex отказался читать роллауты — его собственный Gitleaks-предскан дал 37 совпадений; значения не выводились, файлы не изменялись. Данные по роллаутам получены механикой (см. §4).
- Атом C (избыточность конфигов): первый прогон не дал артефакта (0 байт) — перезапущен сжатым атомом.
- Ревьюер (gpt-6.2-astra): первый прогон убит по таймауту обёртки без артефакта — перезапущен сжатым атомом.
## 7. Два дефекта, найденных и закрытых 28.11 (после первого прогона аудита)

### 7.1 Рантайм принимает только `session.idle`

Лог `opencode.log:156036-156038` (после первого «исправления»):

```
WARN ignoring unknown event types pluginID=no-tails types="[\"message.updated\",\"message.part.updated\"]"
```

Рантайм OpenCode v2 отбрасывает `message.updated` и `message.part.updated`; подписка на `session.idle` принимается. Следствие: коррекция `no-tails` не срабатывала ни разу —
`select count(*) from part where data like '%Не заканчивай ответ%'` → `0`.

Исправлено: все три плагина подписаны только на `session.idle`, счётчики коррекций сбрасываются на чистом ходе / при отсутствии открытых todo. Коммит contour-config `b93a409`.
Проверка после `opencode reload` (14:20:04): счётчик `grep -c 'ignoring unknown event types'` не вырос — `before=263 after=263`.

### 7.2 `codex exec -o` теряет ответ

`docs/codex-audit/20261128/ba4/07-builder-atom-c-tight.md.err`:

```
Error: Failed to write last message file ".../07-builder-atom-c-tight.md.last"
Caused by:
    output path was replaced
```

При этом модель отработала (в том же `.err`: `ИТОГО: 13 находок`, `tokens used 85,510`). Из-за ошибки записи `rc != 0`, артефакт остаётся 0 байт.
Проверено вручную: `codex exec` без `-o` отдаёт финальное сообщение в stdout — `rc=0`, `SMOKE-OK` (9 байт).

### 7.3 Итог исправлений

- Плагины: `subscribe({ types: ["session.idle"] })` во всех трёх; коммит contour-config `b93a409`; после `opencode reload` новых WARN нет (`before=263 after=263`).
- Обёртки: `-o` удалён из `codex-role` и `codex-atom`; коммит tools `b40c127`, PR **#579** (squash merged). Проверка живого прогона: `RUNNER role=explorer model=gpt-6-luna sandbox=read-only rc=0 bytes=9 … out=…/05-explorer-smoke.md`.
- Синтаксис: `bash -n` обоих скриптов → `SYNTAX_OK`; `node --input-type=module --check` трёх плагинов → `no-tails OK`, `todo-gate OK`, `codex-first OK`.

### 7.4 Что осталось непроверенным

- Функциональное срабатывание `no-tails`/`todo-gate` на реальном ходе с хвостом (подписка валидна, доставка события в плагин подтверждена отсутствием WARN, но коррекция в живой сессии не наблюдалась) — UNVERIFIED.
- Нативная компакция провайдера `alibaba-token-plan`: поддержка в документации не подтверждена, не включена.
