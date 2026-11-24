# shellcheck shell=sh
# Общие помощники. Подключается из install.sh, отдельно не запускается.

# Используется в lib/components.sh и lib/render.sh; при проверке этого файла
# отдельно shellcheck считает переменную неиспользуемой.
# shellcheck disable=SC2034
PREFIX="alxmrz_kit"

log() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok() { printf '  OK    %s\n' "$*"; }
skip() { printf '  SKIP  %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*" >&2; }
die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

# Раскрывает ~ и ~/... в путях, пришедших из аргументов или конфигов.
# Без этого `--dir '~'` попадал в cd как литеральный каталог "~".
expand_tilde() {
	case "$1" in
	"~") printf '%s\n' "${HOME:-/nonexistent}" ;;
	"~"/*)
		# shellcheck disable=SC2088  # это литерал "~/", а не путь для раскрытия
		_rel=${1#"~/"}; printf '%s\n' "${HOME:-/nonexistent}/$_rel"
		;;
	*) printf '%s\n' "$1" ;;
	esac
}

# Абсолютный путь к существующему каталогу.
abspath() {
	[ -d "$1" ] || return 1
	(cd "$1" && pwd -P)
}

# Каталог проекта: только он и его подкаталоги. Домашний каталог и корень запрещены.
resolve_project_dir() {
	_arg=$(expand_tilde "$1")
	_dir=$(abspath "$_arg") || die "нет такого каталога: $1"
	case "$_dir" in
	"/") die "отказываюсь работать в корне файловой системы" ;;
	esac
	# HOME может быть не задан (set -u) или задан со слешем на конце,
	# поэтому сравниваем канонические пути, а не строки.
	_home=${HOME:-}
	if [ -n "$_home" ] && [ -d "$_home" ]; then
		_home=$(abspath "$_home") || _home=
		if [ "$_dir" = "$_home" ]; then
			die "kit ставится только внутрь проекта, не в домашний каталог: $_dir"
		fi
	fi
	printf '%s\n' "$_dir"
}

# Копирование пишется только внутрь проекта: пути с .. и абсолютные запрещены.
in_project() {
	case "$1" in
	/* | *".."*) die "путь вне проекта запрещён: $1" ;;
	esac
}

# Симлинк на месте файла kit-а означает запись в чужое место:
# cp/mv пошли бы по ссылке. Отказываемся, а не перезаписываем.
refuse_symlink() {
	_path=$1
	_label=$2
	if [ -L "$_path" ]; then
		die "$_label: это симлинк; kit не пишет через симлинки (уберите файл вручную)"
	fi
}

has_line() {
	[ -f "$1" ] || return 1
	grep -qxF -- "$2" "$1"
}
