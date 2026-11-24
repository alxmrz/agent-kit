# shellcheck shell=sh
# Группы компонентов и раскладка целевых путей.
#
# Группа — каталог components/<группа>/ с подкаталогами rules/, skills/,
# commands/, agents/. Подкаталог может отсутствовать. Группа base ставится
# всегда, языковые подключаются флагом --with.
#
# Новый файл внутри подкаталога группы подхватывается без правки скрипта:
# список источников даёт find, а не отдельный список.

COMPONENTS_DIR="$KIT_ROOT/components"
# Используется в install.sh; при проверке этого файла отдельно shellcheck
# считает переменную неиспользуемой.
# shellcheck disable=SC2034
BASE_GROUP="base"

# Все группы: имена каталогов в components/, по алфавиту.
list_groups() {
	for _dir in "$COMPONENTS_DIR"/*/; do
		[ -d "$_dir" ] || continue
		basename "$_dir"
	done
}

# Список групп одной строкой через пробел — для сообщений и --help.
group_names() {
	list_groups | tr '\n' ' ' | sed 's/ $//'
}

group_exists() { [ -d "$COMPONENTS_DIR/$1" ]; }

# list_sources <файл со списком групп>: пути источников относительно components/.
# Список собирается в файл, а не через пайп: ошибка (die) обязана прервать
# установку, а не умереть в подшелле sort-а вместе с половиной файлов.
list_sources() {
	_groups=$1
	[ -f "$_groups" ] || die "внутренняя ошибка: список групп не найден"
	[ -n "${STATE_DIR:-}" ] || die "внутренняя ошибка: STATE_DIR не задан"
	_raw="$STATE_DIR/sources.raw"
	: >"$_raw"
	while IFS= read -r _group; do
		[ -n "$_group" ] || continue
		_src="$COMPONENTS_DIR/$_group"
		group_exists "$_group" ||
			die "нет группы: $_group (есть: $(group_names))"
		find "$_src" -type f >"$_raw.files" || die "не удалось прочитать $_src"
		while IFS= read -r _file; do
			_rel=${_file#"$COMPONENTS_DIR/"}
			# Служебные файлы каталога (.gitkeep и т. п.) не компоненты.
			case "${_rel##*/}" in .*) continue ;; esac
			printf '%s\n' "$_rel" >>"$_raw"
		done <"$_raw.files"
		rm -f "$_raw.files"
	done <"$_groups"
	sort -u "$_raw"
}

# target_path <путь относительно components/> -> путь относительно проекта.
# <группа>/rules/<имя>.md       -> .agents/rules/alxmrz_kit_<имя>.md
# <группа>/skills/<id>/...      -> .agents/skills/alxmrz_kit_<id>/...
# <группа>/commands/<имя>.md    -> .opencode/commands/alxmrz_kit_<имя>.md
# <группа>/agents/<имя>.md      -> .opencode/agents/alxmrz_kit_<имя>.md
#
# rules/, commands/ и agents/ — плоские каталоги файлов: вложенность там
# становится частью имени команды/агента, поэтому это ошибка компонента.
target_path() {
	_rest=${1#*/}
	_type=${_rest%%/*}
	_tail=${_rest#*/}
	case "$_type" in
	rules | commands | agents)
		case "$_tail" in
		*/*) die "компонент $_type/ должен быть плоским (без подкаталогов): $1" ;;
		esac
		case "$_type" in
		rules) _dir=".agents/rules" ;;
		commands) _dir=".opencode/commands" ;;
		agents) _dir=".opencode/agents" ;;
		esac
		printf '%s\n' "$_dir/${PREFIX}_${_tail}"
		;;
	skills)
		case "$_tail" in
		*/*)
			_id=${_tail%%/*}
			_rest=${_tail#*/}
			printf '%s\n' ".agents/skills/${PREFIX}_${_id}/${_rest}"
			;;
		*) printf '%s\n' ".agents/skills/${PREFIX}_${_tail}" ;;
		esac
		;;
	*)
		die "компонент вне rules/, skills/, commands/ и agents/: $1"
		;;
	esac
}
