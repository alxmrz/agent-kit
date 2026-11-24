# shellcheck shell=sh
# Общие помощники. Подключается из install.sh, отдельно не запускается.

PREFIX="alxmrz_kit"
MANIFEST_NAME=".${PREFIX}_manifest.json"

log() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok() { printf '  OK    %s\n' "$*"; }
skip() { printf '  SKIP  %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*" >&2; }
die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# Абсолютный путь к существующему каталогу.
abspath() { (cd "$1" && pwd -P); }

sha256_of() {
	if have sha256sum; then
		sha256sum "$1" | cut -d' ' -f1
	elif have shasum; then
		shasum -a 256 "$1" | cut -d' ' -f1
	elif have openssl; then
		openssl dgst -sha256 "$1" | sed 's/.*= *//'
	else
		die "нужен sha256sum, shasum или openssl"
	fi
}

# Каталог проекта: только он и его подкаталоги. Домашний каталог и корень запрещены.
resolve_project_dir() {
	_dir=$(abspath "$1")
	[ -d "$_dir" ] || die "нет такого каталога: $1"
	case "$_dir" in
	"/") die "отказываюсь работать в корне файловой системы" ;;
	"$HOME") die "kit ставится только внутрь проекта, не в домашний каталог: $_dir" ;;
	esac
	printf '%s\n' "$_dir"
}

# Копирование пишется только внутрь проекта: пути с .. и абсолютные запрещены.
in_project() {
	case "$1" in
	/* | *".."*) die "путь вне проекта запрещён: $1" ;;
	esac
}

has_line() {
	[ -f "$1" ] || return 1
	grep -qxF -- "$2" "$1"
}
