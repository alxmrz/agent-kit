# shellcheck shell=sh
# Каталог компонентов и профили.
#
# Профиль — текстовый список путей относительно components/.
# Может указывать как на отдельный файл, так и на каталог целиком:
# каталог разворачивается рекурсивно, поэтому новые файлы внутри
# существующего скилла подхватываются без правки списков.

PROFILE_DIR="$KIT_ROOT/components/profiles"
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
list_sources() {
	_profile=$1
	profile_exists "$_profile" || die "неизвестный профиль: $_profile (есть: $(list_profiles | tr '\n' ' '))"
	while IFS= read -r _entry; do
		case "$_entry" in '' | '#'*) continue ;; esac
		_src="$KIT_ROOT/components/$_entry"
		[ -e "$_src" ] || die "профиль $_profile ссылается на отсутствующий компонент: $_entry"
		if [ -d "$_src" ]; then
			find "$_src" -type f | sed "s|^$KIT_ROOT/components/||"
		else
			printf '%s\n' "$_entry"
		fi
	done <"$PROFILE_DIR/$_profile.list" | sort -u
}

# target_path <путь относительно components/> -> путь относительно проекта.
# rules/X.md          -> .agents/rules/alxmrz_kit_X.md
# skills/<id>/...     -> .agents/skills/alxmrz_kit_<id>/...
target_path() {
	case "$1" in
	rules/*)
		_rel=${1#rules/}
		printf '%s\n' ".agents/rules/${PREFIX}_${_rel}"
		;;
	skills/?*)
		_rest=${1#skills/}
		_id=${_rest%%/*}
		_tail=${_rest#*/}
		if [ "$_tail" = "$_rest" ]; then
			printf '%s\n' ".agents/skills/${PREFIX}_${_id}/SKILL.md"
		else
			printf '%s\n' ".agents/skills/${PREFIX}_${_id}/${_tail}"
		fi
		;;
	*)
		die "компонент вне rules/ и skills/: $1"
		;;
	esac
}
