#!/bin/sh
# agent-kit: шаблонные файлы для работы с ИИ внутри проекта.
#
#   ./install.sh [install] [флаги]   поставить или обновить файлы kit-а
#   ./install.sh status              показать, что стоит и что разошлось
#   ./install.sh uninstall           убрать файлы kit-а из проекта
#   ./install.sh adopt <каталог>     забрать компоненты в этот репозиторий
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
# shellcheck source=lib/manifest.sh
. "$KIT_ROOT/lib/manifest.sh"
# shellcheck source=lib/render.sh
. "$KIT_ROOT/lib/render.sh"

PROFILE=$DEFAULT_PROFILE
DRY_RUN=0
KEEP_MODIFIED=0
NO_AGENTS=0
NO_OPENSPEC=0
FORCE=0

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
  ./install.sh status [каталог]    показать состояние установки
  ./install.sh uninstall [флаги]   убрать файлы kit-а из проекта
  ./install.sh adopt <каталог>     забрать компоненты в этот репозиторий

Флаги:
  --dir <каталог>      целевой проект (по умолчанию текущий каталог)
  --profile <имя>      профиль компонентов (по умолчанию $DEFAULT_PROFILE;
                       доступны: $(list_profiles | tr '\n' ' '))
  --dry-run            показать план, ничего не записывая
  --keep-modified      не перезаписывать локально изменённые kit-файлы
  --force              uninstall/смена профиля: удалить и локально изменённые файлы
  --no-agents          не создавать AGENTS.md
  --no-openspec        не дописывать правила в openspec/config.yaml
  --offline            не обновлять клон kit-а (для bootstrap.sh)
  -h, --help           эта справка

Что появляется в проекте:
  .agents/rules/${PREFIX}_<имя>.md
  .agents/skills/${PREFIX}_<id>/
  .agents/$MANIFEST_NAME
  opencode.json          (дополняется instructions[])
  AGENTS.md              (только если его ещё нет)
  openspec/config.yaml   (дополняется rules, если openspec уже есть)
  .gitignore             (добавляется .agent-kit/)
EOF
}

# --- аргументы --------------------------------------------------------------

COMMAND=
ADOPT_SRC=

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		install | status | uninstall | adopt)
			COMMAND=$1
			;;
		--dir)
			[ $# -ge 2 ] || die "--dir требует значение"
			PROJECT_DIR=$2
			shift
			;;
		--profile)
			[ $# -ge 2 ] || die "--profile требует значение"
			PROFILE=$2
			shift
			;;
		--dry-run) DRY_RUN=1 ;;
		--keep-modified) KEEP_MODIFIED=1 ;;
		--force) FORCE=1 ;;
		--no-agents) NO_AGENTS=1 ;;
		--no-openspec) NO_OPENSPEC=1 ;;
		--offline)
			# install.sh в сеть не ходит: флаг осмыслен только для bootstrap.sh,
			# здесь принимается, чтобы команда была одинаковой.
			;;
		-h | --help)
			usage
			exit 0
			;;
		-*)
			die "неизвестный флаг: $1 (см. --help)"
			;;
		*)
			if [ "$COMMAND" = "adopt" ] && [ -z "$ADOPT_SRC" ]; then
				ADOPT_SRC=$1
			elif [ -z "$PROJECT_DIR" ]; then
				PROJECT_DIR=$1
			else
				die "лишний аргумент: $1"
			fi
			;;
		esac
		shift
	done
	if [ -z "$COMMAND" ]; then
		COMMAND=install
	fi
}

# --- установка --------------------------------------------------------------

# install_file <путь в проекте> <путь источника в components/>
install_file() {
	_dst="$PROJECT_DIR/$1"
	_prev=$(manifest_hash "$1")
	_before=
	if [ -f "$_dst" ]; then
		_before=$(sha256_of "$_dst")
	fi

	# Локальная правка = файл числится в манифесте, но содержимое разошлось.
	_local_edit=0
	if [ -n "$_before" ] && [ -n "$_prev" ] && [ "$_before" != "$_prev" ]; then
		_local_edit=1
	fi

	if [ "$_local_edit" -eq 1 ] && [ "$KEEP_MODIFIED" -eq 1 ]; then
		skip "$1 (изменён локально, оставлен)"
		# Манифест сохраняет прежний хеш kit-а, иначе дрифт «забудется»
		# и следующая обычная установка молча затёрла бы правку.
		printf '%s\t%s\n' "$1" "$_prev" >>"$STATE_DIR/pinned"
		return 0
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		if [ -L "$_dst" ]; then
			warn "$1 (план: это симлинк, установка откажется писать)"
		elif [ "$_local_edit" -eq 1 ]; then
			ok "$1 (план: локальные правки будут перезаписаны)"
		elif [ -n "$_before" ] && [ -z "$_prev" ]; then
			ok "$1 (план: чужой файл будет перезаписан)"
		else
			ok "$1 (план)"
		fi
		return 0
	fi

	refuse_symlink "$_dst" "$1"

	copy_component "$2" "$1"
	if [ "$_local_edit" -eq 1 ]; then
		warn "$1: локальные правки перезаписаны (--keep-modified сохраняет их)"
	elif [ -n "$_before" ] && [ -z "$_prev" ]; then
		warn "$1: файл был, но не числился в манифесте — перезаписан"
	fi
	ok "$1"
}

install_components() {
	step "Компоненты (профиль: $PROFILE)"
	: >"$STATE_DIR/targets"
	: >"$STATE_DIR/pinned"

	list_sources "$PROFILE" >"$STATE_DIR/sources"

	# Сначала полный список целевых путей: он нужен copy_component, чтобы
	# знать, ставит ли профиль PHP-правила, ещё до их установки.
	while IFS= read -r _src; do
		_rel=$(target_path "$_src")
		in_project "$_rel"
		printf '%s\n' "$_rel" >>"$STATE_DIR/targets"
	done <"$STATE_DIR/sources"

	while IFS= read -r _src; do
		install_file "$(target_path "$_src")" "$_src"
	done <"$STATE_DIR/sources"
}

# Пути, которые kit ставил раньше, но текущий профиль их не содержит:
# иначе после --profile php -> base остаётся осиротевший php_rules.md,
# который никто больше не обновляет.
removed_targets() {
	manifest_lines | cut -f1 | sort -u >"$STATE_DIR/old_targets"
	sort -u "$STATE_DIR/targets" >"$STATE_DIR/new_targets"
	comm -23 "$STATE_DIR/old_targets" "$STATE_DIR/new_targets"
}

prune_components() {
	removed_targets >"$STATE_DIR/removed"
	[ -s "$STATE_DIR/removed" ] || return 0

	step "Очистка профиля"
	_pruned=0
	while IFS= read -r _rel; do
		[ -n "$_rel" ] || continue
		_dst="$PROJECT_DIR/$_rel"
		if [ ! -e "$_dst" ] && [ ! -L "$_dst" ]; then
			continue
		fi
		# Локальную правку не выбрасываем молча: только --force.
		if [ "$FORCE" -eq 0 ] && [ ! -L "$_dst" ] &&
			[ "$(sha256_of "$_dst")" != "$(manifest_hash "$_rel")" ]; then
			warn "$_rel: изменён локально, оставлен (--force удалит)"
			# Файл остаётся — значит, он должен остаться и в манифесте,
			# и в instructions[]: иначе он превратится в неуправляемый мусор.
			printf '%s\n' "$_rel" >>"$STATE_DIR/targets"
			printf '%s\t%s\n' "$_rel" "$(manifest_hash "$_rel")" >>"$STATE_DIR/pinned"
			_pruned=$((_pruned + 1))
			continue
		fi
		if [ "$DRY_RUN" -eq 1 ]; then
			ok "$_rel (план: удалить, профиль его больше не ставит)"
			_pruned=$((_pruned + 1))
			continue
		fi
		rm -f "$_dst"
		prune_empty_dirs "$(dirname "$_dst")"
		ok "$_rel (удалён: профиль его больше не ставит)"
		_pruned=$((_pruned + 1))
	done <"$STATE_DIR/removed"

	if [ "$_pruned" -eq 0 ]; then
		skip "лишних файлов нет"
	fi
}

install_agents_md() {
	step "AGENTS.md"
	_dst="$PROJECT_DIR/AGENTS.md"

	if [ "$NO_AGENTS" -eq 1 ]; then
		skip "AGENTS.md (--no-agents)"
		return 0
	fi
	if [ -e "$_dst" ] || [ -L "$_dst" ]; then
		skip "AGENTS.md (уже есть; kit его не перезаписывает)"
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

# Ссылки на правила, которые ставит kit: они попадают в instructions[].
instructions_list() {
	sed -n 's|^\.agents/rules/|./.agents/rules/|p' "$STATE_DIR/targets"
}

# Ссылки kit-а в instructions[], которых больше нет в целевом списке.
obsolete_instructions() {
	manifest_lines | cut -f1 | grep -E '^\.agents/rules/' |
		sed 's|^|./|' | sort -u >"$STATE_DIR/old_instructions"
	instructions_list | sort -u >"$STATE_DIR/new_instructions"
	comm -23 "$STATE_DIR/old_instructions" "$STATE_DIR/new_instructions"
}

install_opencode_json() {
	step "opencode.json"

	if [ -f "$PROJECT_DIR/opencode.jsonc" ]; then
		skip "opencode.jsonc: автоматическое слияние не делается (комментарии)"
		log "        Добавьте в instructions[] вручную:"
		instructions_list | sed 's|^|          "|; s|$|",|'
		return 0
	fi

	if ! have python3; then
		warn "python3 не найден: instructions[] не обновлён, добавьте вручную:"
		instructions_list | sed 's|^|          "|; s|$|",|'
		return 0
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		ok "opencode.json (план: дополнить instructions[])"
		return 0
	fi

	refuse_symlink "$PROJECT_DIR/opencode.json" "opencode.json"
	instructions_list >"$STATE_DIR/instructions"
	obsolete_instructions >"$STATE_DIR/instructions.remove"

	if python3 "$KIT_ROOT/lib/merge.py" json "$PROJECT_DIR/opencode.json" \
		"$STATE_DIR/instructions" "$STATE_DIR/instructions.remove" >"$STATE_DIR/merge.out" 2>&1; then
		sed 's/^/        /' "$STATE_DIR/merge.out"
		ok "opencode.json (instructions[] актуален)"
	else
		warn "opencode.json: слияние не удалось, добавьте вручную:"
		instructions_list | sed 's|^|          "|; s|$|",|'
	fi
}

install_openspec_rules() {
	step "openspec/config.yaml"
	_cfg="$PROJECT_DIR/openspec/config.yaml"

	if [ "$NO_OPENSPEC" -eq 1 ]; then
		skip "openspec/config.yaml (--no-openspec)"
		return 0
	fi
	if [ ! -f "$_cfg" ]; then
		skip "openspec в проекте не инициализирован (нет openspec/config.yaml)"
		return 0
	fi
	if ! have python3; then
		warn "python3 не найден: правила openspec не обновлены"
		return 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		ok "openspec/config.yaml (план: обновить правила с маркером [alxmrz_kit])"
		return 0
	fi

	refuse_symlink "$_cfg" "openspec/config.yaml"

	if python3 "$KIT_ROOT/lib/merge.py" yaml "$_cfg" \
		"$KIT_ROOT/snippets/openspec.rules.tsv" >"$STATE_DIR/merge.out" 2>&1; then
		sed 's/^/        /' "$STATE_DIR/merge.out"
		ok "openspec/config.yaml (правила kit-а обновлены)"
	else
		warn "openspec/config.yaml: слияние не удалось, правила не изменены"
		warn "        (нестандартная разметка rules — поправьте вручную по сниппету snippets/openspec.rules.tsv)"
	fi
}

install_gitignore() {
	step ".gitignore"
	_gi="$PROJECT_DIR/.gitignore"

	if has_line "$_gi" ".agent-kit/"; then
		skip ".gitignore (.agent-kit/ уже игнорируется)"
		return 0
	fi
	refuse_symlink "$_gi" ".gitignore"
	if [ "$DRY_RUN" -eq 1 ]; then
		ok ".gitignore (план: добавить .agent-kit/)"
		return 0
	fi

	{
		if [ -s "$_gi" ] && [ -n "$(tail -c 1 "$_gi")" ]; then
			printf '\n'
		fi
		printf '.agent-kit/\n'
	} >"$STATE_DIR/gitignore.append"
	cat "$STATE_DIR/gitignore.append" >>"$_gi"
	ok ".gitignore (.agent-kit/ добавлен)"
}

write_manifest() {
	if [ "$DRY_RUN" -eq 1 ]; then
		return 0
	fi
	if manifest_write "$PROFILE" "$STATE_DIR/targets" "$STATE_DIR/pinned"; then
		ok ".agents/$MANIFEST_NAME"
	else
		skip ".agents/$MANIFEST_NAME (без изменений)"
	fi
}

cmd_install() {
	PROJECT_DIR=$(resolve_project_dir "${PROJECT_DIR:-.}")
	step "agent-kit $KIT_VERSION -> $PROJECT_DIR"
	if [ "$DRY_RUN" -eq 1 ]; then
		log "  режим: dry-run, изменения не записываются"
	fi

	install_components
	prune_components
	install_agents_md
	install_opencode_json
	install_openspec_rules
	install_gitignore
	write_manifest

	step "Готово"
	log "  Обновить:  $KIT_ROOT/install.sh --dir \"$PROJECT_DIR\""
	log "  Состояние: $KIT_ROOT/install.sh status \"$PROJECT_DIR\""
	if [ ! -d "$PROJECT_DIR/openspec" ]; then
		log "  OpenSpec:  openspec init . --tools opencode"
	fi
}

# --- состояние --------------------------------------------------------------

# status_drift: сверяет файлы компонентов, instructions[] и правила openspec.
# Без последних двух «расхождений: 0» врало бы: слияния в конфиги — это
# единственное место, где установка может тихо не сработать.
status_drift() {
	_drift=0
	_total=0

	manifest_lines >"$STATE_DIR/manifest"
	while IFS='	' read -r _rel _hash; do
		[ -n "$_rel" ] || continue
		_total=$((_total + 1))
		if [ -L "$PROJECT_DIR/$_rel" ]; then
			log "  SYMLINK  $_rel"
			_drift=$((_drift + 1))
		elif [ ! -f "$PROJECT_DIR/$_rel" ]; then
			log "  MISSING  $_rel"
			_drift=$((_drift + 1))
		elif [ "$(sha256_of "$PROJECT_DIR/$_rel")" != "$_hash" ]; then
			log "  DRIFT    $_rel"
			_drift=$((_drift + 1))
		fi
	done <"$STATE_DIR/manifest"

	# Ссылки на правила kit-а должны быть в instructions[].
	manifest_lines | cut -f1 | sed -n 's|^\.agents/rules/|./.agents/rules/|p' >"$STATE_DIR/expected_instructions"
	if [ -s "$STATE_DIR/expected_instructions" ]; then
		while IFS= read -r _entry; do
			[ -n "$_entry" ] || continue
			if ! grep -qF -- "\"$_entry\"" "$PROJECT_DIR/opencode.json" 2>/dev/null; then
				log "  MISSING  opencode.json: $_entry"
				_drift=$((_drift + 1))
			fi
		done <"$STATE_DIR/expected_instructions"
	fi

	# Правила kit-а должны быть в openspec/config.yaml, если он есть.
	_cfg="$PROJECT_DIR/openspec/config.yaml"
	if [ -f "$_cfg" ] && [ "$NO_OPENSPEC" -eq 0 ]; then
		_missing_keys=
		while IFS='	' read -r _key _rule; do
			[ -n "$_key" ] || continue
			case "$_key" in '#'*) continue ;; esac
			if ! has_line "$_cfg" "    - \"$_rule\""; then
				case " $_missing_keys " in
				*" $_key "*) ;;
				*) _missing_keys="$_missing_keys $_key" ;;
				esac
			fi
		done <"$KIT_ROOT/snippets/openspec.rules.tsv"
		for _key in $_missing_keys; do
			log "  MISSING  openspec/config.yaml: rules.$_key"
			_drift=$((_drift + 1))
		done
	fi

	log ""
	log "  Файлов: $_total, расхождений: $_drift"
	if [ "$_drift" -gt 0 ]; then
		log "  Обновить: $KIT_ROOT/install.sh --dir \"$PROJECT_DIR\""
	fi
	return 0
}

cmd_status() {
	# status не имеет --no-openspec: проверяет всё, что поставлено.
	NO_OPENSPEC=0
	PROJECT_DIR=$(resolve_project_dir "${PROJECT_DIR:-.}")
	step "agent-kit: состояние $PROJECT_DIR"

	if ! manifest_exists; then
		log "  Манифест не найден: kit в этот проект ещё не ставился."
		return 0
	fi

	log "  версия:      $(manifest_field kit_version) (коммит $(manifest_field kit_commit))"
	log "  профиль:     $(manifest_field profile)"
	log "  установлен:  $(manifest_field installed_at)"
	log ""

	status_drift
}

# --- uninstall --------------------------------------------------------------

# Удаляет файлы по манифесту. Локально изменённые файлы остаются, чтобы
# не потерять правки: для них нужен явный --force.
uninstall_files() {
	_removed=0
	_kept=0
	: >"$STATE_DIR/kept.paths"
	: >"$STATE_DIR/kept.pinned"
	manifest_lines >"$STATE_DIR/manifest"
	while IFS='	' read -r _rel _hash; do
		[ -n "$_rel" ] || continue
		_dst="$PROJECT_DIR/$_rel"
		if [ ! -e "$_dst" ] && [ ! -L "$_dst" ]; then
			continue
		fi
		if [ -L "$_dst" ]; then
			rm -f "$_dst"
			ok "$_rel (удалён симлинк)"
			_removed=$((_removed + 1))
			continue
		fi
		if [ "$(sha256_of "$_dst")" != "$_hash" ] && [ "$FORCE" -eq 0 ]; then
			warn "$_rel: изменён после установки, оставлен (--force удалит)"
			# Оставленный файл остаётся под управлением манифеста,
			# иначе повторный --force уже не найдёт его.
			printf '%s\n' "$_rel" >>"$STATE_DIR/kept.paths"
			printf '%s\t%s\n' "$_rel" "$_hash" >>"$STATE_DIR/kept.pinned"
			_kept=$((_kept + 1))
			# Ссылку на него из instructions[] убирать нельзя: файл живёт.
			printf '%s\n' "$_rel" >>"$STATE_DIR/still_present"
			continue
		fi
		rm -f "$_dst"
		prune_empty_dirs "$(dirname "$_dst")"
		ok "$_rel (удалён)"
		_removed=$((_removed + 1))
	done <"$STATE_DIR/manifest"

	step "Итог uninstall"
	log "  Удалено: $_removed, оставлено: $_kept"
}

cmd_uninstall() {
	PROJECT_DIR=$(resolve_project_dir "${PROJECT_DIR:-.}")
	step "agent-kit: удаление из $PROJECT_DIR"

	if ! manifest_exists; then
		log "  Манифест не найден: kit в этот проект не ставился."
		return 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		log "  режим: dry-run, файлы не удаляются"
		log "  Под манифестом: $(manifest_lines | wc -l | tr -d ' ') файл(ов)"
		return 0
	fi

	manifest_lines | cut -f1 | sed -n 's|^\.agents/rules/|./.agents/rules/|p' | sort -u >"$STATE_DIR/instructions.all"
	: >"$STATE_DIR/no_instructions"
	: >"$STATE_DIR/still_present"
	_profile=$(manifest_field profile)
	[ -n "$_profile" ] || _profile=$DEFAULT_PROFILE

	uninstall_files

	# Ссылки на оставленные файлы не трогаем, остальные kit-ссылки убираем.
	# comm требует отсортированные входы.
	sed 's|^|./|' "$STATE_DIR/still_present" | sort -u >"$STATE_DIR/instructions.keep"
	comm -23 "$STATE_DIR/instructions.all" "$STATE_DIR/instructions.keep" >"$STATE_DIR/instructions.remove"

	if have python3 && [ -f "$PROJECT_DIR/opencode.json" ] && [ -s "$STATE_DIR/instructions.remove" ]; then
		refuse_symlink "$PROJECT_DIR/opencode.json" "opencode.json"
		if python3 "$KIT_ROOT/lib/merge.py" json "$PROJECT_DIR/opencode.json" \
			"$STATE_DIR/no_instructions" "$STATE_DIR/instructions.remove" >"$STATE_DIR/merge.out" 2>&1; then
			sed 's/^/        /' "$STATE_DIR/merge.out"
			ok "opencode.json (ссылки kit-а убраны)"
		else
			warn "opencode.json: ссылки нужно убрать вручную"
		fi
	fi

	if have python3 && [ -f "$PROJECT_DIR/openspec/config.yaml" ]; then
		refuse_symlink "$PROJECT_DIR/openspec/config.yaml" "openspec/config.yaml"
		if python3 "$KIT_ROOT/lib/merge.py" yaml-prune "$PROJECT_DIR/openspec/config.yaml" \
			"$KIT_ROOT/snippets/openspec.rules.tsv" >"$STATE_DIR/merge.out" 2>&1; then
			sed 's/^/        /' "$STATE_DIR/merge.out"
			ok "openspec/config.yaml (правила kit-а убраны)"
		else
			warn "openspec/config.yaml: правила нужно убрать вручную"
		fi
	fi

	if [ -s "$STATE_DIR/kept.paths" ]; then
		# Манифест остаётся, пока под ним есть оставленные локальные правки:
		# иначе их уже нечем будет удалить и они выпадут из instructions.
		manifest_write "$_profile" "$STATE_DIR/kept.paths" "$STATE_DIR/kept.pinned" || true
		ok ".agents/$MANIFEST_NAME (сохранён: под ним остались локальные правки)"
		log "  Убрать их полностью: $KIT_ROOT/install.sh uninstall --dir \"$PROJECT_DIR\" --force"
	else
		manifest_remove
		ok ".agents/$MANIFEST_NAME (удалён)"
	fi
	log ""
	log "  AGENTS.md и строка .agent-kit/ в .gitignore оставлены: это ваши файлы."
}

# --- adopt ------------------------------------------------------------------

# В adopt каталог скилла мог прийти прямо из проекта с установленным kit-ом:
# сначала снимаем префикс, потом служебный metadata, иначе при следующей
# установке получилось бы alxmrz_kit_alxmrz_kit_<id> и версия бы не обновлялась.
strip_kit_metadata() {
	_file=$1
	[ "$(head -n 1 "$_file")" = "---" ] || return 0
	grep -q '^metadata:' "$_file" || return 0
	_tmp="$_file.tmp.$$"
	awk '
		NR == 1 { print; next }
		!done && /^---$/ { done = 1; print; next }
		!done && /^metadata:/ { skip = 1; next }
		!done && skip && /^[ \t]/ { next }
		{ skip = 0; print }
	' "$_file" >"$_tmp" && mv "$_tmp" "$_file"
}

# restore_refs возвращает префиксные пути к исходным, чтобы после adopt
# install.sh переписал их заново и подстановки не задвоились.
# php_rules.md не возвращается к `docs/...`: тогда при профиле base ссылка
# снова стала бы битой. Вместо этого она формулируется через профиль.
restore_refs() {
	_file=$1
	grep -q 'alxmrz_kit_' "$_file" || return 0
	_tmp="$_file.tmp.$$"
	sed \
		-e "s|Общие правила — в \`\.agents/rules/${PREFIX}_general_rules\.md\`|Общие правила — в \`docs/general_rules.md\`|g" \
		-e "s|\`\.agents/rules/${PREFIX}_general_rules\.md\`|\`docs/general_rules.md\`|g" \
		-e "s|^Специфика PHP.*\$|Специфика PHP — в \`docs/php_rules.md\`.|" \
		-e "s|\`\.agents/rules/${PREFIX}_php_rules\.md\`|\`docs/php_rules.md\`|g" \
		-e "s|\.agents/skills/${PREFIX}_spec-authoring|.agents/skills/spec-authoring|g" \
		"$_file" >"$_tmp" || {
		rm -f "$_tmp"
		return 0
	}
	finish_tmp "$_tmp" "$_file"
}

cmd_adopt() {
	[ -n "$ADOPT_SRC" ] || die "укажите каталог проекта: ./install.sh adopt <каталог>"
	_src=$(resolve_project_dir "$ADOPT_SRC")
	step "adopt: $_src -> $KIT_ROOT/components"

	_adopted=0
	for _rule in "$_src/docs/general_rules.md" "$_src/docs/php_rules.md"; do
		[ -f "$_rule" ] || continue
		cp "$_rule" "$KIT_ROOT/components/rules/"
		restore_refs "$KIT_ROOT/components/rules/$(basename "$_rule")"
		ok "components/rules/$(basename "$_rule")"
		_adopted=$((_adopted + 1))
	done

	for _skill in "$_src"/.agents/skills/*/; do
		[ -f "${_skill}SKILL.md" ] || continue
		_name=$(basename "$_skill")
		_name=${_name#"${PREFIX}_"}
		case "$_name" in
		openspec-*)
			skip "skills/$_name (генерируется openspec init)"
			continue
			;;
		esac
		mkdir -p "$KIT_ROOT/components/skills/$_name"
		cp -R "$_skill." "$KIT_ROOT/components/skills/$_name/"
		strip_kit_metadata "$KIT_ROOT/components/skills/$_name/SKILL.md"
		restore_refs "$KIT_ROOT/components/skills/$_name/SKILL.md"
		ok "components/skills/$_name"
		_adopted=$((_adopted + 1))
	done

	if [ "$_adopted" -eq 0 ]; then
		die "в $_src нет ни docs/*_rules.md, ни .agents/skills/*/SKILL.md"
	fi
	log ""
	log "  Дальше: проверьте ссылки внутри components/ и закоммитьте."
}

# --- main -------------------------------------------------------------------

parse_args "$@"

STATE_DIR=$(mktemp -d) || die "не удалось создать временный каталог"

case "$COMMAND" in
install) cmd_install ;;
status) cmd_status ;;
uninstall) cmd_uninstall ;;
adopt) cmd_adopt ;;
*) die "неизвестная команда: $COMMAND" ;;
esac
