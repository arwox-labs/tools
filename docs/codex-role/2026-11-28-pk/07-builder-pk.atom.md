Исправлено: [bin/sync-loop.php](/root/workspaces/projects/clients/sanatory-avto/kint-b24/bin/sync-loop.php:84) возвращает быстрый интервал при изменениях и ограничивает idle-пик формулой `min(current * 2, max(fast, 30))`. В [tests/test_cli.php](/root/workspaces/projects/clients/sanatory-avto/kint-b24/tests/test_cli.php:212) добавлена проверка; ожидание idle-пика изменено с `5` на `10`. Размер набора: `8986/9000` строк.

Приёмка: `php -l bin/sync-loop.php` → `No syntax errors detected in bin/sync-loop.php`; `php tests/test_cli.php` → exit 0; `bash bin/check.sh` → `GATE: PASS`. KINT и Git не тронуты; Beads `kint-b24-mjk` закрыт. Обновление индекса CBM заблокировал `chmod 0700 failed (errno 30)`. Время: 5 мин 48 с.

> Проверено: `php -l bin/sync-loop.php`, `php tests/test_cli.php`, `bash bin/check.sh` → `GATE: PASS`; 8986 строк тестов. [Изменения](/root/workspaces/projects/clients/sanatory-avto/kint-b24/bin/sync-loop.php:84)
> Контур закрыт
