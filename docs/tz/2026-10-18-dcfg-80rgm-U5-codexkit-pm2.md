# ТЗ dcfg-80rgm U5 — шаблон Codex и реестр PM2 без курьера
FILE: .codex-kit/templates/global-AGENTS.md
FILE: docs/PM2-PROCESSES.md

Контекст: курьер ship/ship-post отключён владельцем 17.10 (dcfg-hrkh5); 18.10 процесс PM2 `ship-post` удалён по слову владельца (`pm2 save`, в dump.pm2 ship* = 0). Закон доставки — `CLAUDE.md:3` «GITHUB НАПРЯМУЮ».
5 Whys: реестр PM2 описывает процесс, которого больше нет → после удаления реестр не обновлён; шаблон Codex диктует доставку курьером → не обновлён после 17.10. ADR: строки реестра о ship-post удалить (процесса нет; откат записан в bd dcfg-zirjh), в шаблоне заменить доставку на «GitHub напрямую».

## Правки
1. `docs/PM2-PROCESSES.md`: удалить целиком две строки таблицы — начинающуюся с ``| `ship-post` |`` и начинающуюся с ``| `ship-post-events` |``. Файл большой — найди их через Grep `ship-post`, не читай файл целиком. Больше ничего не менять.
2. `.codex-kit/templates/global-AGENTS.md` строка 5 (`For owner-authorized work: …`): фрагмент про доставку курьером / `ship-post` / `tools/bin/ship` заменить на: `then deliver by GITHUB DIRECT (projects/CLAUDE.md «GITHUB НАПРЯМУЮ»): \`git push -u origin <own codex/* branch>\` → \`gh pr create --base main\` → \`gh pr merge\` → \`git-sync\` → \`bd close\` with the PR number.` Остальной текст строки сохранить.

## Запреты
Только эти 2 файла и эти строки. Без rm -rf, force-push, --no-verify.

## Готово, когда
`grep -c -E 'ship-post|tools/bin/ship|курьер|почтальон'` по 2 файлам = 0.
