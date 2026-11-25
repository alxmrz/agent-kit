# Spec Delta

## Purpose

Defines how the kit connects the rule files it installs to the agent by extending `instructions[]`
in the project's `opencode.json`, without disturbing the rest of that config.

## ADDED Requirements

### Requirement: Пути правил в instructions[]

Установка SHALL добавлять в `instructions[]` файла `opencode.json` путь к каждому правилу,
поставленному в `.agents/rules/`: правило группы `base` и правила всех групп, выбранных `--with`.
Пути SHALL быть относительными и начинаться с `./`.

#### Scenario: Только base
- **WHEN** установка выполняется без `--with`
- **THEN** `instructions[]` содержит `./.agents/rules/alxmrz_kit_general_rules.md`

#### Scenario: Несколько групп
- **WHEN** установка выполняется с `--with php,js`, и каждая группа ставит правило
- **THEN** `instructions[]` содержит пути правил base, php и js

#### Scenario: Группа без правил
- **WHEN** выбранная группа не ставит ни одного файла в `.agents/rules/`
- **THEN** её путь в `instructions[]` не появляется

### Requirement: Создание opencode.json

Если файла `opencode.json` в проекте нет, установка SHALL создать его с ключом `instructions`,
содержащим пути правил.

#### Scenario: Конфига нет
- **WHEN** установка проходит в проект без `opencode.json`
- **THEN** файл создан, валиден как JSON и содержит пути правил в `instructions[]`

#### Scenario: Пустой каталог проекта
- **WHEN** установка проходит в пустой проект с `--dry-run`
- **THEN** `opencode.json` не создаётся

### Requirement: Сохранение чужого содержимого

Существующий `opencode.json` установка MUST NOT переписывать целиком: она SHALL только дописывать
отсутствующие пути правил. Прочие ключи, прежние записи `instructions[]` и их порядок MUST
сохраняться.

#### Scenario: Чужой конфиг
- **WHEN** в `opencode.json` есть ключ `model` и запись `./docs/my_rules.md` в `instructions[]`
- **THEN** после установки `model` и `./docs/my_rules.md` на месте, а пути kit-а добавлены после них

#### Scenario: Запись kit-а уже есть
- **WHEN** путь правила kit-а уже присутствует в `instructions[]` в другой форме записи
- **THEN** дубликат не добавляется

### Requirement: Сохранение форматирования

Установка SHALL сохранять отступ существующего файла, переводы строк CRLF и однострочную форму
JSON. Если добавлять нечего, файл MUST NOT перезаписываться.

#### Scenario: Отступ 4 пробела
- **WHEN** существующий `opencode.json` отформатирован с отступом 4 пробела
- **THEN** после установки отступ остаётся 4 пробела

#### Scenario: CRLF
- **WHEN** существующий `opencode.json` использует CRLF
- **THEN** после установки файл остаётся с CRLF

#### Scenario: Однострочный конфиг
- **WHEN** существующий `opencode.json` записан одной строкой
- **THEN** после установки он остаётся одной строкой

#### Scenario: Повторный запуск
- **WHEN** установка запускается повторно без изменений в kit-е
- **THEN** `opencode.json` побайтово прежний

### Requirement: Файл не поддержан

Если `opencode.json` содержит комментарии JSONC или невалидный JSON, а также если в проекте есть
`opencode.jsonc`, установка MUST NOT изменять или создавать конфиг и SHALL напечатать пути правил
для ручной вставки. Остальные файлы kit-а при этом SHALL ставиться, а установка завершаться успешно.

#### Scenario: Комментарии в JSON
- **WHEN** `opencode.json` содержит комментарий `//`
- **THEN** файл не изменяется и в выводе есть готовый список путей для `instructions[]`

#### Scenario: opencode.jsonc
- **WHEN** в проекте есть `opencode.jsonc` и нет `opencode.json`
- **THEN** ни один из файлов не создаётся и не изменяется, печатаются пути для ручной вставки

### Requirement: Отсутствие python3

Если `python3` недоступен, установка MUST NOT изменять `opencode.json` и SHALL напечатать пути
правил для ручной вставки. Остальные файлы kit-а SHALL ставиться.

#### Scenario: python3 нет в PATH
- **WHEN** установка запускается в окружении без `python3`
- **THEN** `opencode.json` не создаётся, печатается список путей, файлы правил и `AGENTS.md` на месте

### Requirement: Симлинк вместо opencode.json

Если `opencode.json` в проекте — симлинк, установка MUST NOT писать по нему и MUST NOT
разыменовывать ссылку. Установка при этом SHALL завершаться успешно.

#### Scenario: opencode.json — симлинк
- **WHEN** `opencode.json` в проекте является симлинком на файл вне проекта
- **THEN** файл, на который ведёт ссылка, не изменяется, а остальные файлы kit-а поставлены
