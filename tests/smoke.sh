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

# new_project <имя> — пустой git-проект с opencode.json.
new_project() {
	_dir="$WORK/$1"
	mkdir -p "$_dir"
	git -C "$_dir" init -q
	printf '{\n  "model": "x"\n}\n' >"$_dir/opencode.json"
	printf '%s\n' "$_dir"
}

kit() { sh "$KIT_ROOT/install.sh" "$@"; }

# --- 1. базовая установка ---------------------------------------------------
printf '\n== 1. install\n'
P=$(new_project basic)
kit --dir "$P" >"$WORK/install.log" 2>&1 || bad "установка упала (см. $WORK/install.log)"

check "правило создано с префиксом" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "скилл создан с префиксом" test -f "$P/.agents/skills/alxmrz_kit_spec-authoring/SKILL.md"
check "манифест создан" test -f "$P/.agents/.alxmrz_kit_manifest.json"
check "AGENTS.md создан" test -f "$P/AGENTS.md"
check "php_rules не попал в профиль base" test ! -f "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "instructions[] дополнен" grep -q 'alxmrz_kit_general_rules.md' "$P/opencode.json"
check "opencode.json остался валидным JSON" python3 -c "import json,sys; json.load(open('$P/opencode.json'))"
check ".gitignore игнорирует клон" grep -qxF '.agent-kit/' "$P/.gitignore"
check "внутренние ссылки правил переписаны на префикс" grep -q 'alxmrz_kit_php_rules.md' "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "скилл помечен версией kit-а" grep -q 'alxmrz-kit:' "$P/.agents/skills/alxmrz_kit_conventional-commit/SKILL.md"
check "name: скилла не подменён ID" grep -qx 'name: conventional-commit' "$P/.agents/skills/alxmrz_kit_conventional-commit/SKILL.md"

# --- 2. идемпотентность -----------------------------------------------------
printf '\n== 2. повторный запуск\n'
cp -a "$P" "$WORK/basic-snap"
kit --dir "$P" >"$WORK/run2.log" 2>&1
check "второй запуск не меняет файлы" sh -c "diff -r '$P' '$WORK/basic-snap' >/dev/null"
check "второй запуск не дублирует instructions" test "$(grep -c 'alxmrz_kit_general_rules' "$P/opencode.json")" -eq 1

# --- 3. чужие файлы не трогаются -------------------------------------------
printf '\n== 3. чужие файлы\n'
P=$(new_project foreign)
mkdir -p "$P/.agents/skills/spec-authoring"
printf -- '---\nname: my-own-spec\n---\nМОЁ\n' >"$P/.agents/skills/spec-authoring/SKILL.md"
printf '# Мой AGENTS\n' >"$P/AGENTS.md"
kit --dir "$P" >/dev/null 2>&1
check "свой скилл с похожим именем цел" grep -qxF 'МОЁ' "$P/.agents/skills/spec-authoring/SKILL.md"
check "свой AGENTS.md не перезаписан" grep -qxF '# Мой AGENTS' "$P/AGENTS.md"
check "рядом появился префиксованный скилл" test -f "$P/.agents/skills/alxmrz_kit_spec-authoring/SKILL.md"

# --- 4. openspec: чужие правила целы ---------------------------------------
printf '\n== 4. openspec\n'
P=$(new_project spec)
mkdir -p "$P/openspec"
cat >"$P/openspec/config.yaml" <<'EOF'
schema: spec-driven

rules:
  specs:
    - Моё правило
  proposal:
    - Коротко

operations:
  apply:
    guidance:
      - Кратко
EOF
kit --dir "$P" >/dev/null 2>&1
kit --dir "$P" >/dev/null 2>&1
check "чужое правило specs сохранено" grep -qxF '    - Моё правило' "$P/openspec/config.yaml"
check "чужое правило proposal сохранено" grep -qxF '    - Коротко' "$P/openspec/config.yaml"
check "правило kit-а добавлено" grep -q 'alxmrz_kit_spec-authoring' "$P/openspec/config.yaml"
check "operations не затронут" grep -q '^  apply:' "$P/openspec/config.yaml"
check "правила kit-а не продублированы" test "$(grep -c 'alxmrz_kit_spec-authoring' "$P/openspec/config.yaml")" -eq 4
check "yaml остался валидным" python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
yaml.safe_load(open('$P/openspec/config.yaml'))
"

# --- 5. дрифт и --keep-modified --------------------------------------------
printf '\n== 5. локальные правки\n'
P=$(new_project drift)
kit --dir "$P" >/dev/null 2>&1
printf '\n# моя правка\n' >>"$P/.agents/rules/alxmrz_kit_general_rules.md"
check "status видит DRIFT" sh -c "sh '$KIT_ROOT/install.sh' status '$P' | grep -q DRIFT"
kit --dir "$P" --keep-modified >/dev/null 2>&1
check "--keep-modified сохраняет правку" grep -q '# моя правка' "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "--keep-modified не забывает дрифт" sh -c "sh '$KIT_ROOT/install.sh' status '$P' | grep -q DRIFT"
kit --dir "$P" >/dev/null 2>&1
check "обычный запуск перезаписывает правку" sh -c "! grep -q '# моя правка' '$P/.agents/rules/alxmrz_kit_general_rules.md'"
check "манифест совпадает с файлом после перезаписи" sh -c "
	h=\$(sha256sum '$P/.agents/rules/alxmrz_kit_general_rules.md' | cut -d' ' -f1)
	grep -q \"\\\"\$h\\\"\" '$P/.agents/.alxmrz_kit_manifest.json'
"
check "status снова чистый" sh -c "sh '$KIT_ROOT/install.sh' status '$P' | grep -q 'расхождений: 0'"

# --- 6. dry-run -------------------------------------------------------------
printf '\n== 6. dry-run\n'
P=$(new_project dry)
kit --dir "$P" --dry-run >/dev/null 2>&1
check "dry-run ничего не создал" test ! -d "$P/.agents"

# --- 7. защита от записи вне проекта ---------------------------------------
printf '\n== 7. границы\n'
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
check "в домашнем каталоге ничего не создано" test ! -d "$HOME/.agents/rules/alxmrz_kit_general_rules.md"

# --- 8. профили -------------------------------------------------------------
printf '\n== 8. профили\n'
P=$(new_project prof)
kit --dir "$P" --profile php >/dev/null 2>&1
check "профиль php даёт php_rules" test -f "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "профиль php ссылается на general_rules" grep -q 'alxmrz_kit_general_rules' "$P/.agents/rules/alxmrz_kit_php_rules.md"
if kit --dir "$P" --profile нетакого >/dev/null 2>&1; then
	bad "неизвестный профиль принят"
else
	ok "неизвестный профиль отклонён"
fi

printf '\n== Итог: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
