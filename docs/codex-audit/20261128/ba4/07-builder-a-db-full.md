**Итог:** `sessions_total = 3845`. Суммы токенов по группам provider/model совпали с общими: все пять разниц равны нулю. Запросы выполнялись через `sqlite3 "file:/root/.local/share/opencode/opencode.db?mode=ro" "<SQL>"`. Файлы и БД не изменялись.

### 1. Схема и число сессий

SQL:

```sql
PRAGMA table_info(session_v2);
```

Результат — существенные для отчёта колонки:

| Группа | Колонки |
|---|---|
| Сессия | `id`, `parent_id`, `title`, `directory`, `model`, `metadata` |
| Стоимость | `cost` |
| Токены | `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write` |
| Время, Unix ms | `time_created`, `time_updated` |

В `model` хранится JSON; использованы `$.providerID` и `$.id`.

SQL:

```sql
PRAGMA table_info(part);
```

Результат: `part(id, message_id, session_id, time_created, time_updated, data)`. Для размера использован `length(data)` — число символов сериализованных данных.

SQL:

```sql
SELECT count(*) FROM session_v2;
```

Вывод:

```text
3845
```

### 2. Все сессии: корневые и субагенты

SQL:

```sql
SELECT CASE WHEN parent_id IS NULL THEN 'root' ELSE 'subagent' END AS kind, count(*) AS sessions, sum(cost) AS cost, sum(tokens_input) AS input, sum(tokens_output) AS output, sum(tokens_reasoning) AS reasoning, sum(tokens_cache_read) AS cache_read, sum(tokens_cache_write) AS cache_write FROM session_v2 GROUP BY kind ORDER BY kind;
```

Результат:

| Тип | Сессий | Стоимость | Input | Output | Reasoning | Cache read | Cache write |
|---|---:|---:|---:|---:|---:|---:|---:|
| root | 3227 | 86.038820632973 | 337610425 | 14581379 | 27649552 | 4881284199 | 46285674 |
| subagent | 618 | 3.319429124552 | 33308745 | 3864087 | 3627581 | 947594462 | 4376104 |
| **Всего** | **3845** | **89.358249757525** | **370919170** | **18445466** | **31277133** | **5828878661** | **50661778** |

### 3. Группировка по provider/model

SQL:

```sql
SELECT coalesce(json_extract(model,'$.providerID'),'[no provider]') AS provider, coalesce(json_extract(model,'$.id'),'[no model id]') AS model_id, count(*) AS sessions, sum(tokens_input) AS input, sum(tokens_output) AS output, sum(tokens_reasoning) AS reasoning, sum(tokens_cache_read) AS cache_read, sum(tokens_cache_write) AS cache_write FROM session_v2 GROUP BY provider,model_id ORDER BY provider,model_id;
```

Результат:

| Provider | Model | Сессий | Input | Output | Reasoning | Cache read | Cache write |
|---|---|---:|---:|---:|---:|---:|---:|
| [no provider] | [no model id] | 1 | 28427 | 52 | 315 | 4736 | 0 |
| alibaba-token-plan | deepseek-v4-pro | 2 | 2810668 | 185083 | 122783 | 144974817 | 3117778 |
| alibaba-token-plan | deepseek-v4-pro-0813 | 32 | 2469865 | 147060 | 444782 | 19364608 | 0 |
| alibaba-token-plan | deepseek-v4.1-flash | 1 | 520046 | 31343 | 64362 | 13461024 | 589554 |
| alibaba-token-plan | deepseek-v4.1-flash-1017 | 207 | 45479191 | 3873001 | 2406085 | 2084288810 | 34998306 |
| alibaba-token-plan | glm-5.3 | 33 | 1220167 | 135892 | 291540 | 24839936 | 0 |
| alibaba-token-plan | qwen3.8-flash | 11 | 4304 | 87182 | 34039 | 32234698 | 641332 |
| alibaba-token-plan | qwen3.8-max | 1 | 494 | 22 | 108 | 0 | 16858 |
| alibaba-token-plan | qwen4-max | 1 | 481 | 12 | 678 | 5608 | 36794 |
| alibaba-token-plan | qwen4-max-preview | 6 | 1757656 | 131630 | 244194 | 45969616 | 3031064 |
| bitrix | bitrixgpt-5.6-agent | 1 | 0 | 0 | 0 | 0 | 0 |
| bitrixgpt | bitrix/bitrixgpt-5.5 | 1 | 10576 | 204 | 0 | 41088 | 0 |
| bitrixgpt | bitrix/bitrixgpt-5.5-thinking | 1 | 14340 | 862 | 1204 | 155360 | 0 |
| bitrixgpt | bitrix/bitrixgpt-5.6-agent | 1136 | 64457072 | 4259034 | 11142313 | 608002496 | 0 |
| bitrixgpt | bitrix/bitrixgpt-6.0-agent | 7 | 494999 | 11733 | 5276 | 1568320 | 0 |
| bitrixgpt | bitrix/openai/gpt-oss-120b | 1 | 23981 | 51 | 112 | 0 | 0 |
| openai | gpt-5 | 26 | 105280 | 5023 | 8704 | 205824 | 0 |
| opencode | beam-free | 1 | 0 | 0 | 0 | 0 | 0 |
| opencode | glm-5.3 | 1 | 0 | 0 | 0 | 0 | 0 |
| opencode | glm-5.3-flash-free | 1 | 0 | 0 | 0 | 0 | 0 |
| opencode | gpt-5.4-mini | 1 | 0 | 0 | 0 | 0 | 0 |
| opencode | hy3-free | 3 | 45625 | 1467 | 707 | 76416 | 0 |
| opencode | longcat-2.5-free | 2 | 0 | 0 | 0 | 0 | 0 |
| opencode | nemotron-3-ultra-free | 1 | 0 | 0 | 0 | 0 | 0 |
| opencode | qwen3.8-flash | 1 | 684 | 29280 | 0 | 1841701 | 152446 |
| opencode-go | claude-haiku-5-5 | 2 | 10 | 869 | 560 | 31320 | 91284 |
| opencode-go | deepseek-v4-pro | 91 | 31438387 | 809302 | 2604251 | 477923712 | 0 |
| opencode-go | deepseek-v4.1-flash | 809 | 77634006 | 4118501 | 7120563 | 1243352041 | 74496 |
| opencode-go | gemini-4-argon | 9 | 9828267 | 219673 | 597562 | 74132386 | 1134591 |
| opencode-go | glm-5.3 | 4 | 112329 | 2986 | 12096 | 604319 | 0 |
| opencode-go | glm-5.3-flash | 378 | 51954845 | 1766444 | 2113212 | 316359664 | 0 |
| opencode-go | gpt-5.6-luna | 1 | 9 | 671 | 921 | 165484 | 155603 |
| opencode-go | gpt-6-luna | 61 | 3271 | 231450 | 359971 | 52315268 | 2832777 |
| opencode-go | hy4-flash-free | 4 | 3898982 | 312173 | 118095 | 275505792 | 0 |
| opencode-go | kimi-k2.7-code | 4 | 140658 | 991 | 3179 | 643584 | 0 |
| opencode-go | kimi-k3.1-pro | 5 | 4939435 | 125336 | 105311 | 55782910 | 390398 |
| opencode-go | longcat-2.5-free | 24 | 1312658 | 37327 | 149659 | 9254656 | 0 |
| opencode-go | longcat-2.5-preview-free | 71 | 7043816 | 94701 | 327157 | 26685824 | 0 |
| opencode-go | mimo-v2.6-flash | 119 | 6415952 | 347066 | 1244119 | 89437005 | 0 |
| opencode-go | qwen3.8-flash | 2 | 1185 | 3649 | 444 | 768 | 49759 |
| opencode-go | qwen4-max | 1 | 2258 | 142408 | 204 | 18365646 | 3055919 |
| opencode-go | step-5-preview-free | 10 | 931876 | 9597 | 38675 | 2913856 | 0 |
| openrouter | anthropic/claude-sonnet-4.5 | 1 | 0 | 0 | 0 | 0 | 0 |
| openrouter | deepseek/deepseek-v3.1-terminus | 1 | 10093 | 2 | 0 | 0 | 0 |
| openrouter | deepseek/deepseek-v4-flash | 331 | 12399556 | 639957 | 1154141 | 100031611 | 0 |
| openrouter | deepseek/deepseek-v4-pro | 9 | 117870 | 17316 | 12675 | 861897 | 0 |
| openrouter | openai/gpt-5.6-sol | 1 | 15350 | 92 | 130 | 7744 | 9953 |
| openrouter | qwen/qwen3-coder | 1 | 9583 | 1195 | 0 | 58791 | 0 |
| openrouter | qwen/qwen3-coder-next | 316 | 36686772 | 314464 | 0 | 46062928 | 0 |
| openrouter | ~openai/gpt-sol-latest | 1 | 0 | 0 | 0 | 0 | 0 |
| openrouter | ~openai/gpt-terra-latest | 1 | 0 | 0 | 0 | 0 | 0 |
| teamorouter | deepseek-flash | 48 | 2633639 | 253980 | 427737 | 36933559 | 0 |
| teamorouter | deepseek-flash-free | 10 | 180783 | 1290 | 2206 | 153472 | 0 |
| teamorouter | deepseek-v4-pro | 21 | 726536 | 21531 | 84772 | 3158528 | 0 |
| teamorouter | glm-5.3 | 1 | 2257281 | 68905 | 29321 | 20861487 | 282866 |
| teamorouter | glm-5.3-flash | 16 | 501671 | 2585 | 1956 | 206253 | 0 |
| teamorouter | glm-5.3-flash-free | 10 | 278236 | 2074 | 1014 | 33098 | 0 |
| teamorouter | gpt-6-luna | 3 | 0 | 0 | 0 | 0 | 0 |

### 4. Группировка по дням

День рассчитан по `time_created` в локальной зоне SQLite-хоста (`MSK`). Доля cache read = `cache_read / (input + cache_read)`; при нулевом знаменателе оставлена пустой.

SQL:

```sql
SELECT date(time_created/1000,'unixepoch','localtime') AS day, count(*) AS sessions, sum(tokens_input) AS input, sum(tokens_output) AS output, sum(tokens_cache_read) AS cache_read, round(1.0*sum(tokens_cache_read)/nullif(sum(tokens_input)+sum(tokens_cache_read),0),6) AS cache_read_share FROM session_v2 GROUP BY day ORDER BY day;
```

| День | Сессий | Input | Output | Cache read | Доля cache read |
|---|---:|---:|---:|---:|---:|
| 2026-08-25 | 1 | 15350 | 92 | 7744 | 0.335325 |
| 2026-08-26 | 4 | 55718 | 1469 | 76416 | 0.578322 |
| 2026-09-05 | 2 | 18569 | 24 | 0 | 0 |
| 2026-09-06 | 17 | 562496 | 16769 | 2120512 | 0.790349 |
| 2026-09-07 | 33 | 437304 | 14782 | 1335015 | 0.753259 |
| 2026-09-08 | 41 | 13318712 | 75539 | 3343424 | 0.20066 |
| 2026-09-09 | 52 | 16832152 | 111864 | 13566000 | 0.446277 |
| 2026-09-10 | 46 | 4022103 | 90055 | 20720809 | 0.837444 |
| 2026-09-11 | 3 | 0 | 0 | 0 | — |
| 2026-09-12 | 10 | 0 | 0 | 0 | — |
| 2026-09-13 | 11 | 0 | 0 | 0 | — |
| 2026-09-14 | 18 | 0 | 0 | 0 | — |
| 2026-09-15 | 42 | 0 | 0 | 0 | — |
| 2026-09-16 | 37 | 0 | 0 | 0 | — |
| 2026-09-17 | 51 | 44234 | 1236 | 27904 | 0.386814 |
| 2026-09-18 | 102 | 2224512 | 91571 | 13294720 | 0.856661 |
| 2026-09-19 | 15 | 502835 | 26964 | 2648064 | 0.840415 |
| 2026-09-20 | 25 | 630978 | 59455 | 4652544 | 0.880576 |
| 2026-09-21 | 2 | 53646 | 2638 | 268800 | 0.833628 |
| 2026-09-22 | 121 | 4891553 | 325683 | 30579008 | 0.862095 |
| 2026-09-23 | 213 | 7246949 | 519793 | 53453056 | 0.88061 |
| 2026-09-24 | 10 | 833786 | 40687 | 6310912 | 0.8833 |
| 2026-09-25 | 45 | 3239013 | 149293 | 18572032 | 0.851497 |
| 2026-09-26 | 36 | 1620242 | 133177 | 18018304 | 0.917497 |
| 2026-09-27 | 188 | 11895122 | 842401 | 118708480 | 0.908922 |
| 2026-09-28 | 93 | 9335290 | 569243 | 71179008 | 0.884054 |
| 2026-09-29 | 33 | 2465025 | 134345 | 13225984 | 0.842902 |
| 2026-09-30 | 1 | 186725 | 7167 | 915200 | 0.830547 |
| 2026-10-01 | 116 | 7775467 | 664977 | 78272439 | 0.909638 |
| 2026-10-02 | 113 | 9850098 | 408185 | 97954184 | 0.90863 |
| 2026-10-03 | 54 | 3713328 | 225797 | 43294208 | 0.921006 |
| 2026-10-04 | 52 | 3927295 | 236351 | 61368576 | 0.939854 |
| 2026-10-05 | 61 | 5003908 | 220792 | 39428640 | 0.887382 |
| 2026-10-06 | 17 | 830409 | 62652 | 5831424 | 0.875348 |
| 2026-10-07 | 1 | 90111 | 13291 | 2672128 | 0.967378 |
| 2026-10-08 | 28 | 648933 | 25388 | 2834236 | 0.813695 |
| 2026-10-09 | 102 | 0 | 0 | 0 | — |
| 2026-10-10 | 153 | 6845668 | 151127 | 51279492 | 0.882225 |
| 2026-10-11 | 79 | 9278133 | 317383 | 43760000 | 0.825067 |
| 2026-10-12 | 35 | 3220879 | 200609 | 14270720 | 0.815861 |
| 2026-10-13 | 54 | 7966537 | 360473 | 42128448 | 0.840971 |
| 2026-10-14 | 20 | 2491780 | 216325 | 13331584 | 0.842525 |
| 2026-10-15 | 31 | 2534826 | 146003 | 35564160 | 0.933467 |
| 2026-10-16 | 26 | 2607953 | 87794 | 26967356 | 0.91182 |
| 2026-10-18 | 8 | 789071 | 19586 | 8648576 | 0.916391 |
| 2026-10-19 | 6 | 459933 | 14267 | 6240128 | 0.931354 |
| 2026-10-22 | 18 | 2033381 | 36465 | 8108636 | 0.799509 |
| 2026-10-23 | 13 | 696301 | 40623 | 5350656 | 0.884851 |
| 2026-10-24 | 346 | 42416571 | 946060 | 314834019 | 0.881269 |
| 2026-10-25 | 130 | 12943526 | 602198 | 182221568 | 0.933679 |
| 2026-10-26 | 156 | 14201754 | 528393 | 177231360 | 0.925813 |
| 2026-10-27 | 145 | 9438423 | 830692 | 206364928 | 0.956264 |
| 2026-10-28 | 78 | 4275785 | 353238 | 67368832 | 0.94032 |
| 2026-10-29 | 7 | 10297982 | 118584 | 75180429 | 0.879525 |
| 2026-10-30 | 3 | 7697169 | 175690 | 182299008 | 0.959488 |
| 2026-10-31 | 2 | 3917445 | 80706 | 67216896 | 0.944929 |
| 2026-11-01 | 1 | 1784255 | 21658 | 8615296 | 0.82843 |
| 2026-11-02 | 3 | 1619238 | 92025 | 37730944 | 0.958851 |
| 2026-11-03 | 10 | 4020935 | 365112 | 180060992 | 0.978157 |
| 2026-11-04 | 43 | 2719098 | 325024 | 56877348 | 0.954375 |
| 2026-11-05 | 62 | 12863163 | 562093 | 202349433 | 0.94023 |
| 2026-11-06 | 45 | 647830 | 123145 | 21559467 | 0.970828 |
| 2026-11-07 | 38 | 5639393 | 186680 | 82861147 | 0.936278 |
| 2026-11-08 | 18 | 788983 | 62489 | 10114750 | 0.927641 |
| 2026-11-09 | 1 | 591137 | 43539 | 9380594 | 0.940719 |
| 2026-11-10 | 34 | 9160269 | 439677 | 113572321 | 0.925364 |
| 2026-11-11 | 2 | 353256 | 23107 | 5467092 | 0.939307 |
| 2026-11-12 | 9 | 2089145 | 97743 | 39399950 | 0.949646 |
| 2026-11-13 | 11 | 489134 | 43783 | 8955191 | 0.948209 |
| 2026-11-14 | 2 | 0 | 0 | 0 | — |
| 2026-11-15 | 29 | 5496702 | 311580 | 67234553 | 0.924424 |
| 2026-11-16 | 15 | 4267146 | 472598 | 296101390 | 0.985794 |
| 2026-11-17 | 9 | 821523 | 19614 | 3979520 | 0.828887 |
| 2026-11-18 | 17 | 444248 | 11408 | 3603808 | 0.890256 |
| 2026-11-19 | 33 | 3003752 | 72185 | 21177798 | 0.875783 |
| 2026-11-20 | 57 | 3354428 | 274903 | 40437047 | 0.9234 |
| 2026-11-21 | 4 | 5269948 | 186573 | 183082053 | 0.972021 |
| 2026-11-22 | 23 | 2455517 | 220309 | 79262524 | 0.969951 |
| 2026-11-23 | 109 | 15981726 | 1356330 | 572788881 | 0.972856 |
| 2026-11-24 | 95 | 20702142 | 1575620 | 915998648 | 0.977899 |
| 2026-11-25 | 9 | 1741484 | 224638 | 107950551 | 0.984124 |
| 2026-11-27 | 54 | 7164147 | 840505 | 416276076 | 0.983081 |
| 2026-11-28 | 6 | 1065591 | 195232 | 90994720 | 0.988425 |

### 5. Топ-20 сессий по cache read

Длительность — `(time_updated - time_created)` в секундах. `cache_read/input` не определён при нулевом input.

SQL:

```sql
SELECT id,title,directory,tokens_input AS input,tokens_cache_read AS cache_read,round(1.0*tokens_cache_read/nullif(tokens_input,0),6) AS cache_read_per_input,round((time_updated-time_created)/1000.0,1) AS duration_seconds FROM session_v2 ORDER BY tokens_cache_read DESC LIMIT 20;
```

| ID | Название | Directory | Input | Cache read | Cache read / input | Длительность, сек |
|---|---|---|---:|---:|---:|---:|
| `ses_df1320e30ffeXmkvex749WWOKO` | Bitrix24 Кинт интеграция | `/root/workspaces/projects/clients/sanatory-avto/kint-b24` | 8835316 | 458932823 | 51.943 | 316852.8 |
| `ses_e1bc367a0ffeP8k9YXxHp6U3mp` | OpenCode proof for agent-preflight-20261116.txt | `/root/workspaces/projects/clients/planeta-autostekla/.cache/wt-beget-existing-plan-20261116` | 3873377 | 275480704 | 71.121583 | 75619.4 |
| `ses_df79f9fbeffePKUfLaPupBgupZ` | Sanatorium Kind v24 Bitrix24 audit | `/root/workspaces/projects/clients/sanatory-avto/kint-b24` | 3852514 | 193318537 | 50.17984 | 21821.9 |
| `ses_e73d56386ffetrWGnDTX0B7IuR` | Cloud-init для восстановления HiDefi на новом сервере | `/root/workspaces/system/services/hiddify` | 6808860 | 145576832 | 21.3805 | 106362.4 |
| `ses_df6513358ffehEB3c4z1tOCo6S` | Kint booking card delivery | `/root/workspaces/projects/clients/sanatory-avto/kint-b24` | 4427582 | 143259802 | 32.356217 | 85817.8 |
| `ses_df16a5755ffeJwf4PznWzdyzUs` | Квота build→flash#low | `/root/workspaces/projects/incidents` | 2403423 | 130139667 | 54.147633 | 14702.2 |
| `ses_e5e15bd21ffetNibDBCZXKP201` | Отключение писем chatgpt-codex-connector | `/root/workspaces/projects/incidents` | 3084407 | 129872384 | 42.106111 | 146351.3 |
| `ses_e01182cd9ffehHcezO8cAJ6fHP` | Сбои PM2 и расходы Yandex Cloud | `/root` | 2712973 | 106755233 | 39.349906 | 92960.4 |
| `ses_df7732643ffeIBhPsksdlJe6jk` | Nginx Proxy Manager proxy hosts | `/root/workspaces/projects/incidents` | 2415197 | 103851926 | 42.99936 | 70304.5 |
| `ses_de380f3f9ffe24n9ol4xX3K97D` | Workspace directory structure audit | `/root/workspaces/projects/incidents` | 716522 | 87297219 | 121.834667 | 9166.3 |
| `ses_e555519ffffevsVzF0MrLM0koy` | Закрытие code-archive-test по контракту 5 строк | `/root/workspaces/projects/incidents` | 3041151 | 82299776 | 27.062049 | 28956.7 |
| `ses_de3cd1c86ffe2csuxaV0JfbV1D` | Yandex Cloud расходы оптимизация | `/root/workspaces/projects` | 1423415 | 79561472 | 55.894783 | 15027.1 |
| `ses_e02db2574ffe5CC2AAmmjkfrmh` | Очистка диска при заполнении 99% | `/root` | 2501716 | 76087588 | 30.414159 | 29138.0 |
| `ses_e5334312fffeHyrz9l4cTwzpOB` | Восстановление настроек OpenCode и MCP | `/root/workspaces` | 6870135 | 69346495 | 10.093906 | 172118.8 |
| `ses_de1336257ffet32EkWJ0OJtJJI` | C: батч записей в Б24 | `/root/workspaces/projects/clients/sanatory-avto/kint-b24` | 232228 | 65231104 | 280.892502 | 884.3 |
| `ses_e7879a657ffeq8kFXHFw9DIJ2S` | Анализ переписки КИНТ и Битрикс | `/root/workspaces/projects/clients/sanatory-avto` | 9015880 | 63170816 | 7.006617 | 348089.1 |
| `ses_df10e6333ffeWWkw1TrdPEyDCv` | Abandon flag + revert autopush off | `/root/workspaces/projects/incidents` | 388207 | 59847552 | 154.164021 | 1281.6 |
| `ses_e48ef7fb5ffeMSIIatmqtrXM3F` | Проверка настроек 2.2.6 и делегирования суб-агентов | `/root/workspaces/projects` | 4821565 | 55822704 | 11.577715 | 228037.2 |
| `ses_e6d82300affelYoDMNHJoTV0Qb` | Fix duplicate Yandex review replies in autoresponder | `/root/workspaces/projects` | 2704165 | 50858560 | 18.807491 | 16728.7 |
| `ses_dfb372acfffeScRrDh5Akvodnn` | Система агентов opencode с тимлидом | `/root` | 1530540 | 43515934 | 28.431752 | 52353.8 |

### 6. Рост размера part

Пять сессий с наибольшим `cache_read` среди сессий, имеющих строки в `part`. Это ограничение важно: первые пять по `cache_read/input` вообще не имеют частей в `part`, а четыре из пяти крупнейших по `cache_read` также не имеют таких строк.

SQL для выбора сессий:

```sql
WITH top5 AS (SELECT s.id,s.title,s.directory,s.tokens_input AS input,s.tokens_cache_read AS cache_read,1.0*s.tokens_cache_read/nullif(s.tokens_input,0) AS ratio,round((s.time_updated-s.time_created)/1000.0,1) AS duration_seconds FROM session_v2 s WHERE EXISTS (SELECT 1 FROM part p WHERE p.session_id=s.id) ORDER BY s.tokens_cache_read DESC LIMIT 5) SELECT *, (SELECT count(*) FROM part p WHERE p.session_id=top5.id) AS parts FROM top5;
```

| ID | Название | Directory | Input | Cache read | Cache read / input | Длительность, сек | Parts |
|---|---|---|---:|---:|---:|---:|---:|
| `ses_e73d56386ffetrWGnDTX0B7IuR` | Cloud-init для восстановления HiDefi на новом сервере | `/root/workspaces/system/services/hiddify` | 6808860 | 145576832 | 21.3805 | 106362.4 | 1448 |
| `ses_e7879a657ffeq8kFXHFw9DIJ2S` | Анализ переписки КИНТ и Битрикс | `/root/workspaces/projects/clients/sanatory-avto` | 9015880 | 63170816 | 7.006617 | 348089.1 | 1277 |
| `ses_e6d82300affelYoDMNHJoTV0Qb` | Fix duplicate Yandex review replies in autoresponder | `/root/workspaces/projects` | 2704165 | 50858560 | 18.807491 | 16728.7 | 765 |
| `ses_e725a1c92ffenViNuGOFlWx8Ja` | Настройка доступа к Git и создание репозиториев | `/root/workspaces/projects` | 649210 | 34851328 | 53.682672 | 6518.8 | 672 |
| `ses_f75706f87ffeCFf75UfKxXK2ui` | Copy and remove files (@general subagent) | `/root/workspaces/tools` | 3112089 | 17491232 | 5.620415 | 1007.9 | 1598 |

Для каждой части ниже `n:chars/cumulative_chars`; значения сняты с первых, средних и последних 10 частей. Накопление — сумма `length(data)` с начала сессии.

SQL:

```sql
WITH top5 AS (SELECT s.id,s.title,s.tokens_cache_read FROM session_v2 s WHERE EXISTS (SELECT 1 FROM part p WHERE p.session_id=s.id) ORDER BY s.tokens_cache_read DESC LIMIT 5), p AS (SELECT p.session_id,p.id,p.time_created,length(p.data) AS chars,row_number() OVER (PARTITION BY p.session_id ORDER BY p.time_created,p.id) AS rn,count(*) OVER (PARTITION BY p.session_id) AS n,sum(length(p.data)) OVER (PARTITION BY p.session_id ORDER BY p.time_created,p.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_chars FROM part p JOIN top5 t ON t.id=p.session_id), samples AS (SELECT session_id,'first' AS segment,rn,n,chars,cumulative_chars FROM p WHERE rn<=10 UNION ALL SELECT session_id,'middle',rn,n,chars,cumulative_chars FROM p WHERE rn>n/2-5 AND rn<=n/2+5 UNION ALL SELECT session_id,'last',rn,n,chars,cumulative_chars FROM p WHERE rn>n-10) SELECT t.id,t.title,s.segment,group_concat(s.rn||':'||s.chars||'/'||s.cumulative_chars,' ') AS part_char_cumulative FROM samples s JOIN top5 t ON t.id=s.session_id GROUP BY t.id,t.title,s.segment,t.tokens_cache_read ORDER BY t.tokens_cache_read DESC,CASE s.segment WHEN 'first' THEN 1 WHEN 'middle' THEN 2 ELSE 3 END;
```

| ID | Сегмент | Позиция: размер/накопление |
|---|---|---|
| `ses_e73d56386ffetrWGnDTX0B7IuR` | first | 1:1377/1377 2:21/1398 3:850/2248 4:10211/12459 5:10181/22640 6:158/22798 7:21/22819 8:1922/24741 9:746/25487 10:1261/26748 |
| `ses_e73d56386ffetrWGnDTX0B7IuR` | middle | 720:1150/2016880 721:163/2017043 722:21/2017064 723:145/2017209 724:1903/2019112 725:163/2019275 726:21/2019296 727:8564/2027860 728:4590/2032450 729:163/2032613 |
| `ses_e73d56386ffetrWGnDTX0B7IuR` | last | 1439:5494/3543405 1440:165/3543570 1441:21/3543591 1442:326/3543917 1443:2316/3546233 1444:164/3546397 1445:21/3546418 1446:1191/3547609 1447:1502/3549111 1448:157/3549268 |
| `ses_e7879a657ffeq8kFXHFw9DIJ2S` | first | 1:533/533 2:21/554 3:1546/2100 4:52244/54344 5:161/54505 6:21/54526 7:1065/55591 8:3366/58957 9:163/59120 10:21/59141 |
| `ses_e7879a657ffeq8kFXHFw9DIJ2S` | middle | 634:9262/2526816 635:303/2527119 636:50707/2577826 637:7097/2584923 638:166/2585089 639:21/2585110 640:7740/2592850 641:356/2593206 642:166/2593372 643:21/2593393 |
| `ses_e7879a657ffeq8kFXHFw9DIJ2S` | last | 1268:13687/4069666 1269:166/4069832 1270:21/4069853 1271:22901/4092754 1272:2432/4095186 1273:159/4095345 1274:85/4095430 1275:2209/4097639 1276:85/4097724 1277:727/4098451 |
| `ses_e6d82300affelYoDMNHJoTV0Qb` | first | 1:8104/8104 2:21/8125 3:1409/9534 4:11530/21064 5:24322/45386 6:15961/61347 7:159/61506 8:21/61527 9:381/61908 10:118543/180451 |
| `ses_e6d82300affelYoDMNHJoTV0Qb` | middle | 378:7820/1278057 379:165/1278222 380:21/1278243 381:505/1278748 382:17162/1295910 383:164/1296074 384:21/1296095 385:10471/1306566 386:4232/1310798 387:161/1310959 |
| `ses_e6d82300affelYoDMNHJoTV0Qb` | last | 756:164/2146116 757:21/2146137 758:1632/2147769 759:1924/2149693 760:157/2149850 761:114/2149964 762:21/2149985 763:1276/2151261 764:738/2151999 765:160/2152159 |
| `ses_e725a1c92ffenViNuGOFlWx8Ja` | first | 1:205/205 2:21/226 3:314/540 4:1724/2264 5:161/2425 6:21/2446 7:233/2679 8:1330/4009 9:160/4169 10:21/4190 |
| `ses_e725a1c92ffenViNuGOFlWx8Ja` | middle | 332:21/653818 333:263/654081 334:5739/659820 335:164/659984 336:21/660005 337:341/660346 338:6333/666679 339:162/666841 340:21/666862 341:11996/678858 |
| `ses_e725a1c92ffenViNuGOFlWx8Ja` | last | 663:2720/1075170 664:1512/1076682 665:164/1076846 666:21/1076867 667:1707/1078574 668:1276/1079850 669:165/1080015 670:21/1080036 671:1046/1081082 672:156/1081238 |
| `ses_f75706f87ffeCFf75UfKxXK2ui` | first | 1:991/991 2:21/1012 3:592/1604 4:157/1761 5:21/1782 6:589/2371 7:156/2527 8:21/2548 9:589/3137 10:155/3292 |
| `ses_f75706f87ffeCFf75UfKxXK2ui` | middle | 795:21/204318 796:589/204907 797:156/205063 798:21/205084 799:589/205673 800:158/205831 801:21/205852 802:589/206441 803:158/206599 804:21/206620 |
| `ses_f75706f87ffeCFf75UfKxXK2ui` | last | 1589:156/408198 1590:21/408219 1591:605/408824 1592:156/408980 1593:21/409001 1594:605/409606 1595:156/409762 1596:21/409783 1597:605/410388 1598:156/410544 |

**Сверка группировки:** `input_match=1`, `output_match=1`, `reasoning_match=1`, `cache_read_match=1`, `cache_write_match=1`; все `*_delta=0`.

**Ограничение сканирования:** Gitleaks сообщил `no leaks found`, но также `scanned ~0 bytes`; это не подтверждает сканирование содержимого базы.
