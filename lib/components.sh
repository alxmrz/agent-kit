# shellcheck shell=sh
# Каталог компонентов и профили.
#
# Профиль — текстовый список путей относительно components/.
# Может указывать как на отдельный файл, так и на каталог целиком:
# каталог разворачивается рекурсивно, поэтому новые файлы внутри
# существующего скилла подхватываются без правки списков.

PROFILE_DIR="$KIT_ROOT/components/profiles"
# Используется в install.sh; при проверке этого файла отдельно shellcheck
# считает переменную неиспользуемой.
# shellcheck disable=SC2034
DEFAULT_PROFILE="base"

list_profiles() {
	[ -d "$PROFILE_DIR" ] || die "нет каталога профилей: $PROFILE_DIR"
	for _p in "$PROFILE_DIR"/*.list; do
		[ -e "$_p" ] || continue
		basename "$_p" .list
	done
}

profile_exists() { [ -f "$PROFILE_DIR/$1.list" ]; }

# list_sources <профиль>: пути источников относительно components/, без повторов.
# Список собирается в файл, а не через пайп: ошибка (die) обязана прервать
# установку, а не умереть в подшелле sort-а вместе с половиной файлов.
list_sources() {
	_profile=$1
	profile_exists "$_profile" || die "неизвестный профиль: $_profile (есть: $(list_profiles | tr '\n' ' '))"
	[ -n "${STATE_DIR:-}" ] || die "внутренняя ошибка: STATE_DIR не задан"
	_raw="$STATE_DIR/sources.raw"
	: >"$_raw"
	while IFS= read -r _entry; do
		case "$_entry" in '' | '#'*) continue ;; esac
		_src="$KIT_ROOT/components/$_entry"
		[ -e "$_src" ] || die "профиль $_profile ссылается на отсутствующий компонент: $_entry"
		if [ -d "$_src" ]; then
			find "$_src" -type f >"$_raw.files" || die "не удалось прочитать $_src"
			while IFS= read -r _file; do
				printf '%s\n' "${_file#"$KIT_ROOT/components/"}" >>"$_raw"
			done <"$_raw.files"
			rm -f "$_raw.files"
		else
			printf '%s\n' "$_entry" >>"$_raw"
		fi
	done <"$PROFILE_DIR/$_profile.list"
	sort -u "$_raw"
}

# target_path <путь относительно components/> -> путь относительно проекта.
# rules/X.md          -> .agents/rules/alxmrz_kit_X.md
# skills/<id>/...     -> .agents/skills/alxmrz_kit_<id>/...
# skills/<id>.md      -> .agents/skills/alxmrz_kit_<id>.md
target_path() {
	case "$1" in
	rules/*)
		_rel=${1#rules/}
		printf '%s\n' ".agents/rules/${PREFIX}_${_rel}"
		;;
	skills/?*/*)
		_rest=${1#skills/}
		_id=${_rest%%/*}
		_tail=${_rest#*/}
		printf '%s\n' ".agents/skills/${PREFIX}_${_id}/${_tail}"
		;;
	skills/?*)
		_rest=${1#skills/}
		printf '%s\n' ".agents/skills/${PREFIX}_${_rest}"
		;;
	*)
		die "компонент вне rules/ и skills/: $1"
		;;
	esac
}
