# shellcheck shell=sh
# Манифест установленных файлов: какие пути kit создал и с каким содержимым.
# Формат JSON, но пишется и читается построчно, поэтому парсер не нужен.

manifest_path() { printf '%s\n' "$PROJECT_DIR/.agents/$MANIFEST_NAME"; }

manifest_exists() { [ -f "$(manifest_path)" ]; }

# Печатает "путь<TAB>хеш" для каждой записи манифеста.
manifest_lines() {
	manifest_exists || return 0
	awk -F'"' '/^    "/ { print $2 "\t" $4 }' "$(manifest_path)"
}

# manifest_hash <относительный путь> -> хеш или пустая строка.
manifest_hash() {
	manifest_exists || return 0
	awk -F'"' -v key="$1" '/^    "/ && $2 == key { print $4; exit }' "$(manifest_path)"
}

manifest_field() {
	manifest_exists || return 0
	awk -F'"' -v f="$1" '$0 ~ ("^  \"" f "\":") { print $4; exit }' "$(manifest_path)"
}

# manifest_write <profile> <файл-со-списком-путей> <файл-с-закреплёнными-хешами>
# paths — пути относительно проекта, по одному на строку;
# pinned — строки "путь<TAB>хеш": файлы, которые остались изменёнными
# локально (--keep-modified). Их хеш берётся из этой подсказки, чтобы
# манифест продолжал описывать версию kit-а, а не локальную правку.
# Если ничего не изменилось, файл не перезаписывается: повторный запуск
# не должен давать дифф в git.
manifest_write() {
	_profile=$1
	_targets=$2
	_pinned=$3
	_out=$(manifest_path)
	_commit=$(git -C "$KIT_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
	_now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

	# Дата первой установки сохраняется: это история, а не отметка запуска.
	_installed=$_now
	if manifest_exists; then
		_prev_installed=$(manifest_field installed_at)
		[ -n "$_prev_installed" ] && _installed=$_prev_installed
	fi

	_tmp="$_out.tmp.$$"
	{
		printf '{\n'
		printf '  "generator": "agent-kit",\n'
		printf '  "kit_version": "%s",\n' "$KIT_VERSION"
		printf '  "kit_commit": "%s",\n' "$_commit"
		printf '  "installed_at": "%s",\n' "$_installed"
		printf '  "prefix": "%s",\n' "$PREFIX"
		printf '  "profile": "%s",\n' "$_profile"
		printf '  "files": {\n'
		_first=1
		while IFS= read -r _rel; do
			[ -n "$_rel" ] || continue
			[ "$_first" -eq 1 ] || printf ',\n'
			_first=0
			_pinned_hash=
			if [ -f "$_pinned" ]; then
				_pinned_hash=$(awk -F'\t' -v k="$_rel" '$1 == k { print $2; exit }' "$_pinned")
			fi
			if [ -n "$_pinned_hash" ]; then
				_hash=$_pinned_hash
			else
				_hash=$(sha256_of "$PROJECT_DIR/$_rel")
			fi
			printf '    "%s": "%s"' "$_rel" "$_hash"
		done <"$_targets"
		printf '\n  }\n}\n'
	} >"$_tmp"

	if manifest_exists && cmp -s "$_tmp" "$_out"; then
		rm -f "$_tmp"
		return 1
	fi
	mv "$_tmp" "$_out"
	return 0
}
