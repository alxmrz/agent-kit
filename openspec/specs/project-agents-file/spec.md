# project-agents-file Specification

## Purpose

Defines how the kit seeds the project's `AGENTS.md` from a template exactly once, leaving an
already existing file untouched forever after.

## Requirements

### Requirement: Создание AGENTS.md из шаблона

Если в корне проекта нет `AGENTS.md`, установка SHALL создать его из шаблона kit-а.

#### Scenario: Файла нет
- **WHEN** установка проходит в проект без `AGENTS.md`
- **THEN** в корне проекта появляется `AGENTS.md` с содержимым шаблона

#### Scenario: Шаблон содержит подстановку команды тестов
- **WHEN** создаётся `AGENTS.md`
- **THEN** в нём нет незаполненных плейсхолдеров вида `{{…}}`

### Requirement: Существующий AGENTS.md не трогается

Файл `AGENTS.md`, который уже есть в проекте, MUST NOT читаться, дополняться или
перезаписываться — ни при первой установке, ни при последующих.

#### Scenario: Свой файл до установки
- **WHEN** в проекте уже есть `AGENTS.md` со своим содержимым
- **THEN** после установки его содержимое побайтово прежнее

#### Scenario: Повторная установка
- **WHEN** `AGENTS.md` был создан kit-ом, а затем отредактирован пользователем, и установка запущена снова
- **THEN** правки пользователя сохраняются

### Requirement: Симлинк вместо AGENTS.md

Симлинк на месте `AGENTS.md` SHALL считаться существующим файлом: установка MUST NOT писать по
нему и MUST NOT разыменовывать ссылку.

#### Scenario: AGENTS.md — симлинк
- **WHEN** `AGENTS.md` в проекте является симлинком
- **THEN** установка завершается успешно, ссылка остаётся на месте, а файл, на который она ведёт, не изменяется
