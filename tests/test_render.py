"""Юнит-тесты `kit.render`: переписывание ссылок и атомарная запись."""

from __future__ import annotations

import os
import stat
import unittest

from kit.common import KitError
from kit.render import copy_component, rewrite_refs, write_if_changed
from tests.support import PREFIX, TempDirTestCase, build_components


class RewriteRefsTests(unittest.TestCase):
    def test_docs_general_rules(self) -> None:
        self.assertEqual(
            rewrite_refs("см. docs/general_rules.md"),
            f"см. .agents/rules/{PREFIX}_general_rules.md",
        )

    def test_docs_php_rules(self) -> None:
        self.assertEqual(
            rewrite_refs("см. docs/php_rules.md"),
            f"см. .agents/rules/{PREFIX}_php_rules.md",
        )

    def test_bare_name_after_slash_not_rewritten(self) -> None:
        text = "other/general_rules.md"
        self.assertEqual(rewrite_refs(text), text)

    def test_bare_rule_name(self) -> None:
        self.assertEqual(
            rewrite_refs("открой general_rules.md"),
            f"открой .agents/rules/{PREFIX}_general_rules.md",
        )

    def test_bare_name_after_cyrillic(self) -> None:
        self.assertEqual(
            rewrite_refs("правило:php_rules.md"),
            f"правило:.agents/rules/{PREFIX}_php_rules.md",
        )

    def test_bare_name_glued_to_latin_not_rewritten(self) -> None:
        text = "my_general_rules.md"
        self.assertEqual(rewrite_refs(text), text)

    def test_skill_reference(self) -> None:
        self.assertEqual(
            rewrite_refs("см. .agents/skills/spec-authoring"),
            f"см. .agents/skills/{PREFIX}_spec-authoring",
        )

    def test_crlf_preserved(self) -> None:
        rendered = rewrite_refs("a\r\ndocs/general_rules.md\r\n")
        self.assertIn("\r\n", rendered)
        self.assertIn(f"{PREFIX}_general_rules.md", rendered)

    def test_already_prefixed_path_not_doubled(self) -> None:
        text = f".agents/rules/{PREFIX}_general_rules.md"
        self.assertEqual(rewrite_refs(text), text)


class WriteIfChangedTests(TempDirTestCase):
    def test_creates_file_and_parents(self) -> None:
        target = self.tmp / "deep" / "nested" / "file.md"
        write_if_changed(target, b"data", 0o644)
        self.assertEqual(target.read_bytes(), b"data")

    def test_unchanged_content_keeps_mtime(self) -> None:
        target = self.tmp / "file.md"
        write_if_changed(target, b"data", 0o644)
        old = 1_000_000_000
        os.utime(target, (old, old))
        write_if_changed(target, b"data", 0o644)
        self.assertEqual(int(target.stat().st_mtime), old)

    def test_changed_content_rewritten(self) -> None:
        target = self.tmp / "file.md"
        write_if_changed(target, b"old", 0o644)
        write_if_changed(target, b"new", 0o644)
        self.assertEqual(target.read_bytes(), b"new")

    def test_mode_applied(self) -> None:
        target = self.tmp / "script.sh"
        write_if_changed(target, b"#!/bin/sh\n", 0o755)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)

    def test_no_temp_files_left(self) -> None:
        target = self.tmp / "file.md"
        write_if_changed(target, b"data", 0o644)
        leftovers = [path.name for path in self.tmp.iterdir() if ".tmp." in path.name]
        self.assertEqual(leftovers, [])


class CopyComponentTests(TempDirTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.components = build_components(self.new_dir("components"))
        self.project = self.new_dir("project")

    def test_copies_with_rewritten_refs(self) -> None:
        source = self.components / "php" / "rules" / "php_rules.md"
        source.write_text("общее — в docs/general_rules.md\n", encoding="utf-8")
        copy_component(self.components, self.project, "php/rules/php_rules.md", "out.md")
        self.assertEqual(
            (self.project / "out.md").read_text(encoding="utf-8"),
            f"общее — в .agents/rules/{PREFIX}_general_rules.md\n",
        )

    def test_mode_taken_from_source(self) -> None:
        source = self.components / "base" / "scripts" / "run.sh"
        source.parent.mkdir(parents=True)
        source.write_text("#!/bin/sh\n", encoding="utf-8")
        source.chmod(0o755)
        copy_component(self.components, self.project, "base/scripts/run.sh", "run.sh")
        self.assertEqual(stat.S_IMODE((self.project / "run.sh").stat().st_mode), 0o755)

    def test_missing_source_raises(self) -> None:
        with self.assertRaisesRegex(KitError, "не удалось прочитать"):
            copy_component(self.components, self.project, "base/rules/none.md", "out.md")

    def test_symlink_target_refused(self) -> None:
        victim = self.tmp / "victim"
        victim.write_text("не трогать", encoding="utf-8")
        (self.project / "out.md").symlink_to(victim)
        with self.assertRaisesRegex(KitError, "симлинк"):
            copy_component(self.components, self.project, "base/rules/general_rules.md", "out.md")
        self.assertEqual(victim.read_text(encoding="utf-8"), "не трогать")

    def test_overwrites_existing_file(self) -> None:
        target = self.project / "out.md"
        target.write_text("чужое", encoding="utf-8")
        copy_component(self.components, self.project, "base/rules/general_rules.md", "out.md")
        self.assertEqual(target.read_text(encoding="utf-8"), "# general\n")


if __name__ == "__main__":
    unittest.main()
