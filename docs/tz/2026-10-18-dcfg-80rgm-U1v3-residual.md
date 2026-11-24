# ТЗ dcfg-80rgm U1v3 — остаток U1v2: три фрагмента о курьере
FILE: x/AGENTS.md
FILE: x/rules/owner-operations.md

5 Whys: после U1v2 grep `ship-post` даёт 3 совпадения → 2 внёс сам текст U1v2 («the ship/ship-post courier is off») → дефект ТЗ главного агента; 1 — строка, не попавшая в U1v2. ADR: три точные замены ниже, остальное не трогать.

## Замены (old — точная подстрока, new — замена)
x/AGENTS.md:
1. old `(owner 17.10, epic dcfg-hrkh5; the ship/ship-post courier is off and must not be invoked)` → new `(owner 17.10, epic dcfg-hrkh5; the old delivery courier is off and must not be invoked)`
x/rules/owner-operations.md:
2. old `owner 17.10; the ship/ship-post courier is off)` → new `owner 17.10; the old delivery courier is off)`
3. old `submit the own Codex atom through \`ship-post --submit\`; its successful local commit and normal Beads closure provide the SHA receipt.` → new `deliver the own Codex atom by GITHUB DIRECT; the merged PR number (or, in a repo without origin, the local commit SHA) in the Beads closure is the receipt.`

## Запреты
Только эти 3 замены.

## Готово, когда
`grep -c -E 'ship-post|tools/bin/ship|курьер|почтальон'` по 2 файлам = 0.
