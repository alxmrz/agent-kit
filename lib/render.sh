# shellcheck shell=sh
# Рендеринг компонентов kit в целевой проект.
#
# Правила, скиллы, команды и агенты получают префикс в имени, поэтому не
# сталкиваются с одноимёнными пользовательскими файлами. Ссылки внутри
# kit-файлов приводятся к префиксованным путям, чтобы оставаться рабочими.

# finish_tmp <временный> <целевой>: подменяет файл только если содержимое
# изменилось — иначе у неизменного файла дёргался бы mtime на каждом запуске.
finish_tmp() {
	if cmp -s "$1" "$2"; then
		rm -f "$1"
	else
		mv "$1" "$2"
	fi
}

# rewrite_refs <файл>: исходные имена правил -> префиксованные пути в проекте.
# Временный файл создаётся копией исходного, поэтому права доступа сохраняются
# (scripts/ рядом со SKILL.md бывают исполняемыми).
# Отдельная функция вместо `sed ... || die`: у `A && B || C` C выполнится
# и тогда, когда A успешно, а B вернул ненулевой код.
rewrite_refs() {
	_file=$1
	_tmp="$_file.tmp.$$"
	if ! cp -p "$_file" "$_tmp"; then
		die "не удалось создать временный файл для $_file"
	fi
	: >"$_tmp"
	if ! sed \
		-e "s|docs/php_rules\.md|.agents/rules/${PREFIX}_php_rules.md|g" \
		-e "s|docs/general_rules\.md|.agents/rules/${PREFIX}_general_rules.md|g" \
		-e "s|\(^\|[^/.[:alnum:]_-]\)php_rules\.md|\1.agents/rules/${PREFIX}_php_rules.md|g" \
		-e "s|\(^\|[^/.[:alnum:]_-]\)general_rules\.md|\1.agents/rules/${PREFIX}_general_rules.md|g" \
		-e "s|\.agents/skills/spec-authoring|.agents/skills/${PREFIX}_spec-authoring|g" \
		"$_file" >"$_tmp"; then
		rm -f "$_tmp"
		die "не удалось переписать $_file"
	fi
	finish_tmp "$_tmp" "$_file"
}

# copy_component <путь относительно components/> <путь относительно проекта>
# Пишет через временный файл: mv заменяет симлинк, а не идёт по нему,
# поэтому запись не может уехать за пределы проекта.
copy_component() {
	# Имена с префиксом _cc_: install_file держит свои _src/_dst
	# в той же области видимости.
	_cc_src="$COMPONENTS_DIR/$1"
	_cc_dst="$PROJECT_DIR/$2"
	mkdir -p "$(dirname "$_cc_dst")"
	refuse_symlink "$_cc_dst" "$2"
	_cc_tmp="$_cc_dst.tmp.$$"
	cp -p "$_cc_src" "$_cc_tmp" || {
		rm -f "$_cc_tmp"
		die "не удалось скопировать $1"
	}
	rewrite_refs "$_cc_tmp"
	finish_tmp "$_cc_tmp" "$_cc_dst"
}
