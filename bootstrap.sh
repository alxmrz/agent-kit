#!/bin/sh
# bootstrap.sh — точка входа для нового проекта.
#
#   curl -fsSL https://raw.githubusercontent.com/alxmrz/agent-kit/main/bootstrap.sh | sh
#
# Клонирует kit в <корень проекта>/.agent-kit, запускает install.py и удаляет
# клон: в проекте остаются только поставленные файлы. Повторный запуск ставит
# свежую версию. Всё пишется только внутрь текущего проекта.

set -eu

REPO_URL=${AGENT_KIT_REPO:-https://github.com/alxmrz/agent-kit.git}
REF=${AGENT_KIT_REF:-main}
OFFLINE=0
HAS_DIR=0
DRY_RUN=0
CREATED=0

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

# --offline относится к обновлению клона и в install.py не пробрасывается:
# остальные аргументы (--dir, --with, --dry-run) уходят туда как есть.
# Флаги вырезаются вращением "$@", а не строкой: значения --with содержат
# пробелы и обязаны остаться одним аргументом.
NARGS=$#
n=0
SKIP_NEXT=0
while [ "$n" -lt "$NARGS" ]; do
	n=$((n + 1))
	arg=$1
	shift
	if [ "$SKIP_NEXT" -eq 1 ]; then
		# Значение --dir: может выглядеть как флаг, поэтому флаги в нём не ищем.
		SKIP_NEXT=0
		set -- "$@" "$arg"
		continue
	fi
	case "$arg" in
	--offline) OFFLINE=1 ;;
	--dir)
		HAS_DIR=1
		SKIP_NEXT=1
		set -- "$@" "$arg"
		;;
	*)
		[ "$arg" = "--dry-run" ] && DRY_RUN=1
		set -- "$@" "$arg"
		;;
	esac
done

command -v git >/dev/null 2>&1 || die "нужен git"
# install.py — единственная точка установки: без python3 ставить нечем.
# Проверка до клонирования, чтобы не оставлять в проекте клон без пользы.
command -v python3 >/dev/null 2>&1 || die "нужен python3"

# Корень проекта, а не текущий подкаталог: запуск из src/ не должен
# ставить правила в src/. Если проект не под git — работаем в текущем каталоге.
TARGET=$(pwd -P)
if ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$ROOT" ]; then
	TARGET=$ROOT
fi

KIT_DIR=${AGENT_KIT_DIR:-"$TARGET/.agent-kit"}
case "$KIT_DIR" in
/*) ;;
*) KIT_DIR="$TARGET/$KIT_DIR" ;;
esac

if [ ! -d "$KIT_DIR/.git" ]; then
	if [ -e "$KIT_DIR" ]; then
		die "$KIT_DIR существует, но это не клон agent-kit; уберите его или задайте AGENT_KIT_DIR"
	fi
	printf '== Клонирую %s -> %s\n' "$REPO_URL" "$KIT_DIR"
	git clone --depth 1 --branch "$REF" "$REPO_URL" "$KIT_DIR" ||
		die "не удалось склонировать $REPO_URL"
	CREATED=1
elif [ "$OFFLINE" -eq 1 ]; then
	printf '== Обновление клона пропущено (--offline)\n'
else
	printf '== Обновляю %s\n' "$KIT_DIR"
	if git -C "$KIT_DIR" fetch --depth 1 origin "$REF"; then
		git -C "$KIT_DIR" checkout --detach FETCH_HEAD 2>/dev/null ||
			printf '  WARN  остаюсь на текущей ревизии\n' >&2
	else
		printf '  WARN  не удалось обновить, работаю с текущим клоном\n' >&2
	fi
fi

# Удаляется только клон внутри проекта: в проекте нужны поставленные файлы, а не
# сам kit. Каталог снаружи проекта (AGENT_KIT_DIR) — выбор пользователя, его не
# трогаем. Пути сравниваются каноническими: `..` и симлинки не должны позволить
# удалить что-то за пределами проекта или сам проект. Симлинк вместо каталога
# тоже не удаляем: rm -rf пошёл бы по ссылке.
REMOVE=0
_kit_abs=$(CDPATH='' cd -- "$KIT_DIR" && pwd -P) || _kit_abs=
_target_abs=$(CDPATH='' cd -- "$TARGET" && pwd -P) || _target_abs=
if [ -n "$_kit_abs" ] && [ -n "$_target_abs" ] && [ ! -L "$KIT_DIR" ] &&
	[ "$_kit_abs" != "$_target_abs" ]; then
	case "$_kit_abs" in
	"$_target_abs"/*) REMOVE=1 ;;
	esac
fi
if [ "$REMOVE" -eq 0 ]; then
	printf '  WARN  клон не будет удалён (вне проекта или это симлинк): %s\n' "$KIT_DIR" >&2
elif [ "$CREATED" -eq 0 ]; then
	# Клон создан не этим запуском. В dry-run ничего не пишется — оставляем как
	# есть; рабочий клон с правками (kit дорабатывают) тоже не трогаем.
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '  план: dry-run, существующий клон не удаляется\n'
		REMOVE=0
	elif [ -n "$(git -C "$KIT_DIR" status --porcelain 2>/dev/null)" ]; then
		printf '  WARN  в клоне есть незакоммиченные изменения, не удаляю: %s\n' "$KIT_DIR" >&2
		REMOVE=0
	else
		printf '  WARN  клон уже существовал; после установки он будет удалён: %s\n' "$KIT_DIR" >&2
	fi
fi

# install.py подсказывает «Обновить» по-разному: при удалении клона ссылка на
# install.py была бы нерабочей.
AGENT_KIT_EPHEMERAL=$REMOVE
export AGENT_KIT_EPHEMERAL

# install.py ставит файлы в каталог из --dir; по умолчанию — корень проекта.
STATUS=0
if [ "$HAS_DIR" -eq 1 ]; then
	python3 "$KIT_DIR/install.py" "$@" || STATUS=$?
else
	python3 "$KIT_DIR/install.py" "$@" --dir "$TARGET" || STATUS=$?
fi

# При ошибке клон остаётся: по нему видно, что и где сломалось, и его можно
# переиспользовать для повторного запуска.
if [ "$STATUS" -ne 0 ]; then
	printf '  WARN  установка не удалась; клон оставлен: %s\n' "$KIT_DIR" >&2
	exit "$STATUS"
fi

if [ "$REMOVE" -eq 1 ]; then
	if rm -rf "$_kit_abs"; then
		printf '\n== Клон kit-а удалён: %s\n' "$KIT_DIR"
		printf '   В проекте остались только поставленные файлы.\n'
	else
		printf '  WARN  не удалось удалить клон: %s\n' "$KIT_DIR" >&2
	fi
fi
