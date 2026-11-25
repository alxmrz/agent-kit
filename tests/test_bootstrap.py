"""Интеграционные тесты `bootstrap.sh`: клон, установка и его удаление.

«Origin» — локальный git-репозиторий из текущих исходников kit-а, поэтому
сеть тестам не нужна.
"""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from tests.support import (
    BOOTSTRAP,
    PREFIX,
    TempDirTestCase,
    env_with,
    git_clone,
    make_origin,
    run_bootstrap,
)


class BootstrapTests(TempDirTestCase):
    @classmethod
    def setUpClass(cls) -> None:
        # Один origin на класс: клонирование из git-репозитория небыстрое.
        cls._origin_temp = tempfile.TemporaryDirectory(prefix="agent-kit-origin-")
        cls.origin = make_origin(pathlib.Path(cls._origin_temp.name) / "origin")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._origin_temp.cleanup()

    def setUp(self) -> None:
        super().setUp()
        self.project = self.new_project()

    def bootstrap(self, *args: str, env: dict | None = None):
        environment = env or env_with(AGENT_KIT_REPO=str(self.origin))
        return run_bootstrap(self.project, *args, env=environment)

    def rule(self, name: str) -> pathlib.Path:
        return self.project / f".agents/rules/{PREFIX}_{name}.md"

    def assert_ok(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_installs_and_removes_clone(self) -> None:
        result = self.bootstrap("--with", "php")
        self.assert_ok(result)
        self.assertTrue(self.rule("general_rules").is_file())
        self.assertTrue(self.rule("php_rules").is_file())
        self.assertTrue((self.project / "AGENTS.md").is_file())
        self.assertFalse((self.project / ".agent-kit").exists())

    def test_logs_clone_removal(self) -> None:
        result = self.bootstrap()
        self.assert_ok(result)
        self.assertIn("Клон kit-а удалён", result.stdout)
        self.assertNotIn(".agent-kit/install.py", result.stdout)

    def test_dry_run_keeps_fresh_clone_out_of_project(self) -> None:
        result = self.bootstrap("--dry-run")
        self.assert_ok(result)
        self.assertFalse((self.project / ".agent-kit").exists())
        self.assertFalse((self.project / ".agents").exists())
        self.assertFalse((self.project / "AGENTS.md").exists())

    def test_dry_run_keeps_existing_clone(self) -> None:
        git_clone(self.origin, self.project / ".agent-kit")
        result = self.bootstrap("--offline", "--dry-run")
        self.assert_ok(result)
        self.assertTrue((self.project / ".agent-kit").is_dir())
        self.assertFalse((self.project / ".agents").exists())

    def test_external_kit_dir_not_removed(self) -> None:
        outside = self.new_dir("outside-kit")
        git_clone(self.origin, outside)
        result = self.bootstrap("--offline", env=env_with(AGENT_KIT_DIR=str(outside)))
        self.assert_ok(result)
        self.assertTrue((outside / ".git").is_dir())
        self.assertTrue(self.rule("general_rules").is_file())

    def test_failed_install_keeps_clone(self) -> None:
        result = self.bootstrap("--with", "nope")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.project / ".agent-kit").is_dir())

    def test_retry_reuses_leftover_clone(self) -> None:
        self.bootstrap("--with", "nope")
        result = self.bootstrap("--offline")
        self.assert_ok(result)
        self.assertTrue(self.rule("general_rules").is_file())
        self.assertFalse((self.project / ".agent-kit").exists())

    def test_dirty_clone_kept(self) -> None:
        git_clone(self.origin, self.project / ".agent-kit")
        with (self.project / ".agent-kit/install.py").open("a", encoding="utf-8") as handle:
            handle.write("\n# доработка kit-а\n")
        result = self.bootstrap("--offline")
        self.assert_ok(result)
        self.assertIn(
            "# доработка kit-а",
            (self.project / ".agent-kit/install.py").read_text(encoding="utf-8"),
        )
        self.assertIn("незакоммиченные изменения", result.stdout + result.stderr)

    def test_missing_git_fails(self) -> None:
        shell = shutil.which("sh")
        env = {key: value for key, value in os.environ.items() if key != "PATH"}
        env["PATH"] = "/nonexistent"
        result = subprocess.run(
            [shell, str(BOOTSTRAP)],
            capture_output=True,
            text=True,
            cwd=self.project,
            env=env,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("нужен git", result.stdout + result.stderr)

    def test_existing_non_clone_directory_rejected(self) -> None:
        (self.project / ".agent-kit").mkdir()
        (self.project / ".agent-kit/keep.txt").write_text("x", encoding="utf-8")
        result = self.bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("это не клон agent-kit", result.stdout + result.stderr)
        self.assertTrue((self.project / ".agent-kit/keep.txt").is_file())


if __name__ == "__main__":
    unittest.main()
