#!/usr/bin/env python3
"""Запуск тестов agent-kit.

    python3 tests/smoke.py                все тесты
    python3 tests/smoke.py -v             с именами тестов
    python3 tests/smoke.py test_merge     только один модуль

Тесты — обычный `unittest` (`python3 -m unittest discover` тоже работает);
файл оставлен точкой входа, чтобы команда проверки из CI и документации не
менялась.
"""

from __future__ import annotations

import pathlib
import sys
import unittest

TESTS_DIR = pathlib.Path(__file__).resolve().parent
KIT_ROOT = TESTS_DIR.parent

# Импорты `kit` и `tests.support` рассчитаны на корень репозитория в sys.path.
sys.path.insert(0, str(KIT_ROOT))


def split_args(argv: list[str]) -> tuple[str | None, list[str]]:
    """Первый не-флаговый аргумент — имя модуля, остальное — флаги unittest."""
    module = next((arg for arg in argv if not arg.startswith("-")), None)
    flags = [arg for arg in argv if arg.startswith("-")]
    return module, flags


def build_suite(module: str | None) -> unittest.TestSuite:
    loader = unittest.TestLoader()
    if module is None:
        return loader.discover(str(TESTS_DIR), pattern="test_*.py", top_level_dir=str(KIT_ROOT))
    name = module if module.startswith("tests.") else f"tests.{module}"
    return loader.loadTestsFromName(name)


def main(argv: list[str]) -> int:
    module, flags = split_args(argv)
    runner = unittest.TextTestRunner(verbosity=2 if "-v" in flags else 1)
    return 0 if runner.run(build_suite(module)).wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
