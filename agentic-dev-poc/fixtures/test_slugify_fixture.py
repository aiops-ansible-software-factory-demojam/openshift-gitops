"""Read-only contract checks for slugify. The agent cannot rewrite this file."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, "/sandbox/work")

try:
    from slugify import slugify
except Exception:  # noqa: BLE001
    slugify = None


class SlugifyFixture(unittest.TestCase):
    def test_import(self) -> None:
        self.assertTrue(callable(slugify), "expected slugify(text) in /sandbox/work/slugify.py")

    def test_examples(self) -> None:
        assert slugify is not None
        cases = {
            "Hello, World!": "hello-world",
            "  --Already---slug--  ": "already-slug",
            "": "",
            "...": "",
            "Café au lait": "café-au-lait",
            "a\nb\tc": "a-b-c",
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(slugify(text), expected)

    def test_fixture_is_outside_workdir(self) -> None:
        self.assertTrue(str(Path(__file__).resolve()).startswith("/opt/agentic-poc/fixtures"))


if __name__ == "__main__":
    unittest.main()
