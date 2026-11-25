#!/usr/bin/env python3
"""agent-kit: шаблонные файлы для работы с ИИ внутри проекта.

    python3 install.py [install] [флаги]   поставить или обновить файлы kit-а

Файлы создаются только внутри проекта. Домашний каталог и глобальные
настройки агентов не читаются и не изменяются.
"""

from __future__ import annotations

import sys

# Клон kit-а не должен пачкаться кешем модулей: bootstrap.sh удаляет клон
# только если в нём нет незакоммиченных изменений, а `kit/__pycache__`
# выглядел бы как мусор в рабочем дереве.
sys.dont_write_bytecode = True

import os  # noqa: E402
import pathlib  # noqa: E402
import re  # noqa: E402
import signal  # noqa: E402
import stat  # noqa: E402
from dataclasses import dataclass, field  # noqa: E402

from kit import components, merge, render  # noqa: E402
from kit.common import (  # noqa: E402
    PREFIX,
    KitError,
    cleanup_temp_files,
    die,
    in_project,
    log,
    ok,
    refuse_symlink,
    resolve_project_dir,
    skip,
    step,
    warn,
)

KIT_ROOT = pathlib.Path(__file__).resolve().parent
COMPONENTS_DIR = KIT_ROOT / "components"
TEMPLATE = KIT_ROOT / "snippets" / "AGENTS.md.tmpl"
BASE_GROUP = components.BASE_GROUP


def read_version() -> str:
    try:
        return (KIT_ROOT / "VERSION").read_text(encoding="utf-8").strip()
    except OSError:
        die("не удалось прочитать VERSION")


def usage(version: str) -> None:
    print(f"agent-kit {version}")
    print()
    print("Использование:")
    print("  python3 install.py [install] [флаги]   поставить или обновить файлы kit-а")
    print()
    print("Флаги:")
    print("  --dir <каталог>      целевой проект (по умолчанию текущий каталог)")
    print("  --with <группы>      дополнительные группы через запятую, можно повторять")
    print(f"                       (группа base ставится всегда; доступны: {components.group_names(COMPONENTS_DIR)})")
    print("  --dry-run            показать план, ничего не записывая")
    print("  -h, --help           эта справка")
    print()
    print("Что появляется в проекте:")
    print(f"  .agents/rules/{PREFIX}_<имя>.md")
    print(f"  .agents/skills/{PREFIX}_<id>/")
    print(f"  .opencode/commands/{PREFIX}_<имя>.md")
    print(f"  .opencode/agents/{PREFIX}_<имя>.md")
    print("  AGENTS.md              (только если его ещё нет)")
    print("  opencode.json          (instructions[] с правилами base и выбранных групп)")


@dataclass
class Options:
    project_dir: str = ""
    groups: list[str] = field(default_factory=list)
    dry_run: bool = False


def append_groups(options: Options, value: str) -> None:
    """`--with`: режется по запятым и пробелам, пустые куски пропускаются."""
    for item in re.split(r"[,\s]+", value):
        if item:
            options.groups.append(item)


def parse_args(argv: list[str], version: str) -> Options:
    options = Options()
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "install":
            pass
        elif arg == "--dir":
            if index + 1 >= len(argv):
                die("--dir требует значение")
            options.project_dir = argv[index + 1]
            index += 1
        elif arg == "--with":
            if index + 1 >= len(argv):
                die("--with требует значение")
            append_groups(options, argv[index + 1])
            index += 1
        elif arg == "--dry-run":
            options.dry_run = True
        elif arg in ("-h", "--help"):
            usage(version)
            raise SystemExit(0)
        elif arg.startswith("-"):
            die(f"неизвестный флаг: {arg} (см. --help)")
        elif not options.project_dir:
            options.project_dir = arg
        else:
            die(f"лишний аргумент: {arg}")
        index += 1
    return options


def validate_groups(selected: list[str]) -> list[str]:
    """Проверка выбора групп до первой записи.

    Неизвестная группа не должна оставить в проекте половину файлов.
    """
    unique = sorted(set(selected))
    for group in unique:
        if not components.group_exists(COMPONENTS_DIR, group):
            die(f"неизвестная группа: {group} (есть: {components.group_names(COMPONENTS_DIR)})")
    return sorted({BASE_GROUP, *unique})


def install_file(project_dir: pathlib.Path, rel: str, src: str, dry_run: bool) -> None:
    """Перезапись безусловная: содержимое всегда берётся из components/."""
    dst = project_dir / rel
    if dry_run:
        if dst.is_symlink():
            warn(f"{rel} (план: это симлинк, установка откажется писать)")
        elif dst.is_file():
            ok(f"{rel} (план: перезаписать)")
        else:
            ok(f"{rel} (план)")
        return
    refuse_symlink(dst, rel)
    existed = dst.is_file()
    render.copy_component(COMPONENTS_DIR, project_dir, src, rel)
    if existed:
        ok(f"{rel} (перезаписан)")
    else:
        ok(rel)


def install_components(project_dir: pathlib.Path, groups: list[str], dry_run: bool) -> list[str]:
    step(f"Компоненты (группы: {' '.join(groups)})")
    targets: list[str] = []
    for src in components.list_sources(COMPONENTS_DIR, groups):
        rel = components.target_path(PREFIX, src)
        in_project(rel)
        targets.append(rel)
        install_file(project_dir, rel, src, dry_run)
    return targets


def install_agents_md(project_dir: pathlib.Path, dry_run: bool) -> None:
    step("AGENTS.md")
    dst = project_dir / "AGENTS.md"

    if dst.exists() or dst.is_symlink():
        skip("AGENTS.md (уже есть; kit его не перезаписывает)")
        return
    if dry_run:
        ok("AGENTS.md (план: создать из шаблона)")
        return

    try:
        text = TEMPLATE.read_text(encoding="utf-8")
        mode = stat.S_IMODE(TEMPLATE.stat().st_mode)
    except OSError as exc:
        die(f"не удалось прочитать шаблон AGENTS.md: {exc}")
    data = text.replace("{{TEST_CMD}}", "команда запуска тестов").encode("utf-8")
    render.write_if_changed(dst, data, mode)
    ok("AGENTS.md (создан из шаблона)")
    warn("AGENTS.md: заполните разделы TODO — дальше kit его не трогает")


def instructions_list(targets: list[str]) -> list[str]:
    """Пути поставленных правил в виде, пригодном для instructions[]."""
    return [f"./{rel}" for rel in targets if rel.startswith(".agents/rules/")]


def print_instructions_hint(instructions: list[str]) -> None:
    """Пути правил для ручного добавления в opencode.json."""
    log("        Добавьте в instructions[] opencode.json:")
    for entry in instructions:
        log(f'          "{entry}",')


def install_opencode_json(project_dir: pathlib.Path, targets: list[str], dry_run: bool) -> None:
    """opencode.json: в instructions[] добавляются правила base и выбранных групп.

    Чужое содержимое и форматирование сохраняются (см. kit/merge.py).
    opencode.jsonc не трогаем: комментарии JSONC ломают разбор.
    """
    step("opencode.json")
    instructions = instructions_list(targets)
    if not instructions:
        skip("opencode.json (правил нет)")
        return

    # JSONC не правим: комментарии ломают разбор, а два конфига рядом
    # сделали бы правку `opencode.json` бесполезной.
    if (project_dir / "opencode.jsonc").exists():
        skip("opencode.jsonc: комментарии не дают править файл автоматически")
        print_instructions_hint(instructions)
        return

    # Симлинк — чужое место: не пишем по нему. Это не ошибка установки:
    # остальные файлы kit-а уже поставлены.
    target = project_dir / "opencode.json"
    if target.is_symlink():
        skip("opencode.json (симлинк; не трогаем)")
        print_instructions_hint(instructions)
        return

    if dry_run:
        if target.is_file():
            ok("opencode.json (план: дополнить instructions[])")
        else:
            ok("opencode.json (план: создать с instructions[])")
        return

    result = merge.merge(target, instructions)
    if result.status == merge.OK:
        for entry in result.added:
            log(f"        added: {entry}")
        ok("opencode.json (instructions[] актуален)")
    else:
        if result.message:
            for line in result.message.splitlines():
                log(f"        {line}")
        warn("opencode.json: слияние не удалось, файл не изменён")
        print_instructions_hint(instructions)


def cmd_install(options: Options, version: str) -> None:
    project = pathlib.Path(resolve_project_dir(options.project_dir or "."))
    step(f"agent-kit {version} -> {project}")
    if options.dry_run:
        log("  режим: dry-run, изменения не записываются")

    groups = validate_groups(options.groups)

    targets = install_components(project, groups, options.dry_run)
    install_agents_md(project, options.dry_run)
    install_opencode_json(project, targets, options.dry_run)

    step("Готово")
    if os.environ.get("AGENT_KIT_EPHEMERAL") == "1":
        # Клона, из которого запускался install.py, в проекте уже нет:
        # обновление снова идёт через bootstrap.sh.
        log("  Обновить:  снова запустить bootstrap.sh с теми же флагами")
    else:
        log(f'  Обновить:  python3 {KIT_ROOT / "install.py"} --dir "{project}"')
    if not (project / "openspec").is_dir():
        log("  OpenSpec:  openspec init . --tools opencode")


def _interrupt(signum: int, frame: object) -> None:
    raise KeyboardInterrupt


def main(argv: list[str]) -> int:
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, _interrupt)
    try:
        version = read_version()
        options = parse_args(argv, version)
        cmd_install(options, version)
    except KitError as exc:
        cleanup_temp_files()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        cleanup_temp_files()
        return 130
    finally:
        cleanup_temp_files()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
