"""Exercise run identity and inventory behavior without a cluster or credentials."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


INVENTORY = (
    Path(__file__).resolve().parents[1]
    / "cluster/forgejo/fixtures/collection-template/extensions/molecule/default/inventory/hosts.py"
)


def query(state, *arguments):
    environment = dict(os.environ)
    environment.pop("MOLECULE_EPHEMERAL_DIRECTORY", None)
    if state is not None:
        environment["MOLECULE_EPHEMERAL_DIRECTORY"] = str(state)
    return subprocess.run(
        [sys.executable, str(INVENTORY), *arguments],
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )


class MoleculeInventoryTests(unittest.TestCase):
    def test_lifecycle_queries_keep_the_same_host(self):
        with tempfile.TemporaryDirectory() as state:
            first = query(state, "--list")
            self.assertEqual(first.returncode, 0, first.stderr)
            inventory = json.loads(first.stdout)
            host = inventory["molecule"]["hosts"][0]
            self.assertRegex(host, r"^molecule-[0-9a-f]{16}$")
            for _ in range(4):
                result = query(state, "--list")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), inventory)
            result = query(state, "--host", host)
            self.assertEqual(json.loads(result.stdout), inventory["_meta"]["hostvars"][host])

    def test_separate_sessions_cannot_share_a_host(self):
        with tempfile.TemporaryDirectory() as root:
            hosts = []
            for session in range(4):
                result = query(Path(root) / str(session), "--list")
                self.assertEqual(result.returncode, 0, result.stderr)
                hosts.extend(json.loads(result.stdout)["molecule"]["hosts"])
            self.assertEqual(len(set(hosts)), 4)

    def test_concurrent_inventory_reads_agree_on_the_run(self):
        with tempfile.TemporaryDirectory() as state:
            with ThreadPoolExecutor(max_workers=8) as executor:
                results = list(executor.map(lambda _: query(state, "--list"), range(16)))
            for result in results:
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len({result.stdout for result in results}), 1)

    def test_completed_run_gets_a_new_host(self):
        with tempfile.TemporaryDirectory() as state:
            first = query(state, "--list")
            (Path(state) / "run-id").unlink()
            second = query(state, "--list")
            self.assertNotEqual(first.stdout, second.stdout)

    def test_corrupt_state_fails_without_replacing_the_old_identity(self):
        with tempfile.TemporaryDirectory() as state:
            run_file = Path(state) / "run-id"
            run_file.write_text("old-invalid-identity")
            result = query(state, "--list")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("restore it before destroying", result.stderr)
            self.assertEqual(run_file.read_text(), "old-invalid-identity")

    def test_missing_molecule_context_is_actionable(self):
        result = query(None, "--list")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("collection root", result.stderr)


if __name__ == "__main__":
    unittest.main()
