# Tasks

## 1. Каркас Python-установки

- [x] 1.1 Добавить `kit/__init__.py` (пустой или с `__all__`) и `kit/common.py`: `PREFIX`, `log/step/ok/skip/warn`, класс `KitError`, `resolve_project_dir` (раскрытие `~`, канонический путь, отказ от `/` и `$HOME`), `in_project`, `refuse_symlink`; проверить `python3 -c 'import kit.common'`.
- [x] 1.2 Добавить `kit/components.py`: `list_groups`, `group_names`, `group_exists`, `list_sources(components_dir, groups)` (без файлов с точкой в начале), `target_path(prefix, rel)` с ошибкой на вложенность в `rules/`, `commands/`, `agents/`; проверить вручную `target_path` для всех четырёх типов.
- [x] 1.3 Добавить `kit/render.py`: `rewrite_refs(text)` (те же четыре правила, что в `sed`, включая ограничение слева `[^/.A-Za-z0-9_-]`), `write_if_changed(path, data, mode)` (пропуск при совпадении байт, временный файл с pid, `os.replace`, `finally`), `copy_component(...)` с проверкой симлинка и сохранением прав источника; проверить, что `mtime` неизменного файла не меняется.
- [x] 1.4 Перенести `lib/merge.py` в `kit/merge.py` как функцию с результатом `(status, added)` вместо кодов 0/2/3 и без процесса: сохранить отступ, CRLF, однострочность, сравнение без `./` и «только дополнение»; проверить на файле с отступом 4, CRLF и одном строкой.

## 2. install.py

- [x] 2.1 Создать `install.py`: чтение `VERSION`, `--help` (версия, флаги, список групп, что появляется в проекте), разбор `install`/`--dir`/`--with`/`--dry-run`/`-h`/`--help` с ошибками «требует значение», «неизвестный флаг», «лишний аргумент»; `--with` режется по запятым и пробелам, повтор объединяет.
- [x] 2.2 Перенести шаги установки: `validate_groups` (ошибка до первой записи), `install_components` (список целей собирается в память), `install_agents_md` (`SKIP` при существующем файле или симлинке, `sed`-подстановка `{{TEST_CMD}}` заменяется `str.replace`), `install_opencode_json` (SKIP при `opencode.jsonc`, SKIP при симлинке, план в `--dry-run`, вызов `kit.merge`, печать `added:`) и `instructions_list` из собранных целей.
- [x] 2.3 Оформить вывод и завершение: те же `step/ok/skip/warn`, `WARN`/`ERROR` в stderr, `KitError` → `ERROR:` + код 1, обработчики `SIGHUP`/`SIGINT`/`SIGTERM` → очистка + код 130, подсказка «Обновить» через `AGENT_KIT_EPHEMERAL` (повторный `bootstrap.sh`) иначе путь к `install.py`, подсказка про `openspec init`, когда каталога `openspec/` нет.
- [x] 2.4 Убедиться, что при любой ошибке в проект не попадает половина файлов: валидация групп и каталога происходит до первого шага, а прерывание удаляет временные файлы.

## 3. bootstrap.sh

- [x] 3.1 Добавить проверку `python3` рядом с `git` до создания клона: `ERROR: нужен python3`.
- [x] 3.2 Переключить вызов на `python3 "$KIT_DIR/install.py"`, оставив проброс аргументов, `--dir <TARGET>` по умолчанию, `--offline` без проброса и код возврата установщика.
- [x] 3.3 Проверить `dash -n bootstrap.sh`, `shellcheck -s sh bootstrap.sh` и запуск через `AGENT_KIT_DIR` на локальном клоне с `--dry-run`.

## 4. Тесты на Python

- [x] 4.1 Переписать `tests/smoke.sh` в `tests/smoke.py`: хелперы `ok/bad/check`, `new_project` (`git init`), `kit_ext` (группы `js`/`go`, `commands/`, `agents/`), временный корень в `tempfile` с очисткой в `finally`, вызов установки через `subprocess.run([sys.executable, install.py, ...])`.
- [x] 4.2 Перенести все блоки проверок: базовая установка (включая валидность `opencode.json` без shell), перезапись, идемпотентность, чужие файлы, `--with` (одна/несколько/неизвестная/пробелы), `opencode.json` (создание, чужой конфиг, 4 пробела, CRLF, однострочный, JSONC, `opencode.jsonc`, симлинк, отсутствие дублей), `commands/`/`agents/`, `AGENTS.md` (создание/свой/симлинк), `.gitignore`, `--dry-run`, границы записи (`$HOME`, `$HOME/`, `env -u HOME`, `/`, файл вместо каталога, симлинк), `bootstrap.sh` (клонирование, удаление клона, dry-run, внешний клон, ошибка установки, повтор, грязный клон), битый компонент.
- [x] 4.3 Проверки, которые раньше делал shell (`python3 -c ...`, `env -u HOME`, `git`), оформить без `sh -c`; итог `PASS`/`FAIL` и ненулевой код при провале; прогнать `python3 tests/smoke.py` — все проверки зелёные, временных следов нет.

## 5. Удаление shell-установки и CI

- [x] 5.1 Удалить `install.sh`, `lib/common.sh`, `lib/components.sh`, `lib/render.sh`, `lib/merge.py`, `tests/smoke.sh`.
- [x] 5.2 Обновить `.github/workflows/ci.yml`: `dash -n`/`shellcheck` только для `bootstrap.sh`, `python3 -m compileall -q install.py kit tests`, `python3 tests/smoke.py`.
- [x] 5.3 Проверить, что `grep -rn 'install\.sh\|lib/.*\.sh\|smoke\.sh' --exclude-dir=.git .` не находит живых упоминаний (кроме истории в `openspec/changes/archive`).

## 6. Документация

- [x] 6.1 `README.md`: состав репозитория (`install.py`, `kit/`, `tests/smoke.py`), требования (`python3` обязателен, `git` для bootstrap), команда проверки `python3 tests/smoke.py`, локальный запуск `python3 install.py`.
- [x] 6.2 `AGENTS.md`: раздел проверки (нет `dash -n` по `lib/*.sh`, вместо него `compileall`), устройство (пакет `kit/`, `install.py`), правила правки компонентов без изменений, убрать «Python — необязательная зависимость».
- [x] 6.3 Сверить `--help` и README с фактическим поведением: флаги, подсказки, обязательность `python3`, отсутствие упоминаний `install.sh`.

## 7. Интеграционная проверка

- [x] 7.1 Прогнать полный набор: `dash -n bootstrap.sh`, `shellcheck -s sh bootstrap.sh`, `python3 -m compileall -q install.py kit tests`, `python3 tests/smoke.py`.
- [x] 7.2 Проверить установку в этот репозиторий-песочницу через `--dir` на временном git-проекте: файлы на месте, `opencode.json` валиден, `git status` без мусора.
- [x] 7.3 Прогнать `bootstrap.sh` через локальный «origin» с `--with php` и `--offline --dry-run`; убедиться, что клон удаляется и `.agent-kit/` не остаётся.

## Workflow follow-up

- Archive the change after the project's review requirements are satisfied.
