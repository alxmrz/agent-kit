"""Юнит-тесты `kit.merge`: дополнение instructions[] без потери чужого."""

from __future__ import annotations

import json
import os
import unittest

from kit import merge
from tests.support import TempDirTestCase


class NormalizeTests(unittest.TestCase):
    def test_dot_prefix_stripped(self) -> None:
        self.assertEqual(merge.normalize("./.agents/x"), ".agents/x")

    def test_plain_path_kept(self) -> None:
        self.assertEqual(merge.normalize(".agents/x"), ".agents/x")


class FormatHelpersTests(unittest.TestCase):
    def test_has_comments_line(self) -> None:
        self.assertTrue(merge.has_comments('{\n  // комментарий\n}\n'))

    def test_has_comments_block(self) -> None:
        self.assertTrue(merge.has_comments('{\n  /* block */\n}\n'))

    def test_has_comments_plain_json(self) -> None:
        self.assertFalse(merge.has_comments('{"a": 1}\n'))

    def test_detect_indent_four(self) -> None:
        self.assertEqual(merge.detect_indent('{\n    "a": 1\n}\n'), 4)

    def test_detect_indent_compact(self) -> None:
        self.assertIsNone(merge.detect_indent('{"a": 1}\n'))

    def test_detect_indent_skips_brace_line(self) -> None:
        self.assertEqual(merge.detect_indent('{\n  "a": 1\n}\n'), 2)


class MergeTests(TempDirTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.target = self.tmp / "opencode.json"

    def write(self, text: str) -> None:
        self.target.write_bytes(text.encode("utf-8"))

    def read(self) -> str:
        return self.target.read_bytes().decode("utf-8")

    def test_creates_missing_file(self) -> None:
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.OK)
        self.assertEqual(result.added, ["./.agents/rules/a.md"])
        self.assertEqual(json.loads(self.read()), {"instructions": ["./.agents/rules/a.md"]})

    def test_appends_to_existing_list(self) -> None:
        self.write('{\n  "instructions": ["./docs/own.md"]\n}\n')
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.added, ["./.agents/rules/a.md"])
        data = json.loads(self.read())
        self.assertEqual(data["instructions"], ["./docs/own.md", "./.agents/rules/a.md"])

    def test_foreign_keys_preserved(self) -> None:
        self.write('{"model": "example/model", "instructions": []}\n')
        merge.merge(self.target, ["./.agents/rules/a.md"])
        data = json.loads(self.read())
        self.assertEqual(data["model"], "example/model")

    def test_duplicate_not_added(self) -> None:
        self.write('{"instructions": ["./.agents/rules/a.md"]}\n')
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.OK)
        self.assertEqual(result.added, [])

    def test_duplicate_without_dot_prefix(self) -> None:
        self.write('{"instructions": [".agents/rules/a.md"]}\n')
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.added, [])

    def test_duplicate_inside_single_call(self) -> None:
        result = merge.merge(
            self.target,
            ["./.agents/rules/a.md", "./.agents/rules/a.md"],
        )
        self.assertEqual(result.added, ["./.agents/rules/a.md"])

    def test_nothing_added_file_untouched(self) -> None:
        self.write('{"instructions": ["./.agents/rules/a.md"]}\n')
        old = 1_000_000_000
        os.utime(self.target, (old, old))
        merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(int(self.target.stat().st_mtime), old)

    def test_indent_preserved(self) -> None:
        self.write('{\n    "instructions": []\n}\n')
        merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertIn('    "instructions": [', self.read())

    def test_crlf_preserved(self) -> None:
        self.write('{\r\n  "instructions": []\r\n}\r\n')
        merge.merge(self.target, ["./.agents/rules/a.md"])
        raw = self.target.read_bytes()
        self.assertIn(b"\r\n", raw)
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))
        self.assertIn(b'"./.agents/rules/a.md"', raw)

    def test_compact_json_stays_compact(self) -> None:
        self.write('{"instructions":["./docs/own.md"]}\n')
        merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(self.read().count("\n"), 1)

    def test_missing_instructions_key_added(self) -> None:
        self.write('{\n  "model": "example/model"\n}\n')
        merge.merge(self.target, ["./.agents/rules/a.md"])
        data = json.loads(self.read())
        self.assertEqual(data["instructions"], ["./.agents/rules/a.md"])

    def test_jsonc_is_unsupported_and_untouched(self) -> None:
        text = '{\n  // комментарий\n  "instructions": []\n}\n'
        self.write(text)
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.UNSUPPORTED)
        self.assertEqual(self.read(), text)

    def test_broken_json_is_unsupported(self) -> None:
        text = '{"instructions": [}\n'
        self.write(text)
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.UNSUPPORTED)
        self.assertTrue(result.message)
        self.assertEqual(self.read(), text)

    def test_not_object_is_unsupported(self) -> None:
        self.write("[]\n")
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.UNSUPPORTED)

    def test_instructions_not_list_is_unsupported(self) -> None:
        self.write('{"instructions": "x"}\n')
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.UNSUPPORTED)

    def test_non_string_instruction_is_unsupported(self) -> None:
        self.write('{"instructions": [1]}\n')
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.UNSUPPORTED)

    def test_empty_file_treated_as_object(self) -> None:
        self.write("")
        result = merge.merge(self.target, ["./.agents/rules/a.md"])
        self.assertEqual(result.status, merge.OK)
        self.assertEqual(json.loads(self.read()), {"instructions": ["./.agents/rules/a.md"]})

    def test_no_temp_files_left(self) -> None:
        merge.merge(self.target, ["./.agents/rules/a.md"])
        leftovers = [path.name for path in self.tmp.iterdir() if ".tmp." in path.name]
        self.assertEqual(leftovers, [])


if __name__ == "__main__":
    unittest.main()
