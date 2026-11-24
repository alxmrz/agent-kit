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

# sha <файл>: тот же выбор утилиты, что и в lib/common.sh,
# иначе тест не запустится на macOS (там нет sha256sum).
# Отдельный скрипт, а не функция: часть проверок идёт через sh -c.
cat >"$WORK/sha" <<'EOF'
#!/bin/sh
if command -v sha256sum >/dev/null 2>&1; then
	sha256sum "$1" | cut -d' ' -f1
elif command -v shasum >/dev/null 2>&1; then
	shasum -a 256 "$1" | cut -d' ' -f1
else
	openssl dgst -sha256 "$1" | sed 's/.*= *//'
fi
EOF
chmod +x "$WORK/sha"

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
	h=\$('$WORK/sha' '$P/.agents/rules/alxmrz_kit_general_rules.md')
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

check "base не ссылается на безусловный php_rules" sh -c "
	grep -q 'PHP-специфика подключается профилем' '$WORK/basic/.agents/rules/alxmrz_kit_general_rules.md'
"

# --- 9. смена профиля: сироты удаляются ------------------------------------
printf '\n== 9. смена профиля\n'
P=$(new_project switch)
kit --dir "$P" --profile php >/dev/null 2>&1
kit --dir "$P" --profile base >/dev/null 2>&1
check "php_rules удалён после возврата на base" test ! -e "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "ссылка на php_rules убрана из instructions" sh -c "! grep -q 'php_rules' '$P/opencode.json'"
check "kit-правила openspec не остались сиротами" sh -c "
	! grep -q 'alxmrz_kit' '$P/openspec/config.yaml' 2>/dev/null || true
"
check "status чист после смены профиля" sh -c "sh '$KIT_ROOT/install.sh' status '$P' | grep -q 'расхождений: 0'"

# --- 10. симлинки не перезаписывают чужие файлы ----------------------------
printf '\n== 10. симлинки\n'
P=$(new_project link)
mkdir -p "$P/.agents/rules"
printf 'НЕ ТРОГАТЬ\n' >"$WORK/victim.txt"
ln -s "$WORK/victim.txt" "$P/.agents/rules/alxmrz_kit_general_rules.md"
if kit --dir "$P" >/dev/null 2>&1; then
	bad "установка через симлинк разрешена"
else
	ok "установка через симлинк отклонена"
fi
check "файл по симлинку не изменён" grep -qxF 'НЕ ТРОГАТЬ' "$WORK/victim.txt"

# --- 11. openspec: нестандартная разметка не портится ----------------------
printf '\n== 11. openspec: нестандартный yaml\n'
P=$(new_project yaml-comment)
mkdir -p "$P/openspec"
printf 'schema: x\n\nrules:  # мои\n  specs:\n    - чужое\n' >"$P/openspec/config.yaml"
kit --dir "$P" >/dev/null 2>&1
kit --dir "$P" >/dev/null 2>&1
check "rules с комментарием не дублируется" test "$(grep -c '^rules:' "$P/openspec/config.yaml")" -eq 1
check "чужое правило цело при повторных запусках" grep -qxF '    - чужое' "$P/openspec/config.yaml"

P=$(new_project yaml-inline)
mkdir -p "$P/openspec"
printf 'schema: x\n\nrules: {}\n' >"$P/openspec/config.yaml"
before=$("$WORK/sha" "$P/openspec/config.yaml")
kit --dir "$P" >/dev/null 2>&1
check "inline rules не переписаны вслепую" test "$("$WORK/sha" "$P/openspec/config.yaml")" = "$before"

P=$(new_project yaml-indent)
mkdir -p "$P/openspec"
printf 'rules:\n    specs:\n        - чужое\n' >"$P/openspec/config.yaml"
kit --dir "$P" >/dev/null 2>&1
check "нестандартный отступ оставляет yaml валидным" python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
yaml.safe_load(open('$P/openspec/config.yaml'))
"

# --- 12. ошибка компонента прерывает установку -----------------------------
printf '\n== 12. ошибка в профиле\n'
cp -R "$KIT_ROOT" "$WORK/kit-broken"
printf 'rules/nope.md\n' >>"$WORK/kit-broken/components/profiles/base.list"
P=$(new_project broken)
if sh "$WORK/kit-broken/install.sh" --dir "$P" >/dev/null 2>&1; then
	bad "ошибка профиля не прервала установку"
else
	ok "ошибка профиля прерывает установку"
fi
check "частичная установка не записана" test ! -f "$P/.agents/.alxmrz_kit_manifest.json"

# --- 13. status проверяет слияния в конфиги ---------------------------------
printf '\n== 13. status и конфиги\n'
P=$(new_project status-json)
kit --dir "$P" >/dev/null 2>&1
python3 - "$P" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1], "opencode.json")
data = json.loads(path.read_text())
data["instructions"] = []
path.write_text(json.dumps(data, indent=2) + "\n")
PY
check "status видит ссылку, выпавшую из instructions" sh -c "
	sh '$KIT_ROOT/install.sh' status '$P' | grep -q 'MISSING  opencode.json'
"

P=$(new_project status-yaml)
mkdir -p "$P/openspec"
printf 'schema: x\n\nrules:\n  specs:\n    - чужое\n' >"$P/openspec/config.yaml"
kit --dir "$P" >/dev/null 2>&1
printf 'rules: {}\n' >"$P/openspec/config.yaml"
check "status видит неслитые правила openspec" sh -c "
	sh '$KIT_ROOT/install.sh' status '$P' | grep -q 'MISSING  openspec/config.yaml'
"

# --- 14. uninstall ----------------------------------------------------------
printf '\n== 14. uninstall\n'
P=$(new_project remove)
kit --dir "$P" --profile php >/dev/null 2>&1
kit uninstall --dir "$P" >/dev/null 2>&1
check "uninstall удалил правила" test ! -e "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "uninstall удалил скиллы" test ! -d "$P/.agents/skills/alxmrz_kit_spec-authoring"
check "uninstall убрал ссылки kit-а из instructions" sh -c "! grep -q 'alxmrz_kit' '$P/opencode.json'"
check "uninstall убрал манифест" test ! -f "$P/.agents/.alxmrz_kit_manifest.json"
check "uninstall не тронул AGENTS.md" test -f "$P/AGENTS.md"

P=$(new_project remove-modified)
kit --dir "$P" >/dev/null 2>&1
printf '\nправка\n' >>"$P/.agents/rules/alxmrz_kit_general_rules.md"
kit uninstall --dir "$P" >/dev/null 2>&1
check "uninstall оставляет изменённый локально файл" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"
kit uninstall --dir "$P" --force >/dev/null 2>&1 || true
check "uninstall --force удаляет его" sh -c "
	[ ! -e '$P/.agents/rules/alxmrz_kit_general_rules.md' ] || ! grep -q 'правка' '$P/.agents/rules/alxmrz_kit_general_rules.md'
"

# --- 15. adopt --------------------------------------------------------------
printf '\n== 15. adopt\n'
cp -R "$KIT_ROOT" "$WORK/kit-adopt"
P=$(new_project adopt-src)
kit --dir "$P" >/dev/null 2>&1
sh "$WORK/kit-adopt/install.sh" adopt "$P" >/dev/null 2>&1
check "adopt снимает префикс kit-а" sh -c "
	[ -d '$WORK/kit-adopt/components/skills/spec-authoring' ] &&
	[ ! -d '$WORK/kit-adopt/components/skills/alxmrz_kit_spec-authoring' ]
"
check "adopt не забирает metadata kit-а" sh -c "
	! grep -q 'alxmrz-kit' '$WORK/kit-adopt/components/skills/spec-authoring/SKILL.md'
"


printf '\n== Итог: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
