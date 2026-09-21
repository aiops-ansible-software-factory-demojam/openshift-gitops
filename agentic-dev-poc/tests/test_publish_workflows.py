"""Tests for repeatable, TLS-verified AO publication."""

from __future__ import annotations

import importlib.util
import json
import ssl
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).parents[1] / "scripts" / "publish-workflows.py"
SPEC = importlib.util.spec_from_file_location("publish_workflows", SCRIPT_PATH)
assert SPEC and SPEC.loader
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)


class PublishWorkflowTest(unittest.TestCase):
    def test_tls_context_requires_certificate_verification(self) -> None:
        context = publisher.tls_context()
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)

    def test_existing_credential_is_rotated_in_place(self) -> None:
        with patch.object(
            publisher,
            "request",
            side_effect=[
                (200, {"resources": [{"name": "agentic-poc-runner", "id": "cred-1"}]}),
                (200, {"id": "cred-1"}),
            ],
        ) as request:
            self.assertEqual(publisher.credential_id("access", "replacement"), "cred-1")
        self.assertEqual(request.call_args_list[1].args[:2], ("PATCH", "/api/v1/credentials/cred-1"))
        self.assertEqual(request.call_args_list[1].args[3], {"inputs": {"token": "replacement"}})

    def test_existing_workflow_is_updated_instead_of_duplicated(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / "workflow.json"
            workflow.write_text(
                json.dumps({"name": "manual-opencode-poc", "description": "test"}),
                encoding="utf-8",
            )
            with patch.object(publisher, "ROOT", root), patch.object(
                publisher,
                "request",
                side_effect=[
                    (200, {"resources": [{"name": "manual-opencode-poc", "id": "wf-1", "version": 2}]}),
                    (200, {"id": "wf-1", "version": 3}),
                    (201, {"version": 3}),
                    (200, {"name": "manual-opencode-poc"}),
                ],
            ) as request:
                publisher.publish("access", workflow, "cred-1")
            calls = [(call.args[0], call.args[1]) for call in request.call_args_list]
            self.assertIn(("PATCH", "/api/v1/workflows/wf-1"), calls)
            self.assertNotIn(("POST", "/api/v1/workflows"), calls)


if __name__ == "__main__":
    unittest.main()
