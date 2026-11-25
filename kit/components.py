"""Группы компонентов и раскладка целевых путей.

Группа — каталог `components/<группа>/` с подкаталогами `rules/`, `skills/`,
`commands/`, `agents/`. Подкаталог может отсутствовать. Группа `base` ставится
всегда, языковые подключаются флагом `--with`.

Новый файл внутри подкаталога группы подхватывается без правки скрипта:
список источников собирается обходом `components/`, а не отдельным списком.
"""

from __future__ import annotations

import pathlib

from .common import die

BASE_GROUP = "base"


def list_groups(components_dir: pathlib.Path) -> list[str]:
    """Все группы: имена каталогов в components/, по алфавиту."""
    if not components_dir.is_dir():
        return []
    return sorted(
        entry.name
        for entry in components_dir.iterdir()
        if entry.is_dir()
    )


def group_names(components_dir: pathlib.Path) -> str:
    """Список групп одной строкой через пробел — для сообщений и --help."""
    return " ".join(list_groups(components_dir))


def group_exists(components_dir: pathlib.Path, group: str) -> bool:
    return (components_dir / group).is_dir()


def list_sources(components_dir: pathlib.Path, groups: list[str]) -> list[str]:
    """Пути источников относительно components/, отсортированные.

    Служебные файлы каталога (`.gitkeep` и т. п.) не компоненты и пропускаются.
    """
    sources: set[str] = set()
    for group in groups:
        if not group:
            continue
        group_dir = components_dir / group
        if not group_dir.is_dir():
            die(f"нет группы: {group} (есть: {group_names(components_dir)})")
        try:
            files = [path for path in group_dir.rglob("*") if path.is_file()]
        except OSError:
            die(f"не удалось прочитать {group_dir}")
        for path in files:
            rel = path.relative_to(components_dir).as_posix()
            if rel.rsplit("/", 1)[-1].startswith("."):
                continue
            sources.add(rel)
    return sorted(sources)


def target_path(prefix: str, rel: str) -> str:
    """Путь относительно components/ -> путь относительно проекта.

    `<группа>/rules/<имя>.md`    -> `.agents/rules/<prefix>_<имя>.md`
    `<группа>/skills/<id>/...`   -> `.agents/skills/<prefix>_<id>/...`
    `<группа>/commands/<имя>.md` -> `.opencode/commands/<prefix>_<имя>.md`
    `<группа>/agents/<имя>.md`   -> `.opencode/agents/<prefix>_<имя>.md`

    `rules/`, `commands/` и `agents/` — плоские каталоги файлов: вложенность
    там становится частью имени команды/агента, поэтому это ошибка компонента.
    """
    rest = rel.split("/", 1)[1] if "/" in rel else rel
    kind, _, tail = rest.partition("/")
    if kind in ("rules", "commands", "agents"):
        if "/" in tail:
            die(f"компонент {kind}/ должен быть плоским (без подкаталогов): {rel}")
        directory = {
            "rules": ".agents/rules",
            "commands": ".opencode/commands",
            "agents": ".opencode/agents",
        }[kind]
        return f"{directory}/{prefix}_{tail}"
    if kind == "skills":
        if "/" in tail:
            skill_id, _, inner = tail.partition("/")
            return f".agents/skills/{prefix}_{skill_id}/{inner}"
        return f".agents/skills/{prefix}_{tail}"
    die(f"компонент вне rules/, skills/, commands/ и agents/: {rel}")
