"""Рендеринг компонентов kit в целевой проект.

Правила, скиллы, команды и агенты получают префикс в имени, поэтому не
сталкиваются с одноимёнными пользовательскими файлами. Ссылки внутри
kit-файлов приводятся к префиксованным путям, чтобы оставаться рабочими.
"""

from __future__ import annotations

import os
import pathlib
import re
import stat

from .common import PREFIX, die, refuse_symlink, register_temp, unregister_temp

# Порядок важен: сначала «docs/…», потом голые имена с ограничением слева.
# Ограничение слева — явный ASCII-класс, а не `\w`: `\w` в Python по умолчанию
# Unicode, и кириллица рядом со ссылкой изменила бы поведение.
_REF_RULES = (
    (
        re.compile(r"docs/php_rules\.md"),
        f".agents/rules/{PREFIX}_php_rules.md",
    ),
    (
        re.compile(r"docs/general_rules\.md"),
        f".agents/rules/{PREFIX}_general_rules.md",
    ),
    (
        re.compile(r"(^|[^/.A-Za-z0-9_-])php_rules\.md", re.MULTILINE),
        rf"\1.agents/rules/{PREFIX}_php_rules.md",
    ),
    (
        re.compile(r"(^|[^/.A-Za-z0-9_-])general_rules\.md", re.MULTILINE),
        rf"\1.agents/rules/{PREFIX}_general_rules.md",
    ),
    (
        re.compile(r"\.agents/skills/spec-authoring"),
        f".agents/skills/{PREFIX}_spec-authoring",
    ),
)


def rewrite_refs(text: str) -> str:
    """Исходные имена правил -> префиксованные пути в проекте.

    `\\r` не трогаем, поэтому CRLF в компонентах остаётся.
    """
    for pattern, replacement in _REF_RULES:
        text = pattern.sub(replacement, text)
    return text


def write_if_changed(path: pathlib.Path, data: bytes, mode: int) -> None:
    """Атомарная запись с пропуском неизменного содержимого.

    Сравнение именно байтовое: иначе у неизменённого файла дёргался бы mtime
    на каждом запуске. Временный файл лежит рядом с целевым и удаляется в
    `finally`, поэтому обрыв не оставляет мусора.
    """
    if path.is_file() and not path.is_symlink():
        try:
            if path.read_bytes() == data:
                return
        except OSError:
            pass

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    register_temp(tmp)
    try:
        tmp.write_bytes(data)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()
        unregister_temp(tmp)


def copy_component(
    components_dir: pathlib.Path,
    project_dir: pathlib.Path,
    src: str,
    dst: str,
) -> None:
    """Скопировать компонент с переписанными ссылками.

    Права доступа берутся у источника: у `scripts/` рядом со `SKILL.md` они
    бывают исполняемыми.
    """
    source = components_dir / src
    target = project_dir / dst
    refuse_symlink(target, dst)

    try:
        data = source.read_bytes()
    except OSError:
        die(f"не удалось прочитать {src}")

    rendered = rewrite_refs(data.decode("utf-8")).encode("utf-8")
    try:
        mode = stat.S_IMODE(source.stat().st_mode)
    except OSError:
        die(f"не удалось прочитать {src}")

    write_if_changed(target, rendered, mode)
