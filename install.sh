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
		AGENTS_WAS_PRESENT=1
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

# Правила из .agents/rules/ никуда не подключаются автоматически.
# Если AGENTS.md создан из шаблона, он уже ссылается на них; если уже был —
# печатаем готовые пути для instructions[] файла opencode.json.
print_instructions_hint() {
	[ "${AGENTS_WAS_PRESENT:-0}" -eq 1 ] || return 0
	grep '^\.agents/rules/' "$STATE_DIR/targets" >"$STATE_DIR/rules" || return 0
	[ -s "$STATE_DIR/rules" ] || return 0

	log ""
	log "  AGENTS.md уже был — kit его не менял."
	log "  Чтобы агент видел правила kit-а, добавьте пути в instructions[] opencode.json:"
	sed 's|^|          "|; s|$|",|' "$STATE_DIR/rules"
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
	print_instructions_hint

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
AGENTS_WAS_PRESENT=0

parse_args "$@"

cmd_install
