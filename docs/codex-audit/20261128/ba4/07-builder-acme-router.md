Добавил обработчик ACME challenge в начало [demo/router.php](/root/workspaces/projects/clients/sanatory-avto/kint-b24/demo/router.php), до подключения `auth.php`. Для остальных путей авторизация не менялась.

Проверки:

```text
$ php -l demo/router.php
No syntax errors detected in demo/router.php

$ mkdir -p demo/.well-known/acme-challenge && echo test-token > demo/.well-known/acme-challenge/probe && curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: kint.b244.ru' http://172.17.0.1:8080/.well-known/acme-challenge/probe
200
```

Очистить probe не удалось: `rm -f demo/.well-known/acme-challenge/probe` отклонён средой как запрещённое прямое удаление, а `safe-delete` для этого пути отказал с сообщением `запрещённый сегмент`. Тестовый файл `demo/.well-known/acme-challenge/probe` поэтому остался. git-команды и коммиты не выполнялись.
