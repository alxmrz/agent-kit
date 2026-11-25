# Spec Delta

## Purpose

Defines the POSIX `sh` entry point that runs as `curl … | sh` on a clean machine, validates its
runtime dependency and then delegates the installation to the Python installer.

## ADDED Requirements

### Requirement: POSIX sh как точка входа

Файл `bootstrap.sh` SHALL оставаться единственным shell-скриптом установки, совместимым со строгим
POSIX `sh`: без `[[ ]]`, массивов, `local` и `pipefail`. Он MUST работать при запуске через
`curl … | sh`, то есть без чтения собственного файла и без предположений о текущем каталоге.

#### Scenario: Запуск через curl
- **WHEN** `bootstrap.sh` передан в `sh` через стандартный ввод
- **THEN** установка проходит так же, как при прямом запуске

#### Scenario: Синтаксис проверен
- **WHEN** CI выполняет `dash -n bootstrap.sh` и `shellcheck -s sh bootstrap.sh`
- **THEN** обе проверки завершаются успешно

### Requirement: Проверка python3 до клонирования

`bootstrap.sh` SHALL проверять наличие `python3` и `git` до создания клона. При отсутствии любой из
зависимостей он MUST завершиться ошибкой с сообщением об этой зависимости и MUST NOT создавать или
изменять что-либо в проекте.

#### Scenario: Нет python3
- **WHEN** `bootstrap.sh` запускается в окружении без `python3`
- **THEN** печатается ошибка о нехватке `python3`, код возврата ненулевой, каталог `.agent-kit/` не создан

#### Scenario: Нет git
- **WHEN** `bootstrap.sh` запускается в окружении без `git`
- **THEN** печатается ошибка о нехватке `git`, ничего не записывается в проект

### Requirement: Вызов Python-установщика

`bootstrap.sh` SHALL запускать `python3 "$KIT_DIR/install.py"`, передавая ему все аргументы, кроме
своего собственного `--offline`, и добавляя `--dir <корень проекта>`, когда `--dir` не указан.
Код возврата установщика SHALL становиться кодом возврата `bootstrap.sh`.

#### Scenario: Флаги прозрачны
- **WHEN** `bootstrap.sh` запускается с `--with php,js --dry-run`
- **THEN** установка получает те же `--with` и `--dry-run`

#### Scenario: Целевой каталог по умолчанию
- **WHEN** `bootstrap.sh` запускается без `--dir`
- **THEN** установка получает `--dir` с корнем git-проекта (или текущим каталогом вне git)

#### Scenario: Ошибка установки
- **WHEN** `install.py` завершился ненулевым кодом
- **THEN** `bootstrap.sh` возвращает тот же код и оставляет клон на месте

### Requirement: Собственный флаг --offline

`bootstrap.sh` SHALL понимать `--offline` (не обновлять существующий клон) и MUST NOT передавать
его установщику.

#### Scenario: Обновление клона пропущено
- **WHEN** `bootstrap.sh` запускается с `--offline` и в проекте уже есть клон
- **THEN** клон не обновляется, установка выполняется с текущей ревизии

### Requirement: Подсказка о способе обновления

После успешной установки `bootstrap.sh` SHALL удалять свой клон, если тот создан этим запуском или
находится внутри проекта без незакоммиченных изменений, и MUST NOT ссылаться в выводе на удалённый
файл установщика.

#### Scenario: Клон удалён
- **WHEN** установка прошла успешно из свежего клона внутри проекта
- **THEN** каталог `.agent-kit/` удалён и итоговый вывод не предлагает запускать файл из него

#### Scenario: Клон вне проекта
- **WHEN** клон задан через `AGENT_KIT_DIR` вне проекта
- **THEN** клон не удаляется
