1) `/tmp/*` — отказ по правилу владельца: артефакты хранятся в `tools/docs`, не в `/tmp`.
2) `RUNNER`: `role`, `model`, `sandbox`, `rc`, `bytes`, `atom_sha`, `out`; при ошибке — ещё `err`, при пустом артефакте — `empty`.
3) Ролям с `sandbox=read-only` назначен timeout 300 секунд.
