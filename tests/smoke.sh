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
check "opencode.json создан" test -f "$P/opencode.json"
check "opencode.json валиден" sh -c "python3 -c 'import json,sys; json.load(open(sys.argv[1]))' '$P/opencode.json'"
check "instructions[] содержит правило base" grep -q '"\./\.agents/rules/alxmrz_kit_general_rules.md"' "$P/opencode.json"
check "instructions[] не содержит неподключённую группу" sh -c "! grep -q 'php_rules' '$P/opencode.json'"
check "AGENTS.md создан" test -f "$P/AGENTS.md"
check "в AGENTS.md нет плейсхолдеров" sh -c "! grep -q '{{' '$P/AGENTS.md'"
check "AGENTS.md ссылается на правило kit-а" grep -q 'alxmrz_kit_general_rules.md' "$P/AGENTS.md"
check "AGENTS.md говорит, что правила в opencode.json" grep -q 'instructions\[\]' "$P/AGENTS.md"
check ".gitignore не создан" test ! -e "$P/.gitignore"
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
check "повторный запуск не создал .gitignore" test ! -e "$P/.gitignore"

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
	[ ! -e '$P/.agents' ] && [ ! -e '$P/AGENTS.md' ] && [ ! -e '$P/.opencode' ]
"

# --- 6. opencode.json: правила в instructions[] -----------------------------
printf '\n== 6. opencode.json\n'
P=$(new_project own-config)
cat >"$P/opencode.json" <<'JSON'
{
    "model": "example/model",
    "instructions": [
        "./docs/my_rules.md"
    ]
}
JSON
cp "$P/opencode.json" "$WORK/own-config-before"
kit --dir "$P" --with php >"$WORK/own-opencode.log" 2>&1
check "instructions[] дополнены правилом base" sh -c "
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(\"\n\".join(d[\"instructions\"]))' '$P/opencode.json' |
		grep -qx './.agents/rules/alxmrz_kit_general_rules.md'
"
check "instructions[] дополнены правилом выбранной группы" sh -c "
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(\"\n\".join(d[\"instructions\"]))' '$P/opencode.json' |
		grep -qx './.agents/rules/alxmrz_kit_php_rules.md'
"
check "чужие настройки и запись instructions сохранены" sh -c "
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d[\"model\"] == \"example/model\"; assert d[\"instructions\"][0] == \"./docs/my_rules.md\"' '$P/opencode.json'
"
check "чужой отступ 4 пробела сохранён" grep -qx '    "model": "example/model",' "$P/opencode.json"
check "лог сообщает о добавленных путях" grep -q 'added: ./\.agents/rules/alxmrz_kit_general_rules.md' "$WORK/own-opencode.log"

cp "$P/opencode.json" "$WORK/own-config-once"
kit --dir "$P" --with php >/dev/null 2>&1
check "повторный запуск не меняет opencode.json" cmp -s "$P/opencode.json" "$WORK/own-config-once"

kit --dir "$P" --with php >/dev/null 2>&1
check "настройки kit-а переживают повтор" grep -qx '    "model": "example/model",' "$P/opencode.json"
check "повтор не дублирует пути" sh -c "
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(\"\n\".join(d[\"instructions\"]))' '$P/opencode.json' |
		grep -c 'alxmrz_kit_general_rules.md' | grep -qx 1
"

# CRLF и однострочный JSON не должны переформатироваться.
P=$(new_project crlf-config)
printf '{\r\n  "instructions": [\r\n    "./docs/own.md"\r\n  ]\r\n}\r\n' >"$P/opencode.json"
kit --dir "$P" >/dev/null 2>&1
check "CRLF сохранён" sh -c "od -c '$P/opencode.json' | grep -q '\\\\r'"
check "чужая запись CRLF-конфига цела" grep -q './docs/own.md' "$P/opencode.json"

P=$(new_project compact-config)
printf '{"instructions":["./docs/own.md"]}\n' >"$P/opencode.json"
kit --dir "$P" >/dev/null 2>&1
check "однострочный JSON остался однострочным" test "$(wc -l <"$P/opencode.json")" -eq 1

# Установка только дополняет конфиг: чужие записи и записи прежних запусков
# остаются — kit не удаляет из проекта ни файлы, ни строки конфига.
P=$(new_project append-only)
kit --dir "$P" --with php >/dev/null 2>&1
kit --dir "$P" >/dev/null 2>&1
check "запись прежнего запуска не удаляется" grep -q 'alxmrz_kit_php_rules' "$P/opencode.json"
check "файл правила тоже остался" test -f "$P/.agents/rules/alxmrz_kit_php_rules.md"

# JSONC и битый JSON: файл не трогается, печатаются пути для ручной правки.
P=$(new_project jsonc-config)
printf '{\n  // комментарий\n  "instructions": []\n}\n' >"$P/opencode.json"
cp "$P/opencode.json" "$WORK/jsonc-before"
kit --dir "$P" >"$WORK/jsonc.log" 2>&1 || bad "JSONC уронил установку"
check "JSONC не изменён" cmp -s "$P/opencode.json" "$WORK/jsonc-before"
check "для JSONC печатается подсказка" grep -q 'инструкц\|instructions\[\]' "$WORK/jsonc.log"

# opencode.jsonc не трогаем: комментарии ломают разбор, а рядом с ним
# opencode.json не создаём — иначе получится два конфига.
P=$(new_project jsonc-project)
printf '{\n  // комментарий\n}\n' >"$P/opencode.jsonc"
kit --dir "$P" >"$WORK/jsonc-project.log" 2>&1 || bad "opencode.jsonc уронил установку"
check "при opencode.jsonc файл не создан" test ! -e "$P/opencode.json"
check "opencode.jsonc не изменён" grep -q '// комментарий' "$P/opencode.jsonc"
check "для opencode.jsonc печатается подсказка" grep -q 'instructions\[\]' "$WORK/jsonc-project.log"

# Симлинк opencode.json не трогается, установка не падает.
P=$(new_project link-config)
printf 'НЕ ТРОГАТЬ\n' >"$WORK/victim-config.json"
ln -s "$WORK/victim-config.json" "$P/opencode.json"
kit --dir "$P" >"$WORK/link-config.log" 2>&1 || bad "симлинк opencode.json уронил установку"
check "файл по симлинку opencode.json не изменён" grep -qxF 'НЕ ТРОГАТЬ' "$WORK/victim-config.json"
check "правила поставлены при симлинке opencode.json" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"

# --- 7. команды и агенты ----------------------------------------------------
printf '\n== 7. commands и agents\n'
P=$(new_project commands)
sh "$EXT/install.sh" --dir "$P" >/dev/null 2>&1
check "команда попала в .opencode/commands" test -f "$P/.opencode/commands/alxmrz_kit_review.md"
check "агент попал в .opencode/agents" test -f "$P/.opencode/agents/alxmrz_kit_reviewer.md"
check "пустые каталоги группы не создают мусора" sh -c "
	! ls '$P/.opencode/commands/' | grep -v '^alxmrz_kit_review.md$' | grep -q .
"

# --- 8. AGENTS.md: свой файл и симлинк -------------------------------------
printf '\n== 8. AGENTS.md\n'
P=$(new_project agents-own)
printf '# Мой AGENTS\n' >"$P/AGENTS.md"
kit --dir "$P" >"$WORK/own.log" 2>&1
check "свой AGENTS.md не перезаписан" grep -qxF '# Мой AGENTS' "$P/AGENTS.md"
check "правила подключены и при своём AGENTS.md" sh -c "
	grep -q 'alxmrz_kit_general_rules.md' '$P/opencode.json'
"

P=$(new_project agents-created)
kit --dir "$P" >"$WORK/created.log" 2>&1
check "AGENTS.md создан и правила подключены" sh -c "
	test -f '$P/AGENTS.md' && grep -q 'alxmrz_kit_general_rules.md' '$P/opencode.json'
"
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

# --- 9. .gitignore не трогается ---------------------------------------------
printf '\n== 9. .gitignore\n'
P=$(new_project gitignore-none)
kit --dir "$P" >/dev/null 2>&1
check ".gitignore не создан" test ! -e "$P/.gitignore"

P=$(new_project gitignore-own)
printf 'vendor/\r\n' >"$P/.gitignore"
cp "$P/.gitignore" "$WORK/gi-own-before"
kit --dir "$P" >/dev/null 2>&1
check "чужой .gitignore сохранён байт-в-байт" cmp -s "$P/.gitignore" "$WORK/gi-own-before"

# --- 10. dry-run ------------------------------------------------------------
printf '\n== 10. dry-run\n'
P=$(new_project dry)
kit --dir "$P" --dry-run >/dev/null 2>&1
check "dry-run не создал .agents" test ! -d "$P/.agents"
check "dry-run не создал AGENTS.md" test ! -e "$P/AGENTS.md"

# --- 11. границы записи -----------------------------------------------------
printf '\n== 11. границы\n'
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

# --- 12. bootstrap.sh удаляет клон -----------------------------------------
printf '\n== 12. bootstrap\n'
# Локальный «origin» из текущих исходников kit-а: сеть тесту не нужна.
ORIGIN="$WORK/origin"
mkdir -p "$ORIGIN"
cp -R "$KIT_ROOT/install.sh" "$KIT_ROOT/bootstrap.sh" "$KIT_ROOT/lib" \
	"$KIT_ROOT/components" "$KIT_ROOT/snippets" "$KIT_ROOT/VERSION" "$ORIGIN/"
git -C "$ORIGIN" init -q -b main
git -C "$ORIGIN" add -A
git -C "$ORIGIN" -c user.email=t@t -c user.name=t commit -qm init

P=$(new_project bootstrap)
if sh -c "cd '$P' && AGENT_KIT_REPO='$ORIGIN' sh '$KIT_ROOT/bootstrap.sh' --with php" \
	>"$WORK/bootstrap.log" 2>&1; then
	ok "bootstrap поставил файлы"
else
	bad "bootstrap упал (см. $WORK/bootstrap.log)"
fi
check "правила на месте" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "группа --with дошла до install.sh" test -f "$P/.agents/rules/alxmrz_kit_php_rules.md"
check "клон .agent-kit удалён" test ! -e "$P/.agent-kit"
check "AGENTS.md создан" test -f "$P/AGENTS.md"
check "в лог попало удаление клона" grep -q 'Клон kit-а удалён' "$WORK/bootstrap.log"
check "подсказка обновления не ведёт в удалённый клон" sh -c "
	! grep -q '\.agent-kit/install.sh' '$WORK/bootstrap.log'
"

# Существующий клон в dry-run не удаляется: установка ничего не пишет, значит и
# не трогает то, чего не создавала.
P=$(new_project bootstrap-dry)
git clone -q --depth 1 "$ORIGIN" "$P/.agent-kit"
if sh -c "cd '$P' && sh '$KIT_ROOT/bootstrap.sh' --offline --dry-run" >/dev/null 2>&1; then
	ok "bootstrap --dry-run завершился"
else
	bad "bootstrap --dry-run упал"
fi
check "dry-run оставил клон на месте" test -d "$P/.agent-kit"
check "dry-run не поставил файлы" test ! -e "$P/.agents"

# Свежий клон в dry-run — временный артефакт самого запуска: проект должен
# остаться чистым, поэтому он удаляется.
P=$(new_project bootstrap-dry-fresh)
if sh -c "cd '$P' && AGENT_KIT_REPO='$ORIGIN' sh '$KIT_ROOT/bootstrap.sh' --dry-run" \
	>/dev/null 2>&1; then
	ok "bootstrap --dry-run со свежим клоном завершился"
else
	bad "bootstrap --dry-run со свежим клоном упал"
fi
check "свежий клон удалён после dry-run" test ! -e "$P/.agent-kit"
check "проект после dry-run пуст" sh -c "
	[ ! -e '$P/.agents' ] && [ ! -e '$P/AGENTS.md' ]
"

# Клон снаружи проекта — выбор пользователя (AGENT_KIT_DIR), его не удаляем.
P=$(new_project bootstrap-outside)
OUT="$WORK/outside-kit"
git clone -q --depth 1 "$ORIGIN" "$OUT"
if sh -c "cd '$P' && AGENT_KIT_DIR='$OUT' sh '$KIT_ROOT/bootstrap.sh' --offline" \
	>"$WORK/bootstrap-outside.log" 2>&1; then
	ok "bootstrap с внешним клоном завершился"
else
	bad "bootstrap с внешним клоном упал"
fi
check "внешний клон не удалён" test -d "$OUT/.git"
check "файлы поставлены" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"

# Ошибка установки: клон остаётся, чтобы было видно, что сломалось.
P=$(new_project bootstrap-fail)
if sh -c "cd '$P' && AGENT_KIT_REPO='$ORIGIN' sh '$KIT_ROOT/bootstrap.sh' --with nope" \
	>/dev/null 2>&1; then
	bad "bootstrap проглотил ошибку установки"
else
	ok "bootstrap вернул ошибку установки"
fi
check "после ошибки клон оставлен" test -d "$P/.agent-kit"

# После неудачного запуска клон остался: следующий запуск использует его и
# удаляет после успешной установки.
if sh -c "cd '$P' && sh '$KIT_ROOT/bootstrap.sh' --offline" >"$WORK/bootstrap-retry.log" 2>&1; then
	ok "повторный запуск поверх оставшегося клона"
else
	bad "повторный запуск поверх клона упал (см. $WORK/bootstrap-retry.log)"
fi
check "правила поставлены при повторе" test -f "$P/.agents/rules/alxmrz_kit_general_rules.md"
check "оставшийся клон удалён после успеха" test ! -e "$P/.agent-kit"

# Рабочий клон с правками — не временный каталог, его не удаляем.
P=$(new_project bootstrap-dirty)
git clone -q --depth 1 "$ORIGIN" "$P/.agent-kit"
printf '\n# доработка kit-а\n' >>"$P/.agent-kit/install.sh"
if sh -c "cd '$P' && sh '$KIT_ROOT/bootstrap.sh' --offline" >"$WORK/bootstrap-dirty.log" 2>&1; then
	ok "установка из изменённого клона завершилась"
else
	bad "установка из изменённого клона упала"
fi
check "клон с правками не удалён" test -f "$P/.agent-kit/install.sh"
check "правка в клоне цела" grep -q '# доработка kit-а' "$P/.agent-kit/install.sh"
check "предупреждение о незакоммиченных изменениях" grep -q 'незакоммиченные изменения' "$WORK/bootstrap-dirty.log"

# --- 13. ошибка компонента прерывает установку -----------------------------
printf '\n== 13. битый компонент\n'
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
