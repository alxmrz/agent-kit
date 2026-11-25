"""Юнит-тесты `kit.common`: пути и границы записи."""

from __future__ import annotations

import os
import unittest
from unittest import mock

from kit.common import (
    KitError,
    abspath,
    cleanup_temp_files,
    expand_tilde,
    in_project,
    refuse_symlink,
    register_temp,
    resolve_project_dir,
    unregister_temp,
)
from tests.support import TempDirTestCase


class ExpandTildeTests(unittest.TestCase):
    def test_home_only(self) -> None:
        with mock.patch.dict(os.environ, {"HOME": "/home/user"}):
            self.assertEqual(expand_tilde("~"), "/home/user")

    def test_home_prefix(self) -> None:
        with mock.patch.dict(os.environ, {"HOME": "/home/user"}):
            self.assertEqual(expand_tilde("~/project"), "/home/user/project")

    def test_other_tilde_left_alone(self) -> None:
        self.assertEqual(expand_tilde("~other/x"), "~other/x")

    def test_plain_path_untouched(self) -> None:
        self.assertEqual(expand_tilde("relative/path"), "relative/path")

    def test_missing_home_falls_back(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(expand_tilde("~"), "/nonexistent")
            self.assertEqual(expand_tilde("~/x"), "/nonexistent/x")


class AbspathTests(TempDirTestCase):
    def test_existing_dir_returns_realpath(self) -> None:
        directory = self.tmp / "project"
        directory.mkdir()
        link = self.tmp / "link"
        link.symlink_to(directory)
        self.assertEqual(abspath(str(link)), os.path.realpath(str(directory)))

    def test_missing_dir_returns_none(self) -> None:
        self.assertIsNone(abspath(str(self.tmp / "missing")))

    def test_file_returns_none(self) -> None:
        path = self.tmp / "file"
        path.write_text("x", encoding="utf-8")
        self.assertIsNone(abspath(str(path)))


class ResolveProjectDirTests(TempDirTestCase):
    def test_regular_directory(self) -> None:
        project = self.tmp / "project"
        project.mkdir()
        with mock.patch.dict(os.environ, {"HOME": str(self.tmp / "home")}):
            self.assertEqual(resolve_project_dir(str(project)), os.path.realpath(str(project)))

    def test_missing_directory(self) -> None:
        with self.assertRaisesRegex(KitError, "нет такого каталога"):
            resolve_project_dir(str(self.tmp / "missing"))

    def test_filesystem_root_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "корне файловой системы"):
            resolve_project_dir("/")

    def test_home_rejected(self) -> None:
        home = self.new_dir("home")
        with mock.patch.dict(os.environ, {"HOME": str(home)}):
            with self.assertRaisesRegex(KitError, "не в домашний каталог"):
                resolve_project_dir(str(home))

    def test_home_with_trailing_slash_rejected(self) -> None:
        home = self.new_dir("home")
        with mock.patch.dict(os.environ, {"HOME": str(home) + "/"}):
            with self.assertRaisesRegex(KitError, "не в домашний каталог"):
                resolve_project_dir(str(home))

    def test_tilde_home_rejected(self) -> None:
        home = self.new_dir("home")
        with mock.patch.dict(os.environ, {"HOME": str(home)}):
            with self.assertRaisesRegex(KitError, "не в домашний каталог"):
                resolve_project_dir("~")

    def test_subdirectory_of_home_allowed(self) -> None:
        home = self.new_dir("home")
        project = home / "project"
        project.mkdir()
        with mock.patch.dict(os.environ, {"HOME": str(home)}):
            self.assertEqual(resolve_project_dir(str(project)), os.path.realpath(str(project)))

    def test_missing_home_does_not_break(self) -> None:
        project = self.new_dir("project")
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(resolve_project_dir(str(project)), os.path.realpath(str(project)))


class InProjectTests(unittest.TestCase):
    def test_relative_path_allowed(self) -> None:
        in_project(".agents/rules/x.md")

    def test_parent_traversal_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "путь вне проекта"):
            in_project("../secret")

    def test_parent_traversal_inside_name_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "путь вне проекта"):
            in_project(".agents/../../secret")

    def test_absolute_path_rejected(self) -> None:
        with self.assertRaisesRegex(KitError, "путь вне проекта"):
            in_project("/etc/passwd")


class RefuseSymlinkTests(TempDirTestCase):
    def test_symlink_rejected(self) -> None:
        target = self.tmp / "victim"
        target.write_text("не трогать", encoding="utf-8")
        link = self.tmp / "link"
        link.symlink_to(target)
        with self.assertRaisesRegex(KitError, "симлинк"):
            refuse_symlink(link, "link")

    def test_regular_file_allowed(self) -> None:
        path = self.tmp / "file"
        path.write_text("x", encoding="utf-8")
        refuse_symlink(path, "file")

    def test_missing_path_allowed(self) -> None:
        refuse_symlink(self.tmp / "new", "new")


class TempRegistryTests(TempDirTestCase):
    def test_registered_file_removed(self) -> None:
        path = self.tmp / "temp"
        path.write_text("x", encoding="utf-8")
        register_temp(path)
        cleanup_temp_files()
        self.assertFalse(path.exists())

    def test_registered_symlink_removed(self) -> None:
        victim = self.tmp / "victim"
        victim.write_text("x", encoding="utf-8")
        link = self.tmp / "link"
        link.symlink_to(victim)
        register_temp(link)
        cleanup_temp_files()
        self.assertFalse(link.is_symlink())
        self.assertTrue(victim.exists())

    def test_unregistered_file_kept(self) -> None:
        path = self.tmp / "temp"
        path.write_text("x", encoding="utf-8")
        register_temp(path)
        unregister_temp(path)
        cleanup_temp_files()
        self.assertTrue(path.exists())

    def test_missing_file_does_not_fail(self) -> None:
        register_temp(self.tmp / "gone")
        cleanup_temp_files()


if __name__ == "__main__":
    unittest.main()
