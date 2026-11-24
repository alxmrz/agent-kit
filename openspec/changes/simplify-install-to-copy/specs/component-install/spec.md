# Spec Delta

## Purpose

Defines what the kit copies into a target project — which component groups are selected, where
each file lands, and the safety rules that keep the copy inside the project and repeatable.

## ADDED Requirements

### Requirement: Группы компонентов

Ресурсы kit-а SHALL храниться группами: каждая группа — каталог `components/<группа>/` с
подкаталогами `rules/`, `skills/`, `commands/`, `agents/`. Подкаталог MAY отсутствовать.
Группа `base` SHALL ставиться всегда.

#### Scenario: Состав базовой группы
- **WHEN** выполняется установка без флагов выбора групп
- **THEN** в проект попадают все файлы из `components/base/` и ни одного файла из других групп

#### Scenario: Группа без части подкаталогов
- **WHEN** в группе нет каталога `agents/`
- **THEN** установка завершается успешно и просто не ставит агентов

### Requirement: Множественный выбор групп

Языковая специфика SHALL подключаться флагом `--with` со списком групп через запятую. Флаг MAY
указываться несколько раз, выбранные группы объединяются. Без флага SHALL ставиться только `base`.

#### Scenario: Одна группа
- **WHEN** запускается `install --with php`
- **THEN** ставятся файлы `base` и `php`

#### Scenario: Несколько групп и повтор флага
- **WHEN** запускается `install --with php,js --with go`
- **THEN** ставятся файлы `base`, `php`, `js` и `go`

#### Scenario: Неизвестная группа
- **WHEN** в `--with` указана группа, для которой нет каталога в `components/`
- **THEN** установка завершается ошибкой со списком доступных групп, и в проект не записывается ни один файл

#### Scenario: Пробелы в списке групп
- **WHEN** запускается `install --with 'php, js'`
- **THEN** группы `php` и `js` распознаются так же, как без пробела

### Requirement: Раскладка целевых путей

Каждый тип компонента SHALL попадать в свой каталог проекта и получать префикс `alxmrz_kit_`,
чтобы не сталкиваться с одноимёнными файлами проекта.

| Источник | Целевой путь |
| --- | --- |
| `rules/<имя>.md` | `.agents/rules/alxmrz_kit_<имя>.md` |
| `skills/<id>/…` | `.agents/skills/alxmrz_kit_<id>/…` |
| `commands/<имя>.md` | `.opencode/commands/alxmrz_kit_<имя>.md` |
| `agents/<имя>.md` | `.opencode/agents/alxmrz_kit_<имя>.md` |

#### Scenario: Скилл со вспомогательными файлами
- **WHEN** в группе есть `skills/spec-authoring/SKILL.md` и `skills/spec-authoring/references/x.md`
- **THEN** в проекте появляются `.agents/skills/alxmrz_kit_spec-authoring/SKILL.md` и `.agents/skills/alxmrz_kit_spec-authoring/references/x.md`

#### Scenario: Команда и агент
- **WHEN** в группе есть `commands/review.md` и `agents/reviewer.md`
- **THEN** в проекте появляются `.opencode/commands/alxmrz_kit_review.md` и `.opencode/agents/alxmrz_kit_reviewer.md`

### Requirement: Безусловная перезапись файлов kit-а

Файл kit-а на целевом пути SHALL перезаписываться текущей версией без вопросов и без учёта
прежнего содержимого. Локальные правки в файлах с префиксом `alxmrz_kit_` MUST NOT сохраняться
и MUST NOT обнаруживаться.

#### Scenario: Повторная установка после правки файла kit-а
- **WHEN** пользователь изменил `.agents/rules/alxmrz_kit_general_rules.md` и запустил установку снова
- **THEN** файл содержит исходное содержимое из `components/`, а правка исчезает

#### Scenario: Файл без префикса
- **WHEN** в проекте есть `.agents/skills/spec-authoring/SKILL.md`, не созданный kit-ом
- **THEN** установка его не читает и не изменяет, а рядом появляется `.agents/skills/alxmrz_kit_spec-authoring/SKILL.md`

### Requirement: Подстановка ссылок в поставляемых файлах

При копировании ссылки внутри файлов компонентов SHALL переписываться на фактические пути в
проекте, чтобы после установки они оставались рабочими.

#### Scenario: Ссылка на общие правила
- **WHEN** файл группы `php` содержит ссылку `docs/general_rules.md`
- **THEN** в проекте эта ссылка указывает на `.agents/rules/alxmrz_kit_general_rules.md`

#### Scenario: Ссылка на скилл
- **WHEN** файл компонента содержит ссылку `.agents/skills/spec-authoring`
- **THEN** в проекте она указывает на `.agents/skills/alxmrz_kit_spec-authoring`

### Requirement: Границы записи

Установка SHALL писать только внутрь каталога проекта. Домашний каталог и корень файловой
системы MUST быть отвергнуты, а целевой файл-симлинк MUST NOT перезаписываться.

#### Scenario: Домашний каталог
- **WHEN** в качестве проекта указан `$HOME` или `/`
- **THEN** установка завершается ошибкой и ничего не создаёт

#### Scenario: Симлинк на месте целевого файла
- **WHEN** `.agents/rules/alxmrz_kit_general_rules.md` — симлинк на файл вне проекта
- **THEN** установка завершается ошибкой, и файл, на который ведёт ссылка, не изменяется

### Requirement: Идемпотентность установки

Повторный запуск с теми же группами на неизменённом kit-е SHALL давать побайтово те же файлы
проекта: диффа в git нет.

#### Scenario: Второй запуск
- **WHEN** установка запускается второй раз без изменений в kit-е
- **THEN** содержимое всех файлов проекта остаётся прежним

### Requirement: Файл .gitignore

Установка MUST NOT читать или изменять `.gitignore` проекта: клон `bootstrap.sh` удаляется после
установки, поэтому игнорировать нечего.

#### Scenario: В .gitignore нет строки .agent-kit/
- **WHEN** в проекте нет строки `.agent-kit/`
- **THEN** файл не создаётся и не изменяется

#### Scenario: Чужой .gitignore
- **WHEN** в проекте есть свой `.gitignore`
- **THEN** после установки он побайтово прежний

### Requirement: Подсказка о подключении правил

Правила из `.agents/rules/` MUST NOT попадать ни в один конфиг автоматически. Если `AGENTS.md` не
был создан из шаблона, установка SHALL напечатать готовый список путей правил для добавления в
`instructions[]` файла `opencode.json`.

#### Scenario: AGENTS.md уже существовал
- **WHEN** установка прошла в проект, где `AGENTS.md` уже был
- **THEN** вывод содержит пути правил kit-а и указание добавить их в `instructions[]`

#### Scenario: AGENTS.md создан из шаблона
- **WHEN** установка создала `AGENTS.md` из шаблона
- **THEN** подсказка про `instructions[]` не печатается

### Requirement: Пробный запуск

Флаг `--dry-run` SHALL показывать план установки и MUST NOT записывать файлы.

#### Scenario: Пробный запуск на чистом проекте
- **WHEN** установка запускается с `--dry-run` в проекте без файлов kit-а
- **THEN** ни один файл и ни один каталог не создаётся
