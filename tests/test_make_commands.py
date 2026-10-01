"""Make's public interface must be safe to discover and sequence helpers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAKE = shutil.which("make")


class MakeCommandsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copy(ROOT / "Makefile", self.root / "Makefile")
        self.log = self.root / "calls"
        binary = self.root / "bin"
        binary.mkdir()
        for name in ("oc", "curl", "python3", "ansible", "yq", "jq"):
            path = binary / name
            path.write_text('#!/bin/sh\necho forbidden >> "$CALL_LOG"\nexit 99\n')
            path.chmod(0o755)
        self.env = {"PATH": f"{binary}:/usr/bin:/bin", "HOME": str(self.root),
                    "CALL_LOG": str(self.log)}
        (self.root / ".env").write_text('echo env-loaded >> "$CALL_LOG"\nexit 99\n')
        for parent, names in (("scripts", ("feature-demo.sh", "dispatch-issue.sh", "webapp-demo.sh", "reset-demo.sh")),
                              ("bootstrap", ("bootstrap.sh", "sandbox-image.sh", "preflight.sh", "aap-configure.sh"))):
            directory = self.root / parent
            directory.mkdir()
            for name in names:
                (directory / name).write_text(
                    f'#!/bin/sh\nprintf "%s\\n" "{name} $*" >> "$CALL_LOG"\n'
                    + ('exit "${HYDRATE_RESULT:-0}"\n' if name == "feature-demo.sh" else 'exit 0\n'))

    def make(self, *args):
        return subprocess.run([MAKE, *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True)

    def test_bare_make_and_help_only_print_existing_commands(self):
        for args in ((), ("help",)):
            result = self.make(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("make preflight", result.stdout)
            self.assertIn("make demo ISSUE=N", result.stdout)
            for absent in ("make check", "make test", "make build", "make check-aap", "make test-molecule"):
                self.assertNotIn(absent, result.stdout)
        self.assertFalse(self.log.exists())

    def test_invalid_issue_fails_before_either_helper(self):
        for value in (None, "", "0", "00", "-1", "abc", "1 2", "1; echo injected"):
            with self.subTest(value=value):
                result = self.make("demo", *([] if value is None else ["ISSUE=" + value]))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("positive issue number", result.stderr)
                self.assertFalse(self.log.exists())

    def test_demo_hydrates_then_dispatches_and_stops_on_hydration_failure(self):
        result = self.make("demo", "ISSUE=42")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["feature-demo.sh hydrate", "dispatch-issue.sh 42"])
        self.log.unlink()
        self.env["HYDRATE_RESULT"] = "7"
        self.assertNotEqual(self.make("demo", "ISSUE=42").returncode, 0)
        self.assertEqual(self.log.read_text().splitlines(), ["feature-demo.sh hydrate"])

    def test_aliases_and_existing_commands_forward_to_scripts(self):
        for target, expected in (
            ("bootstrap", "bootstrap.sh "), ("sandbox-build", "sandbox-image.sh "),
            ("demo-hydrate", "feature-demo.sh hydrate"), ("preflight", "preflight.sh "),
            ("aap-configure", "aap-configure.sh "), ("aap-sync", "webapp-demo.sh sync"),
            ("webapp-create", "webapp-demo.sh create"), ("webapp-nginx", "webapp-demo.sh nginx"),
            ("webapp-delete", "webapp-demo.sh delete"), ("webapp-verify", "webapp-demo.sh verify"),
            ("demo-reset", "reset-demo.sh --confirm-demo-reset"),
        ):
            with self.subTest(target=target):
                self.assertEqual(self.make(target).returncode, 0)
                self.assertEqual(self.log.read_text().splitlines()[-1], expected)
