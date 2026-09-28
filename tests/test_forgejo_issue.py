"""Exercise the issue-to-PR flow without a live Forgejo instance."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "cluster/omnigent/image/forgejo-issue.py"
SPEC = importlib.util.spec_from_file_location("forgejo_issue", SCRIPT)
forgejo_issue = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(forgejo_issue)


class ForgejoIssueTests(unittest.TestCase):
    def test_start_reads_issue_and_uses_clean_remote(self):
        with tempfile.TemporaryDirectory() as scratch:
            workspace = Path(scratch)
            calls = []

            def git(_directory, *args, capture=False):
                calls.append(args)
                if args[:3] == ("remote", "get-url", "origin"):
                    return "http://forgejo.internal/demo-owner/ansible-collection-demo.git"
                if args[:2] == ("branch", "--format=%(refname:short)"):
                    return "main"
                return ""

            with patch.dict("os.environ", {
                "FORGEJO_URL": "http://forgejo.internal",
                "FORGEJO_TOKEN": "private-token",
            }), patch.object(forgejo_issue.Path, "cwd", return_value=workspace), \
                    patch.object(forgejo_issue, "api", return_value={
                        "title": "Feature", "body": "Acceptance criteria", "state": "open"
                    }), patch.object(forgejo_issue, "git", side_effect=git):
                forgejo_issue.checkout(7)

            self.assertIn(("clone", "http://forgejo.internal/demo-owner/ansible-collection-demo.git", str(workspace / "issue-7")), calls)
            self.assertIn(("checkout", "-b", "issue-7", "origin/main"), calls)
            self.assertNotIn("private-token", repr(calls))

    def test_submit_pushes_and_creates_pr_linked_to_issue(self):
        with tempfile.TemporaryDirectory() as scratch:
            workspace = Path(scratch)
            body_file = workspace / "pr.md"
            body_file.write_text("Verified ansible-lint and role behavior.\n")
            calls = []

            def git(_directory, *args, capture=False):
                calls.append(args)
                if args[:3] == ("remote", "get-url", "origin"):
                    return "http://forgejo.internal/demo-owner/ansible-collection-demo.git"
                if args[:2] == ("branch", "--show-current"):
                    return "issue-7"
                if args[:2] == ("rev-list", "--count"):
                    return "1"
                return ""

            def api(_method, path, body=None):
                if path.endswith("/issues/7"):
                    return {"title": "Feature", "state": "open"}
                if "/pulls?" in path:
                    return []
                self.assertEqual(body["head"], "issue-7")
                self.assertEqual(body["base"], "main")
                self.assertIn("Closes #7", body["body"])
                return {"html_url": "https://forgejo.example/pr/1"}

            with patch.dict("os.environ", {"FORGEJO_URL": "http://forgejo.internal"}), \
                    patch.object(forgejo_issue.Path, "cwd", return_value=workspace), \
                    patch.object(forgejo_issue, "git", side_effect=git), \
                    patch.object(forgejo_issue, "api", side_effect=api):
                forgejo_issue.submit(7, body_file)

            self.assertIn(("push", "-u", "origin", "issue-7"), calls)


if __name__ == "__main__":
    unittest.main()
