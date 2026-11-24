#!/usr/bin/env python3
"""Идемпотентные слияния в файлы, которые нельзя переименовать.

Режимы:
  json <opencode.json> <файл-со-списком> [<файл-на-удаление>]
      Дополняет instructions[] отсутствующими путями и (если передан третий
      файл) убирает пути, которые kit больше не ставит. Существующие записи
      не меняются, порядок сохраняется. Файла нет — создаётся.

  yaml <openspec/config.yaml> <tsv-файл>
      Обновляет правила в разделе rules. Строки с маркером [alxmrz_kit]
      принадлежат kit-у и пересоздаются; чужие правила не трогаются.

  yaml-prune <openspec/config.yaml> <tsv-файл>
      Убирает строки kit-а для ключей из tsv (используется uninstall).

Код возврата 3 означает «файл не поддержан», вызывающая сторона печатает
инструкцию для ручной правки. Ничего не пишется, если результат совпал
с исходным текстом.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys

MARKER = "[alxmrz_kit]"


# --- общее ------------------------------------------------------------------


def write_atomic(target: pathlib.Path, text: str) -> None:
    """Запись через временный файл: обрыв не оставляет обрезанный конфиг."""
    tmp = target.with_name(target.name + f".tmp.{os.getpid()}")
    try:
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, target)
    finally:
        if tmp.exists():
            tmp.unlink()


def read_list(path: pathlib.Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


# --- opencode.json ----------------------------------------------------------


def jsonc_comments(path: pathlib.Path) -> list[str]:
    """Строки с комментариями: JSONC ломает json.loads."""
    return [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip().startswith(("//", "/*"))
    ]


def normalize(entry: str) -> str:
    """Сравнение путей из instructions[] без учёта ./ в начале."""
    return entry[2:] if entry.startswith("./") else entry


def detect_indent(text: str) -> int | None:
    """Отступ существующего файла: чтобы слияние не переформатировало его целиком.

    None — файл однострочный, отступа нет.
    """
    for line in text.splitlines():
        if not line.strip() or line.strip() == "{":
            continue
        width = len(line) - len(line.lstrip(" "))
        if width > 0:
            return width
        break
    return None


def merge_json(target: pathlib.Path, list_file: pathlib.Path, remove_file: pathlib.Path | None) -> int:
    entries = read_list(list_file)
    removals = set(read_list(remove_file)) if remove_file is not None else set()
    if not entries and not removals:
        return 0

    if target.exists():
        if jsonc_comments(target):
            return 3
        # read_bytes, а не read_text: иначе universal newlines съест CRLF
        # и файл с виндовыми переводами строк перепишется в LF.
        text = target.read_bytes().decode("utf-8")
        try:
            data = json.loads(text) if text.strip() else {}
        except json.JSONDecodeError as exc:
            print(f"        {exc}", file=sys.stderr)
            return 3
    else:
        text = ""
        data = {}

    if not isinstance(data, dict):
        return 3

    current = data.get("instructions", [])
    if not isinstance(current, list):
        return 3

    drop = {normalize(entry) for entry in removals}
    kept = [entry for entry in current if normalize(entry) not in drop]
    missing = [entry for entry in entries if normalize(entry) not in {normalize(k) for k in kept}]
    merged = kept + missing
    if merged == current:
        return 0

    data["instructions"] = merged
    indent = detect_indent(text) or 2
    # Однострочный JSON остаётся однострочным: иначе первый же запуск
    # разворачивает чужой компактный конфиг в шумный дифф.
    if text.strip() and "\n" not in text.strip():
        rendered = json.dumps(data, separators=(", ", ": "), ensure_ascii=False) + "\n"
    else:
        rendered = json.dumps(data, indent=indent, ensure_ascii=False) + "\n"
    # CRLF-файл не должен превращаться в LF: это шумный дифф в чужом репозитории.
    if "\r\n" in text:
        rendered = rendered.replace("\n", "\r\n")
    write_atomic(target, rendered)
    for entry in missing:
        print(f"added: {entry}")
    for entry in current:
        if entry not in merged:
            print(f"removed: {entry}")
    return 0


# --- openspec/config.yaml ---------------------------------------------------


def rule_groups(list_file: pathlib.Path) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {}
    for raw in list_file.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        key, sep, rule = raw.partition("\t")
        if not sep or not rule.strip():
            raise SystemExit(f"ERROR: строка без табуляции в {list_file}: {raw!r}")
        groups.setdefault(key.strip(), []).append(rule.strip())
    return groups


def rules_bounds(lines: list[str]) -> tuple[int, int]:
    """Границы блока top-level `rules:`: (строка `rules:`, конец блока).

    Возвращает (-1, -1), если блока нет. Бросает ValueError, если раздел
    записан в форме, которую нельзя безопасно править построчно:
    значение в той же строке (`rules: {}`), ключ на другом отступе или
    inline-список. Все такие случаи означают «править вручную», а не угадывать.
    """
    starts = [i for i, line in enumerate(lines) if line.startswith("rules:")]
    if not starts:
        return -1, -1
    start = starts[0]
    tail = lines[start].rstrip("\r\n").strip()[len("rules:"):].strip()
    if tail and not tail.startswith("#"):
        raise ValueError(f"rules записан в одну строку: {lines[start].strip()!r}")

    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].strip() and not lines[index].startswith((" ", "\t")):
            end = index
            break
    return start, end


def key_extent(lines: list[str], key: str, begin: int, end: int) -> tuple[int, int]:
    """Границы подраздела `  <key>:` внутри [begin, end)."""
    start = -1
    for index in range(begin, end):
        stripped = lines[index].rstrip("\r\n")
        if stripped == f"  {key}:":
            start = index
            break
        if re.match(rf"^\s+{re.escape(key)}:", stripped):
            raise ValueError(f"ключ {key!r} в rules записан с нестандартным отступом")
        if re.match(rf"^  {re.escape(key)}:\s*\S", stripped):
            raise ValueError(f"ключ {key!r} в rules записан в одну строку")
    if start < 0:
        return -1, -1

    stop = start + 1
    while stop < end:
        line = lines[stop]
        if not line.strip():
            stop += 1
            continue
        if line.startswith(("    ", "\t")):
            stop += 1
            continue
        break
    return start, stop


def strip_our_lines(lines: list[str], start: int, end: int) -> list[str]:
    kept = [line for line in lines[start:end] if MARKER not in line]
    return lines[:start] + kept + lines[end:]


def drop_empty_keys(lines: list[str], keys) -> list[str]:
    """Убирает подразделы rules, в которых после чистки не осталось строк.

    Иначе uninstall оставил бы `design:`/`tasks:` со значением null —
    формально валидный, но мусорный YAML.
    """
    for key in keys:
        index = 0
        while True:
            rules_index, rules_end = rules_bounds(lines)
            if rules_index < 0:
                return lines
            start, end = key_extent(lines, key, rules_index + 1, rules_end)
            if start < 0:
                break
            if any(line.strip() for line in lines[start + 1:end]):
                break
            del lines[start:end]
    return lines


def rewrite_rules(text: str, groups: dict[str, list[str]], action: str) -> str:
    """Удаляет/вставляет строки kit-а в разделе rules.

    action: "merge" — заменить свои строки на groups; "prune" — только убрать.
    Бросает ValueError, если разметку нельзя править построчно.
    """
    lines = text.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"

    rules_index, rules_end = rules_bounds(lines)
    for key in groups:
        start, end = key_extent(lines, key, rules_index + 1 if rules_index >= 0 else 0, rules_end)
        if start >= 0:
            lines = strip_our_lines(lines, start, end)

    if action == "prune":
        return "".join(drop_empty_keys(lines, groups))

    rules_index, _ = rules_bounds(lines)
    if rules_index < 0:
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.append("rules:\n")
        rules_index = len(lines) - 1

    # Вставляем в обратном порядке, чтобы индексы не съезжали.
    for key in reversed(list(groups)):
        block = [f"    - {quote(rule)}\n" for rule in groups[key]]
        start, _ = key_extent(lines, key, rules_index + 1, len(lines))
        if start < 0:
            lines[rules_index + 1:rules_index + 1] = [f"  {key}:\n"] + block
        else:
            lines[start + 1:start + 1] = block

    # Повторный запуск не должен размножать разделы rules и ключи в них.
    if [i for i, line in enumerate(lines) if line.startswith("rules:")] != [rules_index]:
        raise ValueError("в файле оказалось несколько разделов rules:")
    for key in groups:
        if sum(1 for line in lines if line.rstrip("\r\n") == f"  {key}:") > 1:
            raise ValueError(f"в rules оказалось несколько ключей {key!r}")

    return "".join(lines)


def merge_yaml(target: pathlib.Path, list_file: pathlib.Path) -> int:
    groups = rule_groups(list_file)
    if not groups:
        return 0

    text = target.read_text(encoding="utf-8") if target.exists() else ""
    try:
        merged = rewrite_rules(text, groups, "merge")
    except ValueError as exc:
        print(f"        {exc}", file=sys.stderr)
        return 3

    if merged == text:
        return 0
    write_atomic(target, merged)
    print(f"updated: rules ({', '.join(groups)})")
    return 0


def prune_yaml(target: pathlib.Path, list_file: pathlib.Path) -> int:
    groups = rule_groups(list_file)
    if not groups or not target.exists():
        return 0

    text = target.read_text(encoding="utf-8")
    try:
        merged = rewrite_rules(text, groups, "prune")
    except ValueError as exc:
        print(f"        {exc}", file=sys.stderr)
        return 3

    if merged == text:
        return 0
    write_atomic(target, merged)
    print("removed: rules kit-а")
    return 0


def quote(rule: str) -> str:
    """Однострочный YAML: экранируются только кавычки и обратные слэши."""
    escaped = rule.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


# --- main -------------------------------------------------------------------


def main() -> int:
    if len(sys.argv) < 4 or len(sys.argv) > 5:
        print("usage: merge.py (json|yaml|yaml-prune) <target> <list-file> [<remove-file>]", file=sys.stderr)
        return 1

    mode, target, list_file = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    remove_file = pathlib.Path(sys.argv[4]) if len(sys.argv) == 5 else None
    if mode == "json":
        return merge_json(target, list_file, remove_file)
    if mode == "yaml":
        return merge_yaml(target, list_file)
    if mode == "yaml-prune":
        return prune_yaml(target, list_file)
    print(f"неизвестный режим: {mode}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
