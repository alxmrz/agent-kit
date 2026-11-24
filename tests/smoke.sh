#!/bin/sh
# smoke.sh — проверка kit-а на одноразовых каталогах.
#   ./tests/smoke.sh
# Ничего вне /tmp не трогает.

set -eu

KIT_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$*"; }
bad() {
	FAIL=$((FAIL + 1))
	printf '  FAIL  %s\n' "$*" >&2
}
check() {
	_desc=$1
	shift
	if "$@"; then ok "$_desc"; else bad "$_desc"; fi
}

# new_project <имя> — пустой git-проект.
new_project() {
	_dir="$WORK/$1"
	mkdir -p "$_dir"
	git -C "$_dir" init -q
	printf '%s\n' "$_dir"
}

kit() { sh "$KIT_ROOT/install.sh" "$@"; }

# kit_ext <имя> — копия kit-а с дополнительными группами и новыми типами
# компонентов (commands/, agents/): проверяем расширяемость без правки скрипта.
kit_ext() {
	_dir="$WORK/$1"
	mkdir -p "$_dir"
	cp -R "$KIT_ROOT/install.sh" "$KIT_ROOT/bootstrap.sh" "$KIT_ROOT/lib" \
		"$KIT_ROOT/components" "$KIT_ROOT/snippets" "$KIT_ROOT/VERSION" "$_dir/"
	mkdir -p "$_dir/components/js/rules" "$_dir/components/go/rules"
	printf '# JS\n' >"$_dir/components/js/rules/js_rules.md"
	printf '# Go\n' >"$_dir/components/go/rules/go_rules.md"
	printf -- '---\ndescription: review\n---\nСделай ревью.\n' \
		>"$_dir/components/base/commands/review.md"
	printf -- '---\ndescription: reviewer\n---\nТы ревьюер.\n' \
		>"$_dir/components/base/agents/reviewer.md"
	printf '%s\n' "$_dir"
}

# --- 1. базовая установка ---------------------------------------------------
printf '\n== 1. install\n'
P=$(new_project basic)
kit --dir "$P" >"$WORK/install.log" 2>&1 || bad "установка упала (см. $WORK/install.log)"

check "правило создано с префиксом" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "скилл создан с префиксом" test -f "$P/.agents/skills/alxmrz_kit_spec-authoring/SKILL.md"
check "вспомогательный файл скилла скопирован" test -f "$P/.agents/skills/alxmrz_kit_spec-authoring/references/traceability.md"
check "php_rules не попал в base" test ! -f "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "манифеста нет" test ! -e "$P/.agents/.alxmrz_kit_manifest.json"
check "opencode.json не создан" test ! -e "$P/opencode.json"
check "AGENTS.md создан" test -f "$P/AGENTS.md"
check "в AGENTS.md нет плейсхолдеров" sh -c "! grep -q '{{' '$P/AGENTS.md'"
check "AGENTS.md ссылается на правило kit-а" grep -q 'alxmrz_kit_general_rules.md' "$P/AGENTS.md"
check ".gitignore игнорирует клон" grep -qxF '.agent-kit/' "$P/.gitignore"
check "base не ссылается на php_rules" sh -c "! grep -q 'php_rules' '$P/.agents/rules/alxmrz_kit_general_rules.md'"
check "skills не содержат metadata kit-а" sh -c "! grep -q 'alxmrz-kit:' '$P/.agents/skills/alxmrz_kit_conventional-commit/SKILL.md'"
check "name: скилла не подменён ID" grep -qx 'name: conventional-commit' "$P/.agents/skills/alxmrz_kit_conventional-commit/SKILL.md"

# --- 2. безусловная перезапись ---------------------------------------------
printf '\n== 2. перезапись\n'
P=$(new_project overwrite)
kit --dir "$P" >/dev/null 2>&1
printf '\n# моя правка\n' >>"$P/.agents/rules/alxmrz_kit_general_rules.md"
kit --dir "$P" >/dev/null 2>&1
check "правка в файле kit-а исчезает" sh -c "! grep -q '# моя правка' '$P/.agents/rules/alxmrz_kit_general_rules.md'"
check "содержимое совпало с источником" cmp -s \
	"$P/.agents/rules/alxmrz_kit_general_rules.md" \
	"$KIT_ROOT/components/base/rules/general_rules.md"

# --- 3. идемпотентность -----------------------------------------------------
printf '\n== 3. повторный запуск\n'
P=$(new_project idempotent)
kit --dir "$P" >/dev/null 2>&1
cp -a "$P" "$WORK/idempotent-snap"
kit --dir "$P" >/dev/null 2>&1
check "второй запуск не меняет файлы" sh -c "diff -r '$P' '$WORK/idempotent-snap' >/dev/null"
check ".gitignore не дублирует строку" test "$(grep -cxF '.agent-kit/' "$P/.gitignore")" -eq 1

# --- 4. чужие файлы ---------------------------------------------------------
printf '\n== 4. чужие файлы\n'
P=$(new_project foreign)
mkdir -p "$P/.agents/skills/spec-authoring" "$P/.agents/rules"
printf -- '---\nname: my-own-spec\n---\nМОЁ\n' >"$P/.agents/skills/spec-authoring/SKILL.md"
printf '# мои правила\n' >"$P/.agents/rules/general_rules.md"
kit --dir "$P" >/dev/null 2>&1
check "свой скилл с похожим именем цел" grep -qxF 'МОЁ' "$P/.agents/skills/spec-authoring/SKILL.md"
check "своё правило цело" grep -qxF '# мои правила' "$P/.agents/rules/general_rules.md"
check "рядом появился префиксованный скилл" test -f "$P/.agents/skills/alxmrz_kit_spec-authoring/SKILL.md"
check "рядом появилось префиксованное правило" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"

# --- 5. --with --------------------------------------------------------------
printf '\n== 5. --with\n'
P=$(new_project with-php)
kit --dir "$P" --with php >/dev/null 2>&1
check "--with php ставит php_rules" test -f "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "--with php ставит и base" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "php_rules ссылается на general_rules" grep -q 'alxmrz_kit_general_rules' "$P/.agents/rules/alxmrz_kit_php_rules.md"

P=$(new_project with-spaces)
kit --dir "$P" --with ' php , ' >/dev/null 2>&1
check "пробелы и запятые в --with разбираются" test -f "$P/.agents/rules/alxmrz_kit_php_rules.md"

EXT=$(kit_ext ext-groups)
P=$(new_project with-many)
sh "$EXT/install.sh" --dir "$P" --with php,js --with go >/dev/null 2>&1
check "повтор --with объединяет группы (php)" test -f "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "повтор --with объединяет группы (js)" test -f "$P/.agents/rules/alxmrz_kit_js_rules.md"
check "повтор --with объединяет группы (go)" test -f "$P/.agents/rules/alxmrz_kit_go_rules.md"

P=$(new_project with-unknown)
if kit --dir "$P" --with nope >"$WORK/unknown.log" 2>&1; then
	bad "неизвестная группа принята"
else
	ok "неизвестная группа отклонена"
fi
check "ошибка называет доступные группы" grep -q 'есть: base php' "$WORK/unknown.log"
check "при неизвестной группе ничего не записано" sh -c "
	[ ! -e '$P/.agents' ] && [ ! -e '$P/AGENTS.md' ] && [ ! -e '$P/.gitignore' ]
"

# --- 6. команды и агенты ----------------------------------------------------
printf '\n== 6. commands и agents\n'
P=$(new_project commands)
sh "$EXT/install.sh" --dir "$P" >/dev/null 2>&1
check "команда попала в .opencode/commands" test -f "$P/.opencode/commands/alxmrz_kit_review.md"
check "агент попал в .opencode/agents" test -f "$P/.opencode/agents/alxmrz_kit_reviewer.md"
check "пустые каталоги группы не создают мусора" sh -c "
	! ls '$P/.opencode/commands/' | grep -v '^alxmrz_kit_review.md$' | grep -q .
"

# --- 7. AGENTS.md: свой файл и симлинк -------------------------------------
printf '\n== 7. AGENTS.md\n'
P=$(new_project agents-own)
printf '# Мой AGENTS\n' >"$P/AGENTS.md"
kit --dir "$P" >"$WORK/own.log" 2>&1
check "свой AGENTS.md не перезаписан" grep -qxF '# Мой AGENTS' "$P/AGENTS.md"
check "печатается подсказка про instructions[]" grep -q 'instructions\[\]' "$WORK/own.log"
check "подсказка содержит путь правила" grep -q '.agents/rules/alxmrz_kit_general_rules.md' "$WORK/own.log"

P=$(new_project agents-created)
kit --dir "$P" >"$WORK/created.log" 2>&1
check "подсказка не печатается при создании AGENTS.md" sh -c "! grep -q 'instructions\[\]' '$WORK/created.log'"
check "правка своего AGENTS.md переживает обновление" sh -c "
	printf '\nправка\n' >>'$P/AGENTS.md'
	sh '$KIT_ROOT/install.sh' --dir '$P' >/dev/null 2>&1
	grep -qxF 'правка' '$P/AGENTS.md'
"

P=$(new_project agents-link)
printf 'НЕ ТРОГАТЬ\n' >"$WORK/victim-agents.md"
ln -s "$WORK/victim-agents.md" "$P/AGENTS.md"
kit --dir "$P" >/dev/null 2>&1 || bad "симлинк AGENTS.md уронил установку"
check "AGENTS.md остался симлинком" test -L "$P/AGENTS.md"
check "файл по симлинку не изменён" grep -qxF 'НЕ ТРОГАТЬ' "$WORK/victim-agents.md"

# --- 8. .gitignore ----------------------------------------------------------
printf '\n== 8. .gitignore\n'
P=$(new_project gitignore-none)
kit --dir "$P" >/dev/null 2>&1
check "строка дописана" grep -qxF '.agent-kit/' "$P/.gitignore"

P=$(new_project gitignore-own)
printf 'vendor/\r\n' >"$P/.gitignore"
cp "$P/.gitignore" "$WORK/gi-own-before"
kit --dir "$P" >/dev/null 2>&1
check "чужое содержимое сохранено байт-в-байт" sh -c "
	_size=\$(wc -c <'$WORK/gi-own-before' | tr -d ' ')
	head -c \"\$_size\" '$P/.gitignore' >'$WORK/gi-own-head'
	cmp -s '$WORK/gi-own-head' '$WORK/gi-own-before'
"
check "строка дописана после чужой" test "$(wc -l <"$P/.gitignore" | tr -d ' ')" -eq 2

P=$(new_project gitignore-has)
printf '.agent-kit/\n' >"$P/.gitignore"
cp "$P/.gitignore" "$WORK/gi-before"
kit --dir "$P" >/dev/null 2>&1
check "существующая строка не дублируется и файл не тронут" cmp -s "$P/.gitignore" "$WORK/gi-before"

# --- 9. dry-run -------------------------------------------------------------
printf '\n== 9. dry-run\n'
P=$(new_project dry)
kit --dir "$P" --dry-run >/dev/null 2>&1
check "dry-run не создал .agents" test ! -d "$P/.agents"
check "dry-run не создал AGENTS.md" test ! -e "$P/AGENTS.md"
check "dry-run не создал .gitignore" test ! -e "$P/.gitignore"

# --- 10. границы записи ------------------------------------------------------
printf '\n== 10. границы\n'
if kit --dir "$HOME" >"$WORK/home.log" 2>&1; then
	bad "установка в домашний каталог разрешена"
else
	ok "домашний каталог запрещён"
fi
if kit --dir / >"$WORK/root.log" 2>&1; then
	bad "установка в корень разрешена"
else
	ok "корень файловой системы запрещён"
fi
check "в домашнем каталоге ничего не создано" test ! -e "$HOME/.agents/rules/alxmrz_kit_general_rules.md"
check "HOME со слешем не обходит защиту" sh -c "! HOME='$HOME/' sh '$KIT_ROOT/install.sh' --dir '$HOME' >/dev/null 2>&1"
check "HOME без переменной не роняет запуск" sh -c "env -u HOME sh '$KIT_ROOT/install.sh' --dir '$WORK/basic' >/dev/null 2>&1"
check "несуществующий каталог — внятная ошибка" sh -c "
	sh '$KIT_ROOT/install.sh' --dir '$WORK/nope' 2>&1 | grep -q 'нет такого каталога'
"
if kit --dir "$KIT_ROOT/README.md" >/dev/null 2>&1; then
	bad "файл вместо каталога принят"
else
	ok "файл вместо каталога отклонён"
fi

P=$(new_project link)
mkdir -p "$P/.agents/rules"
printf 'НЕ ТРОГАТЬ\n' >"$WORK/victim.md"
ln -s "$WORK/victim.md" "$P/.agents/rules/alxmrz_kit_general_rules.md"
if kit --dir "$P" >/dev/null 2>&1; then
	bad "установка через симлинк разрешена"
else
	ok "установка через симлинк отклонена"
fi
check "файл по симлинку не изменён" grep -qxF 'НЕ ТРОГАТЬ' "$WORK/victim.md"

# --- 11. ошибка компонента прерывает установку -----------------------------
printf '\n== 11. битый компонент\n'
EXT=$(kit_ext ext-broken)
mkdir -p "$EXT/components/base/rules/nested"
printf '# вложенный\n' >"$EXT/components/base/rules/nested/x.md"
P=$(new_project broken)
if sh "$EXT/install.sh" --dir "$P" >/dev/null 2>&1; then
	bad "вложенность в rules/ не прервала установку"
else
	ok "вложенность в rules/ прерывает установку"
fi

printf '\n== Итог: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
