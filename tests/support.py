"""Общие помощники тестов: пути kit-а, вывод, одноразовые каталоги и CLI.

Тесты не пишут в репозиторий: каждый тест получает свой каталог в системном
`tempfile`, который удаляется после теста (см. `TempDirTestCase`).
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

from kit.common import PREFIX  # noqa: F401 — реэкспорт для тестов

KIT_ROOT = pathlib.Path(__file__).resolve().parent.parent
INSTALL = KIT_ROOT / "install.py"
BOOTSTRAP = KIT_ROOT / "bootstrap.sh"

# Файлы и каталоги, из которых состоит kit. Копия нужна тестам, которые
# меняют компоненты или гоняют bootstrap.sh на локальном «origin».
KIT_ITEMS = ("install.py", "bootstrap.sh", "kit", "components", "snippets", "VERSION")


def run_install(*args: str, cwd: pathlib.Path | None = None, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    """Запуск `install.py` из репозитория отдельным процессом."""
    return subprocess.run(
        [sys.executable, str(INSTALL), *args],
        capture_output=True,
        text=True,
        cwd=cwd,
        env=env,
    )


def run_kit(kit_dir: pathlib.Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    """Запуск `install.py` из копии kit-а (со своим набором компонентов)."""
    return subprocess.run(
        [sys.executable, str(kit_dir / "install.py"), *args],
        capture_output=True,
        text=True,
        env=env,
    )


def run_bootstrap(project: pathlib.Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    """Запуск `bootstrap.sh` в каталоге проекта."""
    return subprocess.run(
        ["sh", str(BOOTSTRAP), *args],
        capture_output=True,
        text=True,
        cwd=project,
        env=env,
    )


def env_with(**overrides: str) -> dict:
    return dict(os.environ, **overrides)


def env_without_home() -> dict:
    return {key: value for key, value in os.environ.items() if key != "HOME"}


def read_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def git_init(path: pathlib.Path) -> None:
    subprocess.run(["git", "-C", str(path), "init", "-q"], check=True, capture_output=True)


def git_clone(origin: pathlib.Path, destination: pathlib.Path) -> None:
    subprocess.run(
        ["git", "clone", "-q", "--depth", "1", str(origin), str(destination)],
        check=True,
        capture_output=True,
    )


def copy_kit(destination: pathlib.Path) -> pathlib.Path:
    """Копия репозитория kit-а без `.git`: база для расширенных и «origin»."""
    destination.mkdir(parents=True, exist_ok=True)
    for item in KIT_ITEMS:
        source = KIT_ROOT / item
        target = destination / item
        if source.is_dir():
            shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy2(source, target)
    return destination


def make_extended_kit(destination: pathlib.Path) -> pathlib.Path:
    """Копия kit-а с группами js/go и новыми командами/агентами.

    Проверяет расширяемость без правки `install.py`: группы и типы компонентов
    подхватываются обходом `components/`.
    """
    copy_kit(destination)
    for group in ("js", "go"):
        rules = destination / "components" / group / "rules"
        rules.mkdir(parents=True)
        (rules / f"{group}_rules.md").write_text(f"# {group}\n", encoding="utf-8")

    commands = destination / "components" / "base" / "commands"
    commands.mkdir(parents=True, exist_ok=True)
    (commands / "review.md").write_text(
        "---\ndescription: review\n---\nСделай ревью.\n", encoding="utf-8"
    )
    agents = destination / "components" / "base" / "agents"
    agents.mkdir(parents=True, exist_ok=True)
    (agents / "reviewer.md").write_text(
        "---\ndescription: reviewer\n---\nТы ревьюер.\n", encoding="utf-8"
    )
    return destination


def make_origin(destination: pathlib.Path) -> pathlib.Path:
    """Локальный git-«origin» из текущих исходников kit-а (сеть не нужна)."""
    copy_kit(destination)
    subprocess.run(["git", "-C", str(destination), "init", "-q", "-b", "main"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(destination), "add", "-A"], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(destination), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"],
        check=True,
        capture_output=True,
    )
    return destination


def build_components(root: pathlib.Path) -> pathlib.Path:
    """Мини-набор `components/`: две группы, плоские каталоги и скилл."""
    files = {
        "base/rules/general_rules.md": "# general\n",
        "base/rules/.gitkeep": "",
        "base/commands/review.md": "---\ndescription: review\n---\nСделай ревью.\n",
        "base/agents/reviewer.md": "---\ndescription: reviewer\n---\nТы ревьюер.\n",
        "base/skills/spec-authoring/SKILL.md": "---\nname: spec-authoring\n---\n",
        "base/skills/spec-authoring/references/trace.md": "# trace\n",
        "php/rules/php_rules.md": "# php\n",
    }
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return root


def snapshot(root: pathlib.Path) -> dict[str, tuple]:
    """Содержимое каталога без `.git`: тип и отпечаток каждого файла/ссылки."""
    entries: dict[str, tuple] = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if ".git" in rel.parts:
            continue
        key = rel.as_posix()
        if path.is_symlink():
            entries[key] = ("link", os.readlink(path))
        elif path.is_file():
            entries[key] = ("file", hashlib.sha256(path.read_bytes()).hexdigest())
        elif path.is_dir():
            entries[key] = ("dir",)
    return entries


class TempDirTestCase(unittest.TestCase):
    """Одноразовый каталог на каждый тест, удаляется после него."""

    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory(prefix="agent-kit-test-")
        self.addCleanup(self._temp.cleanup)
        self.tmp = pathlib.Path(self._temp.name)

    def new_dir(self, name: str) -> pathlib.Path:
        directory = self.tmp / name
        directory.mkdir(parents=True, exist_ok=True)
        return directory

    def new_project(self, name: str = "project", git: bool = True) -> pathlib.Path:
        directory = self.new_dir(name)
        if git:
            git_init(directory)
        return directory
