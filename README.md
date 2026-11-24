# agent-kit

Шаблонные файлы для работы с ИИ-агентом в проекте: правила кода, скиллы и
заготовка `AGENTS.md`. Ставится внутрь проекта, ничего глобального не трогает.

Каждый файл получает префикс `alxmrz_kit_`, поэтому не сталкивается с вашими
одноимёнными правилами и скиллами.

## Установка в новый проект

```sh
curl -fsSL https://raw.githubusercontent.com/alxmrz/agent-kit/main/bootstrap.sh | sh
```

Команда клонирует kit в `./.agent-kit/` (добавляется в `.gitignore`) и запускает
установку. Повторный запуск обновляет клон и перегенерирует файлы:

```sh
./.agent-kit/install.sh              # обновить
./.agent-kit/install.sh --dry-run    # показать план
./.agent-kit/install.sh status       # что стоит и что разошлось
```

Без сети:

```sh
./.agent-kit/install.sh --offline
```

## Что появляется в проекте

| Путь | Назначение |
| --- | --- |
| `.agents/rules/alxmrz_kit_general_rules.md` | общие правила написания кода |
| `.agents/rules/alxmrz_kit_php_rules.md` | PHP-специфика (профиль `php`) |
| `.agents/skills/alxmrz_kit_conventional-commit/` | скилл коммитов |
| `.agents/skills/alxmrz_kit_spec-authoring/` | скилл спек и дизайна |
| `.agents/.alxmrz_kit_manifest.json` | версия и хеши поставленных файлов |
| `opencode.json` | дополняется `instructions[]` |
| `AGENTS.md` | создаётся один раз, если его нет |
| `openspec/config.yaml` | дополняется `rules`, если openspec уже инициализирован |
| `.gitignore` | добавляется `.agent-kit/` |

## Гарантии

- **Только проект.** Домашний каталог и корень файловой системы отвергаются,
  глобальные `~/.agents` и `~/.config/opencode` не читаются и не изменяются.
- **Чужие файлы неприкосновенны.** Всё, что не имеет префикса `alxmrz_kit_`,
  не читается и не перезаписывается.
- **Повторный запуск идемпотентен.** Если kit не менялся, диффа в git не будет.
- **Локальные правки видны.** `status` показывает `DRIFT`; обычный запуск
  перезаписывает файл с предупреждением, `--keep-modified` оставляет правку.

## Флаги

| Флаг | Действие |
| --- | --- |
| `--dir <каталог>` | целевой проект (по умолчанию текущий) |
| `--profile <имя>` | набор компонентов: `base` (по умолчанию) или `php` |
| `--dry-run` | показать план, ничего не записывая |
| `--keep-modified` | не перезаписывать локально изменённые файлы |
| `--no-agents` | не создавать `AGENTS.md` |
| `--no-openspec` | не дописывать правила в `openspec/config.yaml` |

## Переменные окружения

`bootstrap.sh` понимает `AGENT_KIT_REPO`, `AGENT_KIT_REF` и `AGENT_KIT_DIR` —
удобно для форка или проверки ветки.

## Состав репозитория

```
bootstrap.sh              точка входа: clone -> install.sh
install.sh                установка, status, adopt
lib/                      общие функции, манифест, слияния (python3)
components/rules/         исходные правила
components/skills/        исходные скиллы
components/profiles/      списки компонентов по профилям
snippets/                 шаблон AGENTS.md и правила для openspec
tests/smoke.sh            автопроверка на одноразовых каталогах
```

## Требования

`sh`, `git`, `sha256sum` (или `shasum`/`openssl`), `python3` для слияния
`opencode.json` и `openspec/config.yaml` (без него печатается готовый сниппет).

## Развитие kit-а

Компоненты забираются из проекта-источника:

```sh
./install.sh adopt /путь/к/проекту
```

После `adopt` проверьте ссылки внутри `components/` и запустите `tests/smoke.sh`.

OpenSpec-скиллы (`openspec-*`) намеренно не входят в kit: их создаёт
`openspec init`.
