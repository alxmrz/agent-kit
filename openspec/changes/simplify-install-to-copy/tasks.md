# Tasks

## 1. Компоненты: группы вместо профилей

- [x] 1.1 Переложить `components/rules/` и `components/skills/` в `components/base/`, а `php_rules.md` — в `components/php/rules/`; проверить `find components -type f`, что все 8 файлов на месте и `components/profiles/` удалён.
- [x] 1.2 Добавить пустые `components/base/commands/` и `components/base/agents/` с `.gitkeep`-описанием (или без файлов вовсе) и убедиться, что установка на пустом каталоге не падает.
- [x] 1.3 Убрать из `components/base/rules/general_rules.md` ссылку на `docs/php_rules.md` и описать PHP-специфику как отдельную группу; проверить, что `grep -c php_rules` по файлу равно 0.
- [x] 1.4 Обновить `AGENTS.md` kit-а и `README.md`: раскладка `components/<группа>/<тип>/`, состав `base`, отсутствие слияний; проверить, что описанные в README команды совпадают с `install.sh --help`.

## 2. lib: минимум для копирования

- [x] 2.1 Заменить `lib/components.sh` на поиск групп (`components/*/`) и валидацию выбора; проверить вручную: неизвестная группа даёт `die` со списком доступных.
- [x] 2.2 Расширить `target_path` ветками `commands/` и `agents/` (`.opencode/commands/<PREFIX>_<x>`, `.opencode/agents/<PREFIX>_<x>`); проверить `sh -c '. lib/...; target_path commands/review.md'`.
- [x] 2.3 Сократить `lib/render.sh` до режима `refs`, убрать `neutralize`, `stamp`, `apply_profile_rules`, `stamp_skill`; проверить, что `grep -n 'stamp\|neutralize' lib/render.sh` пуст.
- [x] 2.4 Удалить `lib/manifest.sh` и `sha256_of` из `lib/common.sh`; проверить, что `grep -rn 'sha256_of\|manifest' install.sh lib/` не находит остатков.
- [x] 2.5 Удалить `lib/merge.py` и `snippets/openspec.rules.tsv`; убрать шаг `python3 -m py_compile` из `.github/workflows/ci.yml`.
- [x] 2.6 Прогнать `dash -n install.sh bootstrap.sh lib/*.sh tests/smoke.sh` и `shellcheck -s sh` по тем же файлам — оба должны завершиться без ошибок.

## 3. install.sh: одна команда установки

- [x] 3.1 Оставить команду `install` (и `--dry-run`), удалить `status`, `uninstall`, `adopt`, `prune_components`, `install_opencode_json`, `install_openspec_rules`, `write_manifest` и их `case`-ветки; проверить `install.sh --help` — в нём только установка.
- [x] 3.2 Заменить `--profile` на повторяемый `--with <группы>` с разбором запятых и пробелов и валидацией до первой записи; проверить: `--with 'php, js'` ставит обе группы, `--with nope` не создаёт ни одного файла.
- [x] 3.3 Сделать перезапись безусловной: убрать `--keep-modified`, `--force`, `--no-agents`, `--no-openspec` и всю логику локальных правок; проверить: правка в `.agents/rules/alxmrz_kit_general_rules.md` исчезает после повторного запуска.
- [x] 3.4 Обновить `bootstrap.sh`: перестать пробрасывать удалённые флаги, `--offline` оставить; проверить `dash -n bootstrap.sh` и запуск `sh bootstrap.sh --offline --dir <tmp-проект>` на локальном клоне через `AGENT_KIT_DIR`.
- [x] 3.5 Печатать подсказку со списком путей правил для `instructions[]`, только когда `AGENTS.md` уже существовал; проверить оба случая вручную на двух временных проектах.

## 4. AGENTS.md из шаблона

- [x] 4.1 Проверить и при необходимости поправить `snippets/AGENTS.md.tmpl`: упоминания слияний и `openspec.rules.tsv` должны исчезнуть, плейсхолдер `{{TEST_CMD}}` подставляется; проверить `grep -c '{{' AGENTS.md` в свежепоставленном проекте равно 0.
- [x] 4.2 Убедиться, что `.gitignore` дописывается идемпотентно и что симлинк на `AGENTS.md` трактуется как существующий файл; проверить на временном проекте с symlink-ом и без.

## 5. Тесты

- [x] 5.1 Переписать `tests/smoke.sh` под новую модель: базовый набор, перезапись правки, идемпотентность второго запуска, `--with` (одна/несколько/неизвестная группа), `commands/` и `agents/` в `.opencode/`, `AGENTS.md` (создание/сохранение своего/симлинк), `.gitignore`, границы записи, `--dry-run`; прогнать `./tests/smoke.sh` — все проверки зелёные.
- [x] 5.2 Убедиться, что тест не трогает `$HOME` и не оставляет следов, и что он падает при искусственной поломке (например, при копировании без `refuse_symlink`).

## 6. Интеграционная проверка

- [x] 6.1 Прогнать полный набор из `AGENTS.md`: `dash -n`, `shellcheck`, `./tests/smoke.sh`; все шаги зелёные, `py_compile` в списке больше нет.
- [x] 6.2 Прогнать установку в этот репозиторий-песочницу через `AGENT_KIT_DIR` и `--dir` на временном git-проекте, проверить `git status` — ровно ожидаемые новые файлы, без мусора.
- [x] 6.3 Сверить README и `--help` с фактическим поведением (флаги, каталоги, состав `base`); расхождений нет.

## Workflow follow-up

- Archive the change after the project's review requirements are satisfied.
