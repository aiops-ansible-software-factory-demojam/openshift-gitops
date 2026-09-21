"""Runner API and lifecycle tests."""

from __future__ import annotations

import json
import os
import ssl
import threading
import unittest
import urllib.error
import urllib.request
from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory

from agentic_runner.api import ApiServer
from agentic_runner.artifacts import collect_tree
from agentic_runner.lifecycle import Engine, EngineConfig, iso, parse_iso
from agentic_runner.models import RequestError
from agentic_runner.openshell import FakeOpenShell
from agentic_runner.store import Store


TOKEN = "test-token"


class RunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        root = Path(self.tmp.name)
        self.policy = root / "policy.yaml"
        self.policy.write_text("version: 1\nnetwork_policies: {}\n", encoding="utf-8")
        self.store = Store(root / "runner.sqlite")
        self.client = FakeOpenShell()
        self.engine = Engine(
            self.store,
            self.client,
            EngineConfig(
                image="example.com/opencode@sha256:abc",
                policy_path=self.policy,
                policy_hash="policy",
                config_hash="config",
            ),
            root / "artifacts",
        )
        self.autostart = False
        self.server = ApiServer(("127.0.0.1", 0), self.engine, TOKEN, self._start, lambda: True)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address[:2]
        self.base = f"http://127.0.0.1:{port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.store.close()
        self.tmp.cleanup()

    def _start(self, run_id: str) -> None:
        if self.autostart:
            threading.Thread(target=self.engine.execute, args=(run_id,), daemon=True).start()

    def request(self, method: str, path: str, body: dict | None = None, token: str = TOKEN, headers: dict | None = None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Authorization", f"Bearer {token}")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        for key, value in (headers or {}).items():
            request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, json.loads(response.read().decode())
        except urllib.error.HTTPError as exc:
            payload = exc.read().decode()
            return exc.code, json.loads(payload) if payload else {}

    def test_health_has_no_secret_or_prompt(self) -> None:
        status, body = self.request("GET", "/healthz", token="")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"status": "ok"})
        self.assertNotIn(TOKEN, json.dumps(body))

    def test_auth_and_prompt_limits(self) -> None:
        status, _ = self.request("POST", "/v1/runs", {"prompt": "hello"}, token="nope", headers={"Idempotency-Key": "a"})
        self.assertEqual(status, 401)
        status, body = self.request("POST", "/v1/runs", {"prompt": "  "}, headers={"Idempotency-Key": "b"})
        self.assertEqual(status, 400)
        status, body = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "x", "image": "evil"},
            headers={"Idempotency-Key": "c"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(body["error"], "unexpected_field")

    def test_idempotency_busy_and_encoding(self) -> None:
        prompt = "quotes \" ' \n unicode café $(rm -rf /) `id` ; &&"
        status, first = self.request(
            "POST",
            "/v1/runs",
            {"prompt": prompt, "source_execution_id": "exec-1"},
            headers={"Idempotency-Key": "exec-1"},
        )
        self.assertEqual(status, 202)
        self.assertFalse(first["terminal"])
        status, again = self.request(
            "POST",
            "/v1/runs",
            {"prompt": prompt, "source_execution_id": "exec-1"},
            headers={"Idempotency-Key": "exec-1"},
        )
        self.assertIn(status, (200, 202))
        self.assertEqual(again["run_id"], first["run_id"])
        self.assertEqual(self.client.created, [])
        status, _ = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "different"},
            headers={"Idempotency-Key": "exec-1"},
        )
        self.assertEqual(status, 409)
        status, busy = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "second"},
            headers={"Idempotency-Key": "exec-2"},
        )
        self.assertEqual(status, 409)
        self.assertEqual(busy["error"], "busy")
        self.engine.execute(first["run_id"])
        uploaded = self.client.sandboxes[first["run_id"]].files["/sandbox/work/task.json"]
        self.assertEqual(json.loads(uploaded)["prompt"], prompt)
        joined = " ".join(sum(self.client.sandboxes[first["run_id"]].execs, []))
        self.assertNotIn(prompt, joined)
        self.assertEqual(self.client.created.count(first["run_id"]), 1)

    def test_restart_does_not_resume_model_session(self) -> None:
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "make slugify"},
            headers={"Idempotency-Key": "restart"},
        )
        self.assertEqual(status, 202)
        before = len(self.client.created)
        self.engine.reconcile_startup()
        run = self.store.get(created["run_id"])
        self.assertIsNotNone(run)
        assert run is not None
        self.assertEqual(run.state, "interrupted")
        self.assertTrue(run.terminal)
        self.assertEqual(len(self.client.created), before)
        self.assertNotIn(created["run_id"], self.client.sandboxes)

    def test_cancel_and_cleanup_failure_blocks_next_run(self) -> None:
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "work"},
            headers={"Idempotency-Key": "cancel"},
        )
        self.assertEqual(status, 202)
        self.client.fail_delete.add(created["run_id"])
        self.client.before_exec = lambda name: self.engine.request_cancel(created["run_id"])
        self.engine.execute(created["run_id"])
        run = self.store.get(created["run_id"])
        assert run is not None
        self.assertEqual(run.state, "cancelled")
        self.assertEqual(run.cleanup_state, "failed")
        status, blocked = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "next"},
            headers={"Idempotency-Key": "next"},
        )
        self.assertEqual(status, 409)
        self.assertEqual(blocked["error"], "busy")

    def test_artifact_rejection(self) -> None:
        root = Path(self.tmp.name) / "tree"
        root.mkdir()
        (root / "ok.txt").write_text("hello", encoding="utf-8")
        outside = Path(self.tmp.name) / "secret.txt"
        outside.write_text("nope", encoding="utf-8")
        (root / "escape").symlink_to(outside)
        with self.assertRaises(RequestError):
            collect_tree(root, Path(self.tmp.name) / "out.tar.gz")

    def test_deadline_is_absolute(self) -> None:
        moment = {"now": self.engine.clock()}
        self.engine.clock = lambda: moment["now"]
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "late"},
            headers={"Idempotency-Key": "late"},
        )
        self.assertEqual(status, 202)
        moment["now"] = moment["now"] + timedelta(seconds=20 * 60 + 5)
        self.engine.execute(created["run_id"])
        run = self.store.get(created["run_id"])
        assert run is not None
        self.assertEqual(run.state, "timed_out")
        self.assertLess(parse_iso(run.deadline_at), self.engine.clock())
        self.assertEqual(iso(parse_iso(run.deadline_at)), run.deadline_at)


if __name__ == "__main__":
    unittest.main()
