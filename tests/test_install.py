"""Интеграционные тесты `install.py`: установка через CLI.

Каждый тест работает в своём одноразовом проекте и запускает установку
отдельным процессом — так проверяется ровно то, что видит пользователь.
"""

from __future__ import annotations

import os
import pathlib
import unittest

from tests.support import (
    KIT_ROOT,
    PREFIX,
    TempDirTestCase,
    env_without_home,
    make_extended_kit,
    read_json,
    run_install,
    run_kit,
    snapshot,
)


class InstallTestCase(TempDirTestCase):
    """Проект + помощник установки в него."""

    def setUp(self) -> None:
        super().setUp()
        self.project = self.new_project()

    def install(self, *args: str, env: dict | None = None):
        return run_install("--dir", str(self.project), *args, env=env)

    def rule(self, name: str) -> pathlib.Path:
        return self.project / f".agents/rules/{PREFIX}_{name}.md"

    def config_text(self) -> str:
        return (self.project / "opencode.json").read_text(encoding="utf-8")

    def assert_ok(self, result) -> None:
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class BaseInstallTests(InstallTestCase):
    def test_installs_prefixed_rule(self) -> None:
        self.assert_ok(self.install())
        self.assertTrue(self.rule("general_rules").is_file())

    def test_installs_skill_with_resource(self) -> None:
        self.assert_ok(self.install())
        skill = self.project / f".agents/skills/{PREFIX}_spec-authoring"
        self.assertTrue((skill / "SKILL.md").is_file())
        self.assertTrue((skill / "references/traceability.md").is_file())

    def test_php_group_not_installed_by_default(self) -> None:
        self.assert_ok(self.install())
        self.assertFalse(self.rule("php_rules").exists())

    def test_no_manifest_written(self) -> None:
        self.assert_ok(self.install())
        self.assertFalse((self.project / ".agents/.alxmrz_kit_manifest.json").exists())

    def test_creates_valid_opencode_json(self) -> None:
        self.assert_ok(self.install())
        data = read_json(self.project / "opencode.json")
        self.assertIsInstance(data, dict)
        self.assertIn(f"./.agents/rules/{PREFIX}_general_rules.md", data["instructions"])

    def test_config_has_no_unselected_group(self) -> None:
        self.assert_ok(self.install())
        self.assertNotIn("php_rules", self.config_text())

    def test_creates_agents_md(self) -> None:
        self.assert_ok(self.install())
        text = (self.project / "AGENTS.md").read_text(encoding="utf-8")
        self.assertNotIn("{{", text)
        self.assertIn(f"{PREFIX}_general_rules.md", text)
        self.assertIn("instructions[]", text)

    def test_does_not_create_gitignore(self) -> None:
        self.assert_ok(self.install())
        self.assertFalse((self.project / ".gitignore").exists())

    def test_base_rule_has_no_php_reference(self) -> None:
        self.assert_ok(self.install())
        self.assertNotIn("php_rules", self.rule("general_rules").read_text(encoding="utf-8"))

    def test_skill_content_untouched(self) -> None:
        self.assert_ok(self.install())
        text = (self.project / f".agents/skills/{PREFIX}_conventional-commit/SKILL.md").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("alxmrz-kit:", text)
        self.assertIn("name: conventional-commit", text.splitlines())


class OverwriteTests(InstallTestCase):
    def test_manual_edit_replaced(self) -> None:
        self.assert_ok(self.install())
        rule = self.rule("general_rules")
        with rule.open("a", encoding="utf-8") as handle:
            handle.write("\n# моя правка\n")
        self.assert_ok(self.install())
        self.assertNotIn("# моя правка", rule.read_text(encoding="utf-8"))

    def test_content_matches_source(self) -> None:
        self.assert_ok(self.install())
        source = KIT_ROOT / "components/base/rules/general_rules.md"
        self.assertEqual(self.rule("general_rules").read_bytes(), source.read_bytes())

    def test_reports_overwrite(self) -> None:
        self.assert_ok(self.install())
        result = self.install()
        self.assertIn("(перезаписан)", result.stdout)


class IdempotencyTests(InstallTestCase):
    def test_second_run_changes_nothing(self) -> None:
        self.assert_ok(self.install())
        before = snapshot(self.project)
        self.assert_ok(self.install())
        self.assertEqual(snapshot(self.project), before)

    def test_second_run_does_not_create_gitignore(self) -> None:
        self.assert_ok(self.install())
        self.assert_ok(self.install())
        self.assertFalse((self.project / ".gitignore").exists())


class ForeignFilesTests(InstallTestCase):
    def test_foreign_skill_preserved(self) -> None:
        own = self.project / ".agents/skills/spec-authoring/SKILL.md"
        own.parent.mkdir(parents=True)
        own.write_text("---\nname: my-own-spec\n---\nМОЁ\n", encoding="utf-8")
        self.assert_ok(self.install())
        self.assertEqual(own.read_text(encoding="utf-8"), "---\nname: my-own-spec\n---\nМОЁ\n")
        self.assertTrue((self.project / f".agents/skills/{PREFIX}_spec-authoring/SKILL.md").is_file())

    def test_foreign_rule_preserved(self) -> None:
        own = self.project / ".agents/rules/general_rules.md"
        own.parent.mkdir(parents=True)
        own.write_text("# мои правила\n", encoding="utf-8")
        self.assert_ok(self.install())
        self.assertEqual(own.read_text(encoding="utf-8"), "# мои правила\n")
        self.assertTrue(self.rule("general_rules").is_file())


class GroupsTests(InstallTestCase):
    def test_with_php_adds_group_and_base(self) -> None:
        self.assert_ok(self.install("--with", "php"))
        self.assertTrue(self.rule("php_rules").is_file())
        self.assertTrue(self.rule("general_rules").is_file())

    def test_php_rule_links_general_rule(self) -> None:
        self.assert_ok(self.install("--with", "php"))
        self.assertIn(f"{PREFIX}_general_rules", self.rule("php_rules").read_text(encoding="utf-8"))

    def test_with_spaces_and_commas(self) -> None:
        self.assert_ok(self.install("--with", " php , "))
        self.assertTrue(self.rule("php_rules").is_file())

    def test_repeated_with_merges_groups(self) -> None:
        kit = make_extended_kit(self.new_dir("kit"))
        result = run_kit(
            kit,
            "--dir",
            str(self.project),
            "--with",
            "php,js",
            "--with",
            "go",
        )
        self.assert_ok(result)
        for group in ("php", "js", "go"):
            self.assertTrue(self.rule(f"{group}_rules").is_file(), group)

    def test_unknown_group_fails(self) -> None:
        result = self.install("--with", "nope")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("есть: base php", result.stdout + result.stderr)

    def test_unknown_group_writes_nothing(self) -> None:
        self.install("--with", "nope")
        self.assertFalse((self.project / ".agents").exists())
        self.assertFalse((self.project / "AGENTS.md").exists())
        self.assertFalse((self.project / ".opencode").exists())


class OpencodeJsonTests(InstallTestCase):
    def test_augments_own_config(self) -> None:
        self.project.joinpath("opencode.json").write_text(
            '{\n    "model": "example/model",\n    "instructions": [\n        "./docs/my_rules.md"\n    ]\n}\n',
            encoding="utf-8",
        )
        result = self.install("--with", "php")
        self.assert_ok(result)
        data = read_json(self.project / "opencode.json")
        self.assertIn(f"./.agents/rules/{PREFIX}_general_rules.md", data["instructions"])
        self.assertIn(f"./.agents/rules/{PREFIX}_php_rules.md", data["instructions"])
        self.assertEqual(data["model"], "example/model")
        self.assertEqual(data["instructions"][0], "./docs/my_rules.md")
        self.assertIn('    "model": "example/model",', self.config_text())
        self.assertIn(f"added: ./.agents/rules/{PREFIX}_general_rules.md", result.stdout)

    def test_repeat_run_does_not_change_config(self) -> None:
        self.assert_ok(self.install("--with", "php"))
        before = (self.project / "opencode.json").read_bytes()
        self.assert_ok(self.install("--with", "php"))
        self.assertEqual((self.project / "opencode.json").read_bytes(), before)

    def test_previous_run_entry_not_removed(self) -> None:
        self.assert_ok(self.install("--with", "php"))
        self.assert_ok(self.install())
        self.assertIn(f"{PREFIX}_php_rules", self.config_text())
        self.assertTrue(self.rule("php_rules").is_file())

    def test_no_duplicate_entries(self) -> None:
        self.assert_ok(self.install("--with", "php"))
        self.assert_ok(self.install("--with", "php"))
        self.assertEqual(self.config_text().count(f"{PREFIX}_general_rules.md"), 1)

    def test_crlf_preserved(self) -> None:
        (self.project / "opencode.json").write_bytes(
            b'{\r\n  "instructions": [\r\n    "./docs/own.md"\r\n  ]\r\n}\r\n'
        )
        self.assert_ok(self.install())
        raw = (self.project / "opencode.json").read_bytes()
        self.assertIn(b"\r\n", raw)
        self.assertIn(b'"./docs/own.md"', raw)

    def test_compact_json_stays_compact(self) -> None:
        (self.project / "opencode.json").write_text(
            '{"instructions":["./docs/own.md"]}\n', encoding="utf-8"
        )
        self.assert_ok(self.install())
        text = self.config_text()
        self.assertEqual(len(text.splitlines()), 1)
        self.assertIn(f"{PREFIX}_general_rules.md", text)

    def test_jsonc_in_opencode_json_untouched(self) -> None:
        path = self.project / "opencode.json"
        text = '{\n  // комментарий\n  "instructions": []\n}\n'
        path.write_text(text, encoding="utf-8")
        result = self.install()
        self.assert_ok(result)
        self.assertEqual(path.read_text(encoding="utf-8"), text)
        self.assertIn("instructions[]", result.stdout + result.stderr)

    def test_opencode_jsonc_blocks_creation(self) -> None:
        jsonc = self.project / "opencode.jsonc"
        jsonc.write_text('{\n  // комментарий\n}\n', encoding="utf-8")
        result = self.install()
        self.assert_ok(result)
        self.assertFalse((self.project / "opencode.json").exists())
        self.assertIn("// комментарий", jsonc.read_text(encoding="utf-8"))
        self.assertIn("instructions[]", result.stdout + result.stderr)

    def test_symlink_config_not_followed(self) -> None:
        victim = self.tmp / "victim-config.json"
        victim.write_text("НЕ ТРОГАТЬ\n", encoding="utf-8")
        (self.project / "opencode.json").symlink_to(victim)
        result = self.install()
        self.assert_ok(result)
        self.assertEqual(victim.read_text(encoding="utf-8"), "НЕ ТРОГАТЬ\n")
        self.assertTrue(self.rule("general_rules").is_file())
        self.assertIn("instructions[]", result.stdout + result.stderr)


class CommandsAndAgentsTests(TempDirTestCase):
    def test_commands_and_agents_installed(self) -> None:
        kit = make_extended_kit(self.new_dir("kit"))
        project = self.new_project()
        result = run_kit(kit, "--dir", str(project))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = project / ".opencode/commands"
        self.assertTrue((commands / f"{PREFIX}_review.md").is_file())
        self.assertTrue((project / f".opencode/agents/{PREFIX}_reviewer.md").is_file())
        self.assertEqual([path.name for path in commands.iterdir()], [f"{PREFIX}_review.md"])

    def test_nested_component_aborts_install(self) -> None:
        kit = make_extended_kit(self.new_dir("kit"))
        nested = kit / "components/base/rules/nested"
        nested.mkdir(parents=True)
        (nested / "x.md").write_text("# вложенный\n", encoding="utf-8")
        project = self.new_project()
        result = run_kit(kit, "--dir", str(project))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("должен быть плоским", result.stdout + result.stderr)


class AgentsMdTests(InstallTestCase):
    def test_own_agents_md_preserved(self) -> None:
        (self.project / "AGENTS.md").write_text("# Мой AGENTS\n", encoding="utf-8")
        self.assert_ok(self.install())
        self.assertEqual((self.project / "AGENTS.md").read_text(encoding="utf-8"), "# Мой AGENTS\n")
        self.assertIn(f"{PREFIX}_general_rules.md", self.config_text())

    def test_edit_survives_reinstall(self) -> None:
        self.assert_ok(self.install())
        with (self.project / "AGENTS.md").open("a", encoding="utf-8") as handle:
            handle.write("\nправка\n")
        self.assert_ok(self.install())
        self.assertIn("правка", (self.project / "AGENTS.md").read_text(encoding="utf-8").splitlines())

    def test_symlink_not_followed(self) -> None:
        victim = self.tmp / "victim-agents.md"
        victim.write_text("НЕ ТРОГАТЬ\n", encoding="utf-8")
        (self.project / "AGENTS.md").symlink_to(victim)
        result = self.install()
        self.assert_ok(result)
        self.assertTrue((self.project / "AGENTS.md").is_symlink())
        self.assertEqual(victim.read_text(encoding="utf-8"), "НЕ ТРОГАТЬ\n")


class GitignoreTests(InstallTestCase):
    def test_not_created(self) -> None:
        self.assert_ok(self.install())
        self.assertFalse((self.project / ".gitignore").exists())

    def test_own_gitignore_preserved_byte_for_byte(self) -> None:
        path = self.project / ".gitignore"
        path.write_bytes(b"vendor/\r\n")
        self.assert_ok(self.install())
        self.assertEqual(path.read_bytes(), b"vendor/\r\n")


class DryRunTests(InstallTestCase):
    def test_writes_nothing(self) -> None:
        result = self.install("--dry-run")
        self.assert_ok(result)
        self.assertFalse((self.project / ".agents").is_dir())
        self.assertFalse((self.project / "AGENTS.md").exists())
        self.assertFalse((self.project / "opencode.json").exists())

    def test_reports_plan(self) -> None:
        result = self.install("--dry-run")
        self.assertIn("(план", result.stdout)


class BoundaryTests(TempDirTestCase):
    def test_home_rejected(self) -> None:
        home = self.new_dir("home")
        result = run_install("--dir", str(home), env=dict(os.environ, HOME=str(home)))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((home / ".agents").exists())

    def test_root_rejected(self) -> None:
        result = run_install("--dir", "/")
        self.assertNotEqual(result.returncode, 0)

    def test_home_with_trailing_slash_rejected(self) -> None:
        home = self.new_dir("home")
        result = run_install("--dir", str(home), env=dict(os.environ, HOME=str(home) + "/"))
        self.assertNotEqual(result.returncode, 0)

    def test_missing_home_env_is_fine(self) -> None:
        project = self.new_project()
        result = run_install("--dir", str(project), env=env_without_home())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_directory_is_clear_error(self) -> None:
        result = run_install("--dir", str(self.tmp / "nope"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("нет такого каталога", result.stdout + result.stderr)

    def test_file_instead_of_directory_rejected(self) -> None:
        path = self.tmp / "file.txt"
        path.write_text("x", encoding="utf-8")
        result = run_install("--dir", str(path))
        self.assertNotEqual(result.returncode, 0)

    def test_symlink_component_component_refused(self) -> None:
        project = self.new_project()
        (project / ".agents/rules").mkdir(parents=True)
        victim = self.tmp / "victim.md"
        victim.write_text("НЕ ТРОГАТЬ\n", encoding="utf-8")
        (project / f".agents/rules/{PREFIX}_general_rules.md").symlink_to(victim)
        result = run_install("--dir", str(project))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(victim.read_text(encoding="utf-8"), "НЕ ТРОГАТЬ\n")


class CliTests(TempDirTestCase):
    def test_help_exits_zero_with_groups(self) -> None:
        result = run_install("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Использование:", result.stdout)
        self.assertIn("доступны: base php", result.stdout)

    def test_unknown_flag_fails(self) -> None:
        result = run_install("--nope")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("неизвестный флаг", result.stdout + result.stderr)

    def test_install_subcommand_is_optional(self) -> None:
        project = self.new_project()
        first = run_install("install", "--dir", str(project))
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertTrue((project / ".agents/rules").is_dir())

    def test_dir_flag_without_value_fails(self) -> None:
        result = run_install("--dir")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("требует значение", result.stdout + result.stderr)

    def test_with_flag_without_value_fails(self) -> None:
        result = run_install("--with")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("требует значение", result.stdout + result.stderr)

    def test_second_positional_argument_rejected(self) -> None:
        result = run_install("--dir", str(self.tmp), "extra")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("лишний аргумент", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
