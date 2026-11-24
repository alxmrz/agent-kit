# shellcheck shell=sh
# Рендеринг компонентов kit в целевой проект.
#
# Правила и скиллы получают префикс в имени, поэтому не сталкиваются
# с одноимёнными пользовательскими файлами. Ссылки внутри kit-файлов
# приводятся к префиксованным путям, чтобы оставаться рабочими.

# Подстановки путей внутри kit-файлов: исходное имя -> путь в проекте.
rewrite_refs() {
	_file=$1
	_tmp="$_file.tmp.$$"
	sed \
		-e "s|\`docs/php_rules\.md\`|\`.agents/rules/${PREFIX}_php_rules.md\`|g" \
		-e "s|\`docs/general_rules\.md\`|\`.agents/rules/${PREFIX}_general_rules.md\`|g" \
		-e "s|\`php_rules\.md\`|\`.agents/rules/${PREFIX}_php_rules.md\`|g" \
		-e "s|\`general_rules\.md\`|\`.agents/rules/${PREFIX}_general_rules.md\`|g" \
		-e "s|\.agents/skills/spec-authoring|.agents/skills/${PREFIX}_spec-authoring|g" \
		"$_file" >"$_tmp" || {
		rm -f "$_tmp"
		die "не удалось переписать ссылки в $_file"
	}
	mv "$_tmp" "$_file"
}

# Помечает скилл как поставленный kit-ом. name: не трогается (это
# человекочитаемая подпись, ID задаётся каталогом), добавляется только
# metadata с версией. Файл без frontmatter остаётся как есть.
stamp_skill() {
	_file=$1
	[ "$(head -n 1 "$_file")" = "---" ] || return 0
	grep -q '^metadata:' "$_file" && return 0

	_tmp="$_file.tmp.$$"
	awk -v ver="$KIT_VERSION" '
		NR == 1 { print; next }
		/^---$/ {
			print "metadata:"
			print "  alxmrz-kit: \"" ver "\""
			print "---"
			next
		}
		{ print }
	' "$_file" >"$_tmp" && mv "$_tmp" "$_file"
}

# copy_component <путь относительно components/> <путь относительно проекта>
copy_component() {
	_src="$KIT_ROOT/components/$1"
	_dst="$PROJECT_DIR/$2"
	mkdir -p "$(dirname "$_dst")"
	cp "$_src" "$_dst"
	rewrite_refs "$_dst"
	case "$2" in
	.agents/skills/*) stamp_skill "$_dst" ;;
	esac
}
