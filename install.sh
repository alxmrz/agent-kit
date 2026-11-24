#!/bin/sh
# agent-kit: шаблонные файлы для работы с ИИ внутри проекта.
#
#   ./install.sh [install] [флаги]   поставить или обновить файлы kit-а
#
# Файлы создаются только внутри проекта. Домашний каталог и глобальные
# настройки агентов не читаются и не изменяются.

set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
KIT_ROOT=$SELF_DIR
KIT_VERSION=$(tr -d ' \n' <"$KIT_ROOT/VERSION")

STATE_DIR=
PROJECT_DIR=

# shellcheck source=lib/common.sh
. "$KIT_ROOT/lib/common.sh"
# shellcheck source=lib/components.sh
. "$KIT_ROOT/lib/components.sh"
# shellcheck source=lib/render.sh
. "$KIT_ROOT/lib/render.sh"

# Выбранные языковые группы, по одной в строке. base добавляется всегда.
GROUPS_FILE=
DRY_RUN=0

cleanup() {
	if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ]; then
		rm -rf "$STATE_DIR"
	fi
}

# Прерывание должно завершать работу, а не продолжать её с полупустым
# STATE_DIR: в dash после trap на INT скрипт идёт дальше.
interrupted() {
	cleanup
	trap - EXIT HUP INT TERM
	exit 130
}

trap cleanup EXIT
trap interrupted HUP INT TERM

usage() {
	cat <<EOF
agent-kit $KIT_VERSION

Использование:
  ./install.sh [install] [флаги]   поставить или обновить файлы kit-а

Флаги:
  --dir <каталог>      целевой проект (по умолчанию текущий каталог)
  --with <группы>      дополнительные группы через запятую, можно повторять
                       (группа base ставится всегда; доступны: $(group_names))
  --dry-run            показать план, ничего не записывая
  -h, --help           эта справка

Что появляется в проекте:
  .agents/rules/${PREFIX}_<имя>.md
  .agents/skills/${PREFIX}_<id>/
  .opencode/commands/${PREFIX}_<имя>.md
  .opencode/agents/${PREFIX}_<имя>.md
  AGENTS.md              (только если его ещё нет)
  opencode.json          (instructions[] с правилами base и выбранных групп)
EOF
}

# --- аргументы --------------------------------------------------------------

# <значение --with>: режется по запятым и пробелам, пустые куски пропускаются.
# Пайплайн пишет в файл, а не в переменную, поэтому подоболочка не мешает.
append_groups() {
	printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
		while IFS= read -r _item; do
			[ -n "$_item" ] || continue
			printf '%s\n' "$_item" >>"$GROUPS_FILE"
		done
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		install)
			;;
		--dir)
			[ $# -ge 2 ] || die "--dir требует значение"
			PROJECT_DIR=$2
			shift
			;;
		--with)
			[ $# -ge 2 ] || die "--with требует значение"
			append_groups "$2"
			shift
			;;
		--dry-run) DRY_RUN=1 ;;
		-h | --help)
			usage
			exit 0
			;;
		-*)
			die "неизвестный флаг: $1 (см. --help)"
			;;
		*)
			if [ -z "$PROJECT_DIR" ]; then
				PROJECT_DIR=$1
			else
				die "лишний аргумент: $1"
			fi
			;;
		esac
		shift
	done
}

# Проверка выбора групп до первой записи: неизвестная группа не должна
# оставить в проекте половину файлов.
validate_groups() {
	sort -u "$GROUPS_FILE" >"$STATE_DIR/groups.unique"
	while IFS= read -r _group; do
		[ -n "$_group" ] || continue
		group_exists "$_group" ||
			die "неизвестная группа: $_group (есть: $(group_names))"
	done <"$STATE_DIR/groups.unique"

	{
		printf '%s\n' "$BASE_GROUP"
		cat "$STATE_DIR/groups.unique"
	} | sort -u >"$STATE_DIR/groups"
}

# --- установка --------------------------------------------------------------

# install_file <путь в проекте> <путь источника в components/>
# Перезапись безусловная: содержимое всегда берётся из components/.
install_file() {
	_dst="$PROJECT_DIR/$1"

	if [ "$DRY_RUN" -eq 1 ]; then
		if [ -L "$_dst" ]; then
			warn "$1 (план: это симлинк, установка откажется писать)"
		elif [ -f "$_dst" ]; then
			ok "$1 (план: перезаписать)"
		else
			ok "$1 (план)"
		fi
		return 0
	fi

	refuse_symlink "$_dst" "$1"
	_was=0
	if [ -f "$_dst" ]; then
		_was=1
	fi
	copy_component "$2" "$1"
	if [ "$_was" -eq 1 ]; then
		ok "$1 (перезаписан)"
	else
		ok "$1"
	fi
}

install_components() {
	step "Компоненты (группы: $(tr '\n' ' ' <"$STATE_DIR/groups" | sed 's/ $//'))"

	list_sources "$STATE_DIR/groups" >"$STATE_DIR/sources"
	while IFS= read -r _src; do
		[ -n "$_src" ] || continue
		_rel=$(target_path "$_src")
		in_project "$_rel"
		printf '%s\n' "$_rel" >>"$STATE_DIR/targets"
		install_file "$_rel" "$_src"
	done <"$STATE_DIR/sources"
}

install_agents_md() {
	step "AGENTS.md"
	_dst="$PROJECT_DIR/AGENTS.md"

	if [ -e "$_dst" ] || [ -L "$_dst" ]; then
		skip "AGENTS.md (уже есть; kit его не перезаписывает)"
		return 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		ok "AGENTS.md (план: создать из шаблона)"
		return 0
	fi

	sed 's|{{TEST_CMD}}|команда запуска тестов|g' \
		"$KIT_ROOT/snippets/AGENTS.md.tmpl" >"$STATE_DIR/AGENTS.md"
	mv "$STATE_DIR/AGENTS.md" "$_dst"
	ok "AGENTS.md (создан из шаблона)"
	warn "AGENTS.md: заполните разделы TODO — дальше kit его не трогает"
}

# Пути поставленных правил в виде, пригодном для instructions[]:
# base и все выбранные языковые группы попадают сюда, потому что их файлы
# лежат в .agents/rules/ (см. target_path).
instructions_list() {
	sed -n 's|^\.agents/rules/|./.agents/rules/|p' "$STATE_DIR/targets"
}

# print_instructions_hint: пути правил для ручного добавления в opencode.json.
print_instructions_hint() {
	log "        Добавьте в instructions[] opencode.json:"
	sed 's|^|          "|; s|$|",|' "$STATE_DIR/instructions"
}

# opencode.json: в instructions[] добавляются правила base и выбранных групп.
# Чужое содержимое и форматирование сохраняются (см. lib/merge.py). Без
# python3 файл не правится — печатаются пути для ручной вставки. opencode.jsonc
# не трогаем: комментарии JSONC ломают разбор.
install_opencode_json() {
	step "opencode.json"
	instructions_list >"$STATE_DIR/instructions"
	if [ ! -s "$STATE_DIR/instructions" ]; then
		skip "opencode.json (правил нет)"
		return 0
	fi

	# JSONC не правим: комментарии ломают разбор, а два конфига рядом
	# сделали бы правку `opencode.json` бесполезной.
	if [ -e "$PROJECT_DIR/opencode.jsonc" ]; then
		skip "opencode.jsonc: комментарии не дают править файл автоматически"
		print_instructions_hint
		return 0
	fi

	if ! have python3; then
		warn "python3 не найден: opencode.json не изменён"
		print_instructions_hint
		return 0
	fi

	# Симлинк — чужое место: не пишем по нему. Это не ошибка установки:
	# остальные файлы kit-а уже поставлены.
	if [ -L "$PROJECT_DIR/opencode.json" ]; then
		skip "opencode.json (симлинк; не трогаем)"
		print_instructions_hint
		return 0
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		if [ -f "$PROJECT_DIR/opencode.json" ]; then
			ok "opencode.json (план: дополнить instructions[])"
		else
			ok "opencode.json (план: создать с instructions[])"
		fi
		return 0
	fi

	if python3 "$KIT_ROOT/lib/merge.py" json "$PROJECT_DIR/opencode.json" \
		"$STATE_DIR/instructions" >"$STATE_DIR/merge.out" 2>&1; then
		sed 's/^/        /' "$STATE_DIR/merge.out"
		ok "opencode.json (instructions[] актуален)"
	else
		warn "opencode.json: слияние не удалось, файл не изменён"
		print_instructions_hint
	fi
}

cmd_install() {
	PROJECT_DIR=$(resolve_project_dir "${PROJECT_DIR:-.}")
	step "agent-kit $KIT_VERSION -> $PROJECT_DIR"
	if [ "$DRY_RUN" -eq 1 ]; then
		log "  режим: dry-run, изменения не записываются"
	fi

	validate_groups
	: >"$STATE_DIR/targets"

	install_components
	install_agents_md
	install_opencode_json

	step "Готово"
	if [ "${AGENT_KIT_EPHEMERAL:-0}" -eq 1 ]; then
		# Клона, из которого запускался install.sh, в проекте уже нет: обновление
		# снова идёт через bootstrap.sh, а не через локальный install.sh.
		log "  Обновить:  снова запустить bootstrap.sh с теми же флагами"
	else
		log "  Обновить:  $KIT_ROOT/install.sh --dir \"$PROJECT_DIR\""
	fi
	if [ ! -d "$PROJECT_DIR/openspec" ]; then
		log "  OpenSpec:  openspec init . --tools opencode"
	fi
}

# --- main -------------------------------------------------------------------

STATE_DIR=$(mktemp -d) || die "не удалось создать временный каталог"
GROUPS_FILE="$STATE_DIR/groups.raw"
: >"$GROUPS_FILE"

parse_args "$@"

cmd_install
