Изменён только [opencode.jsonc](/root/.config/opencode/opencode.jsonc): включён `repowise`, добавлены разрешения для `pm2-inspect*`, четырёх форм `git push`, двух навыков и ролей `audit`/`verifier`. Существующие deny сохранены.

Проверка JSONC:

```text
пройдено: opencode debug config завершилась с кодом 0
```

Проверки правил: все 8 пройдены, включая наличие destructive push deny и deny для `pm2 jlist*` и `pm2 describe*`. Git-команды не запускал.
