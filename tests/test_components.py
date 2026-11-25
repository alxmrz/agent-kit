"""Юнит-тесты `kit.components`: группы и раскладка целевых путей."""

from __future__ import annotations

import unittest

from kit import components
from kit.common import KitError
from tests.support import TempDirTestCase, build_components


class GroupTests(TempDirTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.components = build_components(self.new_dir("components"))

    def test_list_groups_sorted(self) -> None:
        self.assertEqual(components.list_groups(self.components), ["base", "php"])

    def test_list_groups_ignores_files(self) -> None:
        (self.components / "notes.txt").write_text("x", encoding="utf-8")
        self.assertEqual(components.list_groups(self.components), ["base", "php"])

    def test_list_groups_missing_dir(self) -> None:
        self.assertEqual(components.list_groups(self.tmp / "missing"), [])

    def test_group_names_string(self) -> None:
        self.assertEqual(components.group_names(self.components), "base php")

    def test_group_exists(self) -> None:
        self.assertTrue(components.group_exists(self.components, "php"))
        self.assertFalse(components.group_exists(self.components, "js"))


class ListSourcesTests(TempDirTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.components = build_components(self.new_dir("components"))

    def test_base_sources_sorted(self) -> None:
        self.assertEqual(
            components.list_sources(self.components, ["base"]),
            [
                "base/agents/reviewer.md",
                "base/commands/review.md",
                "base/rules/general_rules.md",
                "base/skills/spec-authoring/SKILL.md",
                "base/skills/spec-authoring/references/trace.md",
            ],
        )

    def test_groups_merged(self) -> None:
        sources = components.list_sources(self.components, ["base", "php"])
        self.assertIn("base/rules/general_rules.md", sources)
        self.assertIn("php/rules/php_rules.md", sources)

    def test_dotfiles_skipped(self) -> None:
        self.assertNotIn("base/rules/.gitkeep", components.list_sources(self.components, ["base"]))

    def test_empty_group_name_skipped(self) -> None:
        self.assertEqual(components.list_sources(self.components, [""]), [])

    def test_missing_group_raises(self) -> None:
        with self.assertRaisesRegex(KitError, "нет группы: js"):
            components.list_sources(self.components, ["js"])


class TargetPathTests(unittest.TestCase):
    def test_rule(self) -> None:
        self.assertEqual(
            components.target_path("kit", "php/rules/php_rules.md"),
            ".agents/rules/kit_php_rules.md",
        )

    def test_command(self) -> None:
        self.assertEqual(
            components.target_path("kit", "base/commands/review.md"),
            ".opencode/commands/kit_review.md",
        )

    def test_agent(self) -> None:
        self.assertEqual(
            components.target_path("kit", "base/agents/reviewer.md"),
            ".opencode/agents/kit_reviewer.md",
        )

    def test_skill_entry(self) -> None:
        self.assertEqual(
            components.target_path("kit", "base/skills/spec-authoring/SKILL.md"),
            ".agents/skills/kit_spec-authoring/SKILL.md",
        )

    def test_skill_resource(self) -> None:
        self.assertEqual(
            components.target_path("kit", "base/skills/spec-authoring/references/trace.md"),
            ".agents/skills/kit_spec-authoring/references/trace.md",
        )

    def test_skill_directory_without_file(self) -> None:
        self.assertEqual(
            components.target_path("kit", "base/skills/spec-authoring"),
            ".agents/skills/kit_spec-authoring",
        )

    def test_nested_rule_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "должен быть плоским"):
            components.target_path("kit", "base/rules/nested/x.md")

    def test_nested_command_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "должен быть плоским"):
            components.target_path("kit", "base/commands/nested/x.md")

    def test_nested_agent_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "должен быть плоским"):
            components.target_path("kit", "base/agents/nested/x.md")

    def test_unknown_kind_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "компонент вне"):
            components.target_path("kit", "base/docs/file.md")


if __name__ == "__main__":
    unittest.main()
