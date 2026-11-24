#!/usr/bin/env python3
"""Идемпотентные слияния в файлы, которые нельзя переименовать.

Режимы:
  json <opencode.json> <файл-со-списком>
      Дополняет instructions[] отсутствующими путями. Существующие записи
      не меняются, порядок сохраняется. Файла нет — создаётся.

  yaml <openspec/config.yaml> <tsv-файл>
      Обновляет правила в разделе rules. Строки с маркером [alxmrz_kit]
      принадлежат kit-у и пересоздаются; чужие правила не трогаются.

Код возврата 3 означает «файл не поддержан», вызывающая сторона печатает
инструкцию для ручной правки.
"""

import json
import pathlib
import sys

MARKER = "[alxmrz_kit]"


# --- opencode.json ----------------------------------------------------------


def references(path: pathlib.Path) -> list[str]:
    """Проверяет, что файл не JSONC: комментарии ломают json.loads."""
    return [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip().startswith(("//", "/*"))
    ]


def merge_json(target: pathlib.Path, list_file: pathlib.Path) -> int:
    entries = [line.strip() for line in list_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not entries:
        return 0

    if target.exists():
        if references(target):
            return 3
        text = target.read_text(encoding="utf-8").strip()
        try:
            data = json.loads(text) if text else {}
        except json.JSONDecodeError as exc:
            print(f"        {exc}", file=sys.stderr)
            return 3
    else:
        data = {}

    if not isinstance(data, dict):
        return 3

    current = data.get("instructions", [])
    if not isinstance(current, list):
        return 3

    missing = [entry for entry in entries if entry not in current]
    if not missing:
        return 0

    data["instructions"] = current + missing
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for entry in missing:
        print(f"added: {entry}")
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


def key_block(lines: list[str], key: str) -> tuple[int, int]:
    """Границы блока `  <key>:` в rules: (начало, конец). (-1, -1) — нет блока."""
    start = -1
    for index, line in enumerate(lines):
        if line.rstrip("\n") == f"  {key}:":
            start = index
            break
    if start < 0:
        return -1, -1

    end = start + 1
    while end < len(lines):
        line = lines[end]
        if not line.strip():
            end += 1
            continue
        if line.startswith(("    ", "\t")):
            end += 1
            continue
        break
    return start, end


def strip_our_lines(lines: list[str], start: int, end: int) -> list[str]:
    kept = [line for line in lines[start:end] if MARKER not in line]
    return lines[:start] + kept + lines[end:]


def merge_yaml(target: pathlib.Path, list_file: pathlib.Path) -> int:
    groups = rule_groups(list_file)
    if not groups:
        return 0

    text = target.read_text(encoding="utf-8") if target.exists() else ""
    lines = text.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"

    for key in groups:
        start, end = key_block(lines, key)
        if start >= 0:
            lines = strip_our_lines(lines, start, end)

    rules_index = -1
    for index, line in enumerate(lines):
        if line.rstrip("\n") == "rules:":
            rules_index = index
            break

    if rules_index < 0:
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.append("rules:\n")
        rules_index = len(lines) - 1

    # Вставляем в обратном порядке, чтобы индексы не съезжали.
    for key in reversed(list(groups)):
        block = [f"    - {quote(rule)}\n" for rule in groups[key]]
        start, _ = key_block(lines, key)
        if start < 0:
            lines[rules_index + 1:rules_index + 1] = [f"  {key}:\n"] + block
        else:
            lines[start + 1:start + 1] = block

    merged = "".join(lines)
    if merged == text:
        return 0
    target.write_text(merged, encoding="utf-8")
    print(f"updated: rules ({', '.join(groups)})")
    return 0


def quote(rule: str) -> str:
    """Однострочный YAML: экранируются только кавычки и обратные слэши."""
    escaped = rule.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


# --- main -------------------------------------------------------------------


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: merge.py (json|yaml) <target> <list-file>", file=sys.stderr)
        return 1

    mode, target, list_file = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    if mode == "json":
        return merge_json(target, list_file)
    if mode == "yaml":
        return merge_yaml(target, list_file)
    print(f"неизвестный режим: {mode}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
