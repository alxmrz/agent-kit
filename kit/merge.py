"""Дополнение instructions[] в opencode.json путями правил kit-а.

`merge()` возвращает `MergeResult(status=..., added=[...])`, где `status` —
один из `OK`, `UNSUPPORTED`, `IO_ERROR`; вызывающая сторона сама переводит
результат в вывод.

Недостающие пути добавляются в конец `instructions[]`, существующие записи и
их порядок сохраняются: kit только дополняет конфиг проекта и никогда ничего
из него не удаляет. Файла нет — создаётся с одним ключом instructions.

Форматирование сохраняется: отступ берётся из самого файла, однострочный JSON
остаётся однострочным, CRLF не превращается в LF. Если добавлять нечего, файл не
перезаписывается (mtime не дёргается).
"""

from __future__ import annotations

import json
import os
import pathlib
import stat
from dataclasses import dataclass, field
from typing import Sequence

from .common import register_temp, unregister_temp

OK = "ok"
UNSUPPORTED = "unsupported"
IO_ERROR = "io_error"


@dataclass
class MergeResult:
    status: str
    added: list[str] = field(default_factory=list)
    message: str = ""


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
    tmp = target.with_name(f"{target.name}.tmp.{os.getpid()}")
    register_temp(tmp)
    try:
        tmp.write_bytes(text.encode("utf-8"))
        if target.exists():
            os.chmod(tmp, stat.S_IMODE(target.stat().st_mode))
        os.replace(tmp, target)
    finally:
        if tmp.exists():
            tmp.unlink()
        unregister_temp(tmp)


def merge(target: pathlib.Path, desired: Sequence[str]) -> MergeResult:
    if target.exists():
        # read_bytes, а не read_text: иначе universal newlines съест CRLF
        # и файл с виндовыми переводами строк перепишется в LF.
        try:
            text = target.read_bytes().decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return MergeResult(IO_ERROR, message=str(exc))
        if has_comments(text):
            return MergeResult(UNSUPPORTED)
        try:
            data = json.loads(text) if text.strip() else {}
        except json.JSONDecodeError as exc:
            return MergeResult(UNSUPPORTED, message=str(exc))
    else:
        text = ""
        data = {}

    if not isinstance(data, dict):
        return MergeResult(UNSUPPORTED)

    current = data.get("instructions", [])
    if not isinstance(current, list):
        return MergeResult(UNSUPPORTED)
    if not all(isinstance(entry, str) for entry in current):
        return MergeResult(UNSUPPORTED)

    present = {normalize(entry) for entry in current}
    missing: list[str] = []
    for entry in desired:
        key = normalize(entry)
        if key not in present:
            present.add(key)
            missing.append(entry)
    if not missing:
        return MergeResult(OK)

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

    try:
        write_atomic(target, rendered)
    except OSError as exc:
        return MergeResult(IO_ERROR, message=str(exc))
    return MergeResult(OK, added=missing)
