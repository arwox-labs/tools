Проверь пять утверждений о гейте Codex и по каждому дай вердикт ПОДТВЕРЖДЕНО/ОПРОВЕРГНУТО с цитатой файла и строкой.

1. /root/.config/opencode/plugins/codex-first/detect.js — функция ranCodex считает запуском codex любое упоминание строки "codex exec" в тексте инструмента.
2. detect.js — sawFallback принимает любой вывод со строкой "FALLBACK:" как законный фолбэк.
3. detect.js — didEdits ловит только инструменты edit/write/apply_patch/patch, правки через shell не видит.
4. /root/.config/opencode/plugins/codex-first/index.js — после MAX_CORRECTIONS замечаний проверка прекращается, блокировки нет.
5. index.js — правка, сделанная дочерней сессией через инструмент subagent, не поднимает коррекцию в родительской сессии.

Формат ответа: строка на утверждение, без вступлений. Файлы только читать.