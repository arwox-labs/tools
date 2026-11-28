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