#!/bin/sh
# agent-kit: шаблонные файлы для работы с ИИ внутри проекта.
#
#   ./install.sh [install] [флаги]   поставить или обновить файлы kit-а
#   ./install.sh status              показать, что стоит и что разошлось
#   ./install.sh adopt <каталог>     забрать компоненты в этот репозиторий
#
# Файлы создаются только внутри проекта. Домашний каталог и глобальные
# настройки агентов не читаются и не изменяются.

set -eu

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
KIT_ROOT=$SELF_DIR
KIT_VERSION=$(tr -d ' \n' <"$KIT_ROOT/VERSION")

. "$KIT_ROOT/lib/common.sh"
. "$KIT_ROOT/lib/components.sh"
. "$KIT_ROOT/lib/manifest.sh"
. "$KIT_ROOT/lib/render.sh"

STATE_DIR=
PROJECT_DIR=
PROFILE=$DEFAULT_PROFILE
DRY_RUN=0
KEEP_MODIFIED=0
NO_AGENTS=0
NO_OPENSPEC=0

cleanup() {
	if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ]; then
		rm -rf "$STATE_DIR"
	fi
}
trap cleanup EXIT HUP INT TERM

usage() {
	cat <<EOF
agent-kit $KIT_VERSION

Использование:
  ./install.sh [install] [флаги]   поставить или обновить файлы kit-а
  ./install.sh status [каталог]    показать состояние установки
  ./install.sh adopt <каталог>     забрать компоненты в этот репозиторий

Флаги:
  --dir <каталог>      целевой проект (по умолчанию текущий каталог)
  --profile <имя>      профиль компонентов (по умолчанию $DEFAULT_PROFILE;
                       доступны: $(list_profiles | tr '\n' ' '))
  --dry-run            показать план, ничего не записывая
  --keep-modified      не перезаписывать локально изменённые kit-файлы
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
		install | status | adopt)
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
		ok "$1 (план)"
		return 0
	fi

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
	while IFS= read -r _src; do
		_rel=$(target_path "$_src")
		in_project "$_rel"
		printf '%s\n' "$_rel" >>"$STATE_DIR/targets"
		install_file "$_rel" "$_src"
	done <"$STATE_DIR/sources"
}

install_agents_md() {
	step "AGENTS.md"
	_dst="$PROJECT_DIR/AGENTS.md"

	if [ "$NO_AGENTS" -eq 1 ]; then
		skip "AGENTS.md (--no-agents)"
		return 0
	fi
	if [ -e "$_dst" ]; then
		skip "AGENTS.md (уже есть; kit его не перезаписывает)"
		return 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		ok "AGENTS.md (план: создать из шаблона)"
		return 0
	fi

	sed 's|{{TEST_CMD}}|TODO: команда запуска тестов|g' \
		"$KIT_ROOT/snippets/AGENTS.md.tmpl" >"$_dst"
	ok "AGENTS.md (создан из шаблона)"
	warn "AGENTS.md: заполните разделы TODO — дальше kit его не трогает"
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

	instructions_list >"$STATE_DIR/instructions"

	if python3 "$KIT_ROOT/lib/merge.py" json "$PROJECT_DIR/opencode.json" \
		"$STATE_DIR/instructions" >"$STATE_DIR/merge.out" 2>&1; then
		sed 's/^/        /' "$STATE_DIR/merge.out"
		ok "opencode.json (instructions[] актуален)"
	else
		warn "opencode.json: слияние не удалось, добавьте вручную:"
		instructions_list | sed 's|^|          "|; s|$|",|'
	fi
}

instructions_list() {
	sed -n 's|^\.agents/rules/|./.agents/rules/|p' "$STATE_DIR/targets"
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

	if python3 "$KIT_ROOT/lib/merge.py" yaml "$_cfg" \
		"$KIT_ROOT/snippets/openspec.rules.tsv" >"$STATE_DIR/merge.out" 2>&1; then

		sed 's/^/        /' "$STATE_DIR/merge.out"
		ok "openspec/config.yaml (правила kit-а обновлены)"
	else
		warn "openspec/config.yaml: слияние не удалось, правила не изменены"
	fi
}

install_gitignore() {
	step ".gitignore"
	_gi="$PROJECT_DIR/.gitignore"

	if has_line "$_gi" ".agent-kit/"; then
		skip ".gitignore (.agent-kit/ уже игнорируется)"
		return 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		ok ".gitignore (план: добавить .agent-kit/)"
		return 0
	fi

	if [ -s "$_gi" ] && [ -n "$(tail -c 1 "$_gi")" ]; then
		printf '\n' >>"$_gi"
	fi
	printf '.agent-kit/\n' >>"$_gi"
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

cmd_status() {
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

	manifest_lines >"$STATE_DIR/manifest"
	_total=0
	_drift=0
	while IFS='	' read -r _rel _hash; do
		[ -n "$_rel" ] || continue
		_total=$((_total + 1))
		if [ ! -f "$PROJECT_DIR/$_rel" ]; then
			log "  MISSING  $_rel"
			_drift=$((_drift + 1))
		elif [ "$(sha256_of "$PROJECT_DIR/$_rel")" != "$_hash" ]; then
			log "  DRIFT    $_rel"
			_drift=$((_drift + 1))
		fi
	done <"$STATE_DIR/manifest"

	log ""
	log "  Файлов: $_total, расхождений: $_drift"
	if [ "$_drift" -gt 0 ]; then
		log "  Обновить: $KIT_ROOT/install.sh --dir \"$PROJECT_DIR\""
	fi
}

# --- adopt ------------------------------------------------------------------

cmd_adopt() {
	[ -n "$ADOPT_SRC" ] || die "укажите каталог проекта: ./install.sh adopt <каталог>"
	_src=$(resolve_project_dir "$ADOPT_SRC")
	step "adopt: $_src -> $KIT_ROOT/components"

	_adopted=0
	for _rule in "$_src/docs/general_rules.md" "$_src/docs/php_rules.md"; do
		[ -f "$_rule" ] || continue
		cp "$_rule" "$KIT_ROOT/components/rules/"
		ok "components/rules/$(basename "$_rule")"
		_adopted=$((_adopted + 1))
	done

	for _skill in "$_src"/.agents/skills/*/; do
		[ -f "${_skill}SKILL.md" ] || continue
		_name=$(basename "$_skill")
		case "$_name" in
		openspec-*)
			skip "skills/$_name (генерируется openspec init)"
			continue
			;;
		esac
		mkdir -p "$KIT_ROOT/components/skills/$_name"
		cp -R "$_skill." "$KIT_ROOT/components/skills/$_name/"
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
adopt) cmd_adopt ;;
*) die "неизвестная команда: $COMMAND" ;;
esac
