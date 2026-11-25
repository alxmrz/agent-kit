"""Общие помощники: префикс, вывод, пути и границы записи.

Ошибка поднимает исключение `KitError`, а не завершает процесс из середины
вложенного вызова: вызывающая сторона решает, как о ней сообщить.
"""

from __future__ import annotations

import os
import pathlib
import sys

PREFIX = "alxmrz_kit"

# Временные файлы, которые сейчас пишутся в проекте. Прерывание обязано
# убрать их: имена содержат pid и установкой не подхватываются, но мусор в
# чужом проекте оставлять нельзя.
_TEMP_FILES: set[pathlib.Path] = set()


def register_temp(path: pathlib.Path) -> None:
    _TEMP_FILES.add(path)


def unregister_temp(path: pathlib.Path) -> None:
    _TEMP_FILES.discard(path)


def cleanup_temp_files() -> None:
    """Удалить незавершённые временные файлы (после прерывания или ошибки)."""
    for path in list(_TEMP_FILES):
        try:
            if path.exists() or path.is_symlink():
                path.unlink()
        except OSError:
            pass
        _TEMP_FILES.discard(path)


class KitError(Exception):
    """Ошибка установки: `main` печатает `ERROR:` и возвращает код 1."""


def log(message: str) -> None:
    print(message, flush=True)


def step(message: str) -> None:
    print(f"\n== {message}", flush=True)


def ok(message: str) -> None:
    print(f"  OK    {message}", flush=True)


def skip(message: str) -> None:
    print(f"  SKIP  {message}", flush=True)


def warn(message: str) -> None:
    print(f"  WARN  {message}", file=sys.stderr, flush=True)


def die(message: str) -> None:
    raise KitError(message)


def expand_tilde(value: str) -> str:
    """Раскрывает `~` и `~/...` в путях из аргументов.

    Без этого `--dir '~'` попадал бы в проверку каталога как литеральное "~".
    """
    if value == "~":
        return os.environ.get("HOME") or "/nonexistent"
    if value.startswith("~/"):
        home = os.environ.get("HOME") or "/nonexistent"
        return os.path.join(home, value[2:])
    return value


def abspath(value: str) -> str | None:
    """Абсолютный канонический путь к существующему каталогу."""
    path = pathlib.Path(value)
    if not path.is_dir():
        return None
    return os.path.realpath(path)


def resolve_project_dir(value: str) -> str:
    """Каталог проекта: только он и его подкаталоги.

    Домашний каталог и корень файловой системы запрещены.
    """
    directory = abspath(expand_tilde(value))
    if directory is None:
        die(f"нет такого каталога: {value}")
    if directory == "/":
        die("отказываюсь работать в корне файловой системы")

    # HOME может быть не задан или задан со слешем на конце, поэтому
    # сравниваем канонические пути, а не строки.
    home_value = os.environ.get("HOME") or ""
    if home_value:
        home = abspath(home_value)
        if home is not None and directory == home:
            die(f"kit ставится только внутрь проекта, не в домашний каталог: {directory}")

    return directory


def in_project(rel: str) -> None:
    """Копирование пишется только внутрь проекта: `..` и абсолютные пути запрещены."""
    if rel.startswith("/") or ".." in rel:
        die(f"путь вне проекта запрещён: {rel}")


def refuse_symlink(path: pathlib.Path | str, label: str) -> None:
    """Симлинк на месте файла kit-а означает запись в чужое место.

    Отказываемся, а не перезаписываем: `os.replace` заменил бы симлинк.
    """
    if os.path.islink(path):
        die(f"{label}: это симлинк; kit не пишет через симлинки (уберите файл вручную)")
