#!/bin/sh
# bootstrap.sh — точка входа для нового проекта.
#
#   curl -fsSL https://raw.githubusercontent.com/alxmrz/agent-kit/main/bootstrap.sh | sh
#
# Клонирует kit в <корень проекта>/.agent-kit и сразу запускает install.sh.
# Повторный запуск обновляет клон и перегенерирует файлы.
# Всё пишется только внутрь текущего проекта.

set -eu

REPO_URL=${AGENT_KIT_REPO:-https://github.com/alxmrz/agent-kit.git}
REF=${AGENT_KIT_REF:-main}
OFFLINE=0
HAS_DIR=0

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

# --offline относится к обновлению клона; остальные флаги уходят в install.sh.
for arg in "$@"; do
	case "$arg" in
	--offline) OFFLINE=1 ;;
	--dir) HAS_DIR=1 ;;
	esac
done

command -v git >/dev/null 2>&1 || die "нужен git"

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

# install.sh ставит файлы в каталог из --dir; по умолчанию — корень проекта.
if [ "$HAS_DIR" -eq 1 ]; then
	sh "$KIT_DIR/install.sh" "$@"
else
	sh "$KIT_DIR/install.sh" "$@" --dir "$TARGET"
fi
