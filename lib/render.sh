# shellcheck shell=sh
# Рендеринг компонентов kit в целевой проект.
#
# Правила и скиллы получают префикс в имени, поэтому не сталкиваются
# с одноимёнными пользовательскими файлами. Ссылки внутри kit-файлов
# приводятся к префиксованным путям, чтобы оставаться рабочими.

# finish_tmp <временный> <целевой>: подменяет файл только если содержимое
# изменилось — иначе у неизменного файла дёргался бы mtime на каждом запуске.
finish_tmp() {
	if cmp -s "$1" "$2"; then
		rm -f "$1"
	else
		mv "$1" "$2"
	fi
}

# render <файл> <режим>: переписывает файл через временный файл.
# Временный создаётся копией исходного, поэтому права доступа сохраняются
# (scripts/ рядом со SKILL.md бывают исполняемыми).
# Режимы:
#   refs    — ссылки kit-файла -> пути в проекте;
#   neutralize — ссылка на PHP-правила -> нейтральная формулировка;
#   stamp   — добавить metadata с версией в frontmatter скилла.
# Отдельная функция вместо `sed ... || die`: у `A && B || C` C выполнится
# и тогда, когда A успешно, а B вернул ненулевой код.
render() {
	_file=$1
	_mode=$2
	_tmp="$_file.tmp.$$"
	if ! cp -p "$_file" "$_tmp"; then
		die "не удалось создать временный файл для $_file"
	fi
	: >"$_tmp"

	case "$_mode" in
	refs)
		sed \
			-e "s|docs/php_rules\.md|.agents/rules/${PREFIX}_php_rules.md|g" \
			-e "s|docs/general_rules\.md|.agents/rules/${PREFIX}_general_rules.md|g" \
			-e "s|\(^\|[^/.[:alnum:]_-]\)php_rules\.md|\1.agents/rules/${PREFIX}_php_rules.md|g" \
			-e "s|\(^\|[^/.[:alnum:]_-]\)general_rules\.md|\1.agents/rules/${PREFIX}_general_rules.md|g" \
			-e "s|\.agents/skills/spec-authoring|.agents/skills/${PREFIX}_spec-authoring|g" \
			"$_file" >"$_tmp" || _fail=1
		;;
	neutralize)
		# shellcheck disable=SC2016  # обратные кавычки — часть текста правила
		sed 's|^Специфика PHP.*$|PHP-специфика подключается профилем `php` (`--profile php`): он добавляет файл `.agents/rules/alxmrz_kit_php_rules.md`.|' \
			"$_file" >"$_tmp" || _fail=1
		;;
	stamp)
		awk -v ver="$KIT_VERSION" '
			NR == 1 { print; next }
			!done && /^---$/ {
				print "metadata:"
				print "  alxmrz-kit: \"" ver "\""
				print "---"
				done = 1
				next
			}
			{ print }
		' "$_file" >"$_tmp" || _fail=1
		;;
	*)
		rm -f "$_tmp"
		die "неизвестный режим рендеринга: $_mode"
		;;
	esac

	if [ "${_fail:-0}" -eq 1 ]; then
		rm -f "$_tmp"
		die "не удалось переписать $_file"
	fi
	finish_tmp "$_tmp" "$_file"
}

# rewrite_refs <файл>: исходные имена правил -> префиксованные пути в проекте.
rewrite_refs() {
	render "$1" refs
}

# apply_profile_rules <файл> <путь в проекте>: ссылка на PHP-правила
# заменяется на нейтральную, если профиль их не ставит. Другие файлы
# не трогаются. Проверяется по targets, а не по факту установки:
# copy_component вызывает это для только что скопированного файла.
apply_profile_rules() {
	[ "$2" = ".agents/rules/${PREFIX}_general_rules.md" ] || return 0
	grep -qxF ".agents/rules/${PREFIX}_php_rules.md" "$STATE_DIR/targets" && return 0
	render "$1" neutralize
}

# stamp_skill <файл>: помечает скилл как поставленный kit-ом. name:
# не трогается (это человекочитаемая подпись, ID задаётся каталогом),
# добавляется только metadata с версией. Правится только первый
# frontmatter-блок: `---` в теле скилла — горизонтальная линейка.
stamp_skill() {
	[ "$(head -n 1 "$1")" = "---" ] || return 0
	grep -q '^metadata:' "$1" && return 0
	render "$1" stamp
}

# copy_component <путь относительно components/> <путь относительно проекта>
# Пишет через временный файл: mv заменяет симлинк, а не идёт по нему,
# поэтому запись не может уехать за пределы проекта.
copy_component() {
	# Имена с префиксом _cc_: install_file и install_components держат
	# свои _src/_dst в той же области видимости.
	_cc_src="$KIT_ROOT/components/$1"
	_cc_dst="$PROJECT_DIR/$2"
	mkdir -p "$(dirname "$_cc_dst")"
	refuse_symlink "$_cc_dst" "$2"
	_cc_tmp="$_cc_dst.tmp.$$"
	cp -p "$_cc_src" "$_cc_tmp" || {
		rm -f "$_cc_tmp"
		die "не удалось скопировать $1"
	}
	rewrite_refs "$_cc_tmp"
	case "$2" in
	.agents/skills/*) stamp_skill "$_cc_tmp" ;;
	esac
	apply_profile_rules "$_cc_tmp" "$2"
	finish_tmp "$_cc_tmp" "$_cc_dst"
}
