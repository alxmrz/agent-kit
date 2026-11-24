#!/usr/bin/env python3
"""Дополнение instructions[] в opencode.json путями правил kit-а.

Использование:
    merge.py json <opencode.json> <файл-со-списком>

Список — по одному пути на строку. Недостающие пути добавляются в конец
instructions[], существующие записи и их порядок сохраняются: kit только
дополняет конфиг проекта и никогда ничего из него не удаляет. Файла нет —
создаётся с одним ключом instructions.

Форматирование сохраняется: отступ берётся из самого файла, однострочный JSON
остаётся однострочным, CRLF не превращается в LF. Если добавлять нечего, файл не
перезаписывается (mtime не дёргается).

Коды возврата:
    0 — готово (в том числе «добавлять нечего»)
    2 — ошибка чтения или записи
    3 — файл не поддержан (комментарии JSONC, невалидный JSON, instructions не
        массив строк); вызывающая сторона печатает пути для ручной правки
"""

from __future__ import annotations

import json
import os
import pathlib
import stat
import sys


def read_entries(path: pathlib.Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return [line.strip() for line in text.splitlines() if line.strip()]


def normalize(entry: str) -> str:
    """Сравнение путей без учёта ./ в начале: `./.agents/x` и `.agents/x`."""
    return entry[2:] if entry.startswith("./") else entry


def has_comments(text: str) -> bool:
    """JSONC ломает json.loads: такой файл правится вручную."""
    return any(line.strip().startswith(("//", "/*")) for line in text.splitlines())


def detect_indent(text: str) -> int | None:
    """Отступ существующего файла, чтобы не переформатировать его целиком.

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


def write_atomic(target: pathlib.Path, text: str) -> None:
    """Запись через временный файл: обрыв не оставляет обрезанный конфиг."""
    tmp = target.with_name(target.name + f".tmp.{os.getpid()}")
    try:
        with open(tmp, "wb") as handle:
            handle.write(text.encode("utf-8"))
        if target.exists():
            os.chmod(tmp, stat.S_IMODE(target.stat().st_mode))
        os.replace(tmp, target)
    finally:
        if tmp.exists():
            tmp.unlink()


def merge(target: pathlib.Path, desired: list[str]) -> int:
    if target.exists():
        # read_bytes, а не read_text: иначе universal newlines съест CRLF
        # и файл с виндовыми переводами строк перепишется в LF.
        text = target.read_bytes().decode("utf-8")
        if has_comments(text):
            return 3
        try:
            data = json.loads(text) if text.strip() else {}
        except json.JSONDecodeError as exc:
            print(f"{exc}", file=sys.stderr)
            return 3
    else:
        text = ""
        data = {}

    if not isinstance(data, dict):
        return 3

    current = data.get("instructions", [])
    if not isinstance(current, list):
        return 3
    if not all(isinstance(entry, str) for entry in current):
        return 3

    present = {normalize(entry) for entry in current}
    missing = []
    for entry in desired:
        key = normalize(entry)
        if key not in present:
            present.add(key)
            missing.append(entry)
    if not missing:
        return 0

    data["instructions"] = current + missing
    indent = detect_indent(text) or 2
    # Однострочный JSON остаётся однострочным: иначе первый же запуск
    # разворачивает чужой компактный конфиг в шумный дифф.
    if text.strip() and "\n" not in text.strip():
        rendered = json.dumps(data, separators=(", ", ": "), ensure_ascii=False) + "\n"
    else:
        rendered = json.dumps(data, indent=indent, ensure_ascii=False) + "\n"
    if "\r\n" in text:
        rendered = rendered.replace("\n", "\r\n")

    write_atomic(target, rendered)
    for entry in missing:
        print(f"added: {entry}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[0] != "json":
        print("использование: merge.py json <opencode.json> <список>", file=sys.stderr)
        return 2

    target = pathlib.Path(argv[1])
    list_file = pathlib.Path(argv[2])
    try:
        desired = read_entries(list_file)
        return merge(target, desired)
    except (OSError, UnicodeDecodeError) as exc:
        print(f"{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
