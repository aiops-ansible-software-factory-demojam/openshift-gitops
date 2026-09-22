"""Runner API and lifecycle tests."""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import tarfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from agentic_runner.api import ApiServer
from agentic_runner.artifacts import collect_tree, extract_bounded_tar
from agentic_runner.lifecycle import Engine, EngineConfig, iso, parse_iso
from agentic_runner.models import RequestError
from agentic_runner.openshell import (
    CliOpenShell,
    FakeOpenShell,
    OpenShellError,
    _bounded_communicate,
    _receive_bounded,
)
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
        self.start_calls: list[str] = []
        self.server = ApiServer(
            ("127.0.0.1", 0), self.engine, TOKEN, self._start, lambda: True
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address[:2]
        self.base = f"http://127.0.0.1:{port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.store.close()
        self.tmp.cleanup()

    def _start(self, run_id: str) -> None:
        self.start_calls.append(run_id)
        if self.autostart:
            threading.Thread(
                target=self.engine.execute, args=(run_id,), daemon=True
            ).start()

    def request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        token: str = TOKEN,
        headers: dict | None = None,
    ):
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

    def test_readiness_polls_exact_structured_phase(self) -> None:
        client = CliOpenShell()
        pending = subprocess.CompletedProcess(
            [],
            0,
            json.dumps({"metadata": {"name": "demo"}, "status": {"phase": "Pending"}}),
            "",
        )
        ready = subprocess.CompletedProcess(
            [],
            0,
            json.dumps({"metadata": {"name": "demo"}, "status": {"phase": "Ready"}}),
            "",
        )
        with patch.object(client, "_run", side_effect=[pending, ready]) as run, patch(
            "agentic_runner.openshell.time.sleep"
        ):
            client.wait_ready("demo", 5)
        self.assertEqual(run.call_count, 2)

    def test_auth_and_prompt_limits(self) -> None:
        status, _ = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "hello"},
            token="nope",
            headers={"Idempotency-Key": "a"},
        )
        self.assertEqual(status, 401)
        status, body = self.request(
            "POST", "/v1/runs", {"prompt": "  "}, headers={"Idempotency-Key": "b"}
        )
        self.assertEqual(status, 400)
        status, body = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "x", "image": "evil"},
            headers={"Idempotency-Key": "c"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(body["error"], "unexpected_field")

    def test_active_http_retry_launches_once_and_preserves_encoding(self) -> None:
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
        self.assertEqual(status, 200)
        self.assertEqual(again["run_id"], first["run_id"])
        self.assertEqual(self.start_calls, [first["run_id"]])
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
        uploaded = self.client.sandboxes[first["run_id"]].files["/sandbox/task.json"]
        self.assertEqual(json.loads(uploaded)["prompt"], prompt)
        joined = " ".join(sum(self.client.sandboxes[first["run_id"]].execs, []))
        self.assertNotIn(prompt, joined)
        self.assertEqual(self.client.created.count(first["run_id"]), 1)

    def test_three_sequential_runs_share_database_and_deliver_project_files(
        self,
    ) -> None:
        run_ids = []
        for number in range(3):
            status, created = self.request(
                "POST",
                "/v1/runs",
                {"prompt": f"run {number}"},
                headers={"Idempotency-Key": f"sequential-{number}"},
            )
            self.assertEqual(status, 202)
            self.engine.execute(created["run_id"])
            result = self.engine.build_result(created["run_id"])
            self.assertEqual(result["state"], "completed")
            run_ids.append(created["run_id"])
            workspace = self.store.get_artifact(created["run_id"], "workspace")
            assert workspace is not None
            with tarfile.open(workspace["path"], "r:gz") as archive:
                self.assertIn("slugify.py", archive.getnames())
        self.assertEqual(len(set(run_ids)), 3)
        self.assertEqual(len(self.client.created), 3)

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
        self.assertFalse(self.client.exists(created["run_id"], 1))

    def test_cancellation_interrupts_active_execution(self) -> None:
        self.autostart = True
        self.client.block_exec = True
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "work"},
            headers={"Idempotency-Key": "active-cancel"},
        )
        self.assertEqual(status, 202)
        self.assertTrue(self.client.exec_started.wait(2))
        status, _ = self.request("POST", f"/v1/runs/{created['run_id']}/cancel")
        self.assertEqual(status, 202)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            run = self.store.get(created["run_id"])
            if run and run.terminal and run.cleanup_state != "pending":
                break
            time.sleep(0.01)
        assert run is not None
        self.assertEqual(run.state, "cancelled")
        self.assertEqual(run.cleanup_state, "complete")

    def test_cleanup_failure_blocks_next_run(self) -> None:
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "work"},
            headers={"Idempotency-Key": "cancel"},
        )
        self.assertEqual(status, 202)
        self.client.fail_delete.add(created["run_id"])
        self.engine.execute(created["run_id"])
        run = self.store.get(created["run_id"])
        assert run is not None
        self.assertEqual(run.state, "failed")
        self.assertTrue(run.terminal)
        self.assertEqual(run.cleanup_state, "failed")
        result = self.engine.build_result(created["run_id"])
        self.assertEqual(result["state"], "failed")
        self.assertIn("cleanup failed", str(result["error"]).lower())
        self.assertIn("delete failed", str(result["error"]).lower())
        status, blocked = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "next"},
            headers={"Idempotency-Key": "next"},
        )
        self.assertEqual(status, 409)
        self.assertEqual(blocked["error"], "busy")

    def test_delayed_cleanup_cannot_be_reported_as_success(self) -> None:
        self.client.block_delete = True
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "work"},
            headers={"Idempotency-Key": "delayed-cleanup"},
        )
        self.assertEqual(status, 202)
        worker = threading.Thread(target=self.engine.execute, args=(created["run_id"],))
        worker.start()
        self.assertTrue(self.client.delete_started.wait(2))
        pending = self.store.get(created["run_id"])
        assert pending is not None
        self.assertEqual(pending.state, "cleaning")
        self.assertFalse(pending.terminal)
        with self.assertRaises(RequestError):
            self.engine.build_result(created["run_id"])
        self.client.delete_released.set()
        worker.join(2)
        self.assertEqual(
            self.engine.build_result(created["run_id"])["state"], "completed"
        )
        workflow = json.loads(
            (
                Path(__file__).parents[1] / "workflows/manual-opencode-poc.json"
            ).read_text()
        )
        classify = next(node for node in workflow["nodes"] if node["id"] == "classify")
        condition = classify["parameters"]["cases"][0]["condition"]
        self.assertIn("cleanup.state", condition)

    def test_artifact_rejection(self) -> None:
        root = Path(self.tmp.name) / "tree"
        root.mkdir()
        (root / "ok.txt").write_text("hello", encoding="utf-8")
        outside = Path(self.tmp.name) / "secret.txt"
        outside.write_text("nope", encoding="utf-8")
        (root / "escape").symlink_to(outside)
        with self.assertRaises(RequestError):
            collect_tree(root, Path(self.tmp.name) / "out.tar.gz")

        escape = root / "escape"
        escape.unlink()
        oversized = root / "oversized.bin"
        with oversized.open("wb") as stream:
            stream.truncate(100 * 1024 * 1024 + 1)
        with self.assertRaises(RequestError):
            collect_tree(root, Path(self.tmp.name) / "oversized.tar.gz")

        oversized.unlink()
        fifo = root / "special"
        os.mkfifo(fifo)
        with self.assertRaises(RequestError):
            collect_tree(root, Path(self.tmp.name) / "special.tar.gz")

        fifo.unlink()
        (root / "leak.txt").write_text(
            "Authorization: Bearer disclosed", encoding="utf-8"
        )
        with self.assertRaises(RequestError):
            collect_tree(root, Path(self.tmp.name) / "credential.tar.gz")

    def test_inspection_failure_is_not_successful_cleanup(self) -> None:
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "work"},
            headers={"Idempotency-Key": "inspect-failure"},
        )
        self.assertEqual(status, 202)
        self.client.fail_inspect = True
        self.engine.execute(created["run_id"])
        run = self.store.get(created["run_id"])
        assert run is not None
        self.assertEqual(run.cleanup_state, "failed")
        self.assertEqual(run.state, "failed")

    def test_gateway_not_found_and_malformed_inventory_fail_closed(self) -> None:
        client = CliOpenShell()
        gateway_error = subprocess.CompletedProcess([], 1, "", "gateway not found")
        with patch.object(client, "_run", return_value=gateway_error):
            with self.assertRaises(OpenShellError):
                client.exists("owned-sandbox", 1)
        absent = subprocess.CompletedProcess(
            [], 1, "", 'status: NotFound, message: "sandbox not found"'
        )
        with patch.object(client, "_run", return_value=absent):
            self.assertFalse(client.exists("owned-sandbox", 1))
        malformed = subprocess.CompletedProcess([], 0, "{}", "")
        with patch.object(client, "_run", return_value=malformed):
            with self.assertRaises(OpenShellError):
                client.list_managed()

    def test_failed_owned_orphan_reconciliation_blocks_readiness_and_admission(
        self,
    ) -> None:
        self.client.create_sandbox(
            "owned-orphan",
            "image",
            self.policy,
            "1",
            "1Gi",
            {"agentic-poc.io/managed": "true"},
            1,
        )
        self.client.create_sandbox("unrelated", "image", self.policy, "1", "1Gi", {}, 1)
        self.client.fail_delete.add("owned-orphan")
        self.engine.reconcile_startup()
        self.assertFalse(self.engine.ready())
        self.assertTrue(self.client.exists("owned-orphan", 1))
        self.assertTrue(self.client.exists("unrelated", 1))
        with self.assertRaises(RequestError) as caught:
            self.engine.accept("next", "", "blocked-by-orphan")
        self.assertEqual(caught.exception.code, "reconciliation_pending")

    def test_inventory_retry_recovers_readiness_after_transient_failure(self) -> None:
        with patch.object(
            self.client,
            "list_managed",
            side_effect=[OpenShellError("transient inventory failure"), []],
        ) as inventory:
            self.engine.reconcile_startup()
        self.assertEqual(inventory.call_count, 2)
        self.assertTrue(self.engine.ready())

    def test_persistent_inventory_failure_blocks_readiness(self) -> None:
        with patch.object(
            self.client,
            "list_managed",
            side_effect=OpenShellError("persistent inventory failure"),
        ) as inventory:
            self.engine.reconcile_startup()
        self.assertEqual(inventory.call_count, 3)
        self.assertFalse(self.engine.ready())
        with self.assertRaises(RequestError) as caught:
            self.engine.accept("next", "", "blocked-by-inventory")
        self.assertEqual(caught.exception.code, "reconciliation_pending")

    def test_observed_exit_and_required_validation_control_outcome(self) -> None:
        self.client.exec_exit_code = 7
        self.client.report_exit_code = 0
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "fail honestly"},
            headers={"Idempotency-Key": "truth-exit"},
        )
        self.assertEqual(status, 202)
        self.engine.execute(created["run_id"])
        result = self.engine.build_result(created["run_id"])
        self.assertEqual(result["state"], "failed")
        self.assertEqual(result["agent_exit_code"], 7)

        self.client.exec_exit_code = 0
        self.client.validation_status = "failed"
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "validation fails"},
            headers={"Idempotency-Key": "truth-validation"},
        )
        self.assertEqual(status, 202)
        self.engine.execute(created["run_id"])
        self.assertEqual(self.engine.build_result(created["run_id"])["state"], "failed")

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

    def test_persisted_agent_deadline_is_checked_after_blocking_exec(self) -> None:
        moment = {"now": self.engine.clock()}
        self.engine.clock = lambda: moment["now"]
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "slow"},
            headers={"Idempotency-Key": "slow-agent"},
        )
        self.assertEqual(status, 202)

        def expire(_name: str) -> None:
            run = self.store.get(created["run_id"])
            assert run is not None and run.agent_deadline_at
            moment["now"] = parse_iso(run.agent_deadline_at) + timedelta(seconds=1)

        self.client.before_exec = expire
        self.engine.execute(created["run_id"])
        run = self.store.get(created["run_id"])
        assert run is not None
        self.assertEqual(run.state, "timed_out")

    def test_artifact_primary_key_migrates_to_run_scope(self) -> None:
        root = Path(self.tmp.name)
        legacy_path = root / "legacy.sqlite"
        connection = sqlite3.connect(legacy_path)
        connection.executescript("""
            CREATE TABLE runs (
              id TEXT PRIMARY KEY, idempotency_key TEXT NOT NULL UNIQUE,
              request_hash TEXT NOT NULL, source_execution_id TEXT NOT NULL,
              prompt TEXT NOT NULL, state TEXT NOT NULL, terminal INTEGER NOT NULL,
              error TEXT NOT NULL DEFAULT '', cleanup_state TEXT NOT NULL,
              sandbox_name TEXT NOT NULL, config_hash TEXT NOT NULL, image TEXT NOT NULL,
              policy_hash TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              deadline_at TEXT NOT NULL, provision_deadline_at TEXT NOT NULL,
              agent_deadline_at TEXT NOT NULL DEFAULT '', collect_deadline_at TEXT NOT NULL DEFAULT '',
              agent_exit_code INTEGER, summary TEXT NOT NULL DEFAULT '',
              validation_json TEXT NOT NULL DEFAULT '', result_json TEXT NOT NULL DEFAULT '',
              cancel_requested INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE artifacts (
              id TEXT PRIMARY KEY, run_id TEXT NOT NULL, name TEXT NOT NULL, path TEXT NOT NULL,
              size INTEGER NOT NULL, sha256 TEXT NOT NULL, content_type TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            """)
        connection.close()
        migrated = Store(legacy_path)
        columns = migrated._db.execute("PRAGMA table_info(artifacts)").fetchall()
        self.assertEqual(
            [
                row["name"]
                for row in sorted(columns, key=lambda row: row["pk"])
                if row["pk"]
            ],
            ["run_id", "id"],
        )
        self.assertIn(
            "execution_claimed",
            [row["name"] for row in migrated._db.execute("PRAGMA table_info(runs)")],
        )
        self.assertIn(
            "artifacts_expired",
            [row["name"] for row in migrated._db.execute("PRAGMA table_info(runs)")],
        )
        migrated.close()

    def test_retention_removes_only_expired_clean_runs(self) -> None:
        moment = {"now": self.engine.clock()}
        self.engine.clock = lambda: moment["now"]
        status, created = self.request(
            "POST",
            "/v1/runs",
            {"prompt": "retain briefly"},
            headers={"Idempotency-Key": "retention"},
        )
        self.assertEqual(status, 202)
        self.engine.execute(created["run_id"])
        artifact_dir = self.engine.artifact_root / created["run_id"]
        self.assertTrue(artifact_dir.exists())
        moment["now"] += timedelta(days=8)
        self.engine.enforce_retention()
        retained = self.store.get(created["run_id"])
        self.assertIsNotNone(retained)
        assert retained is not None
        self.assertTrue(retained.artifacts_expired)
        self.assertEqual(retained.prompt, "")
        self.assertFalse(artifact_dir.exists())
        replay, status, is_new = self.engine.accept("retain briefly", "", "retention")
        self.assertEqual((replay.id, status, is_new), (created["run_id"], 200, False))
        self.assertTrue(self.engine.build_result(replay.id)["artifacts_expired"])
        with self.assertRaises(RequestError) as caught:
            self.engine.accept("changed", "", "retention")
        self.assertEqual(caught.exception.code, "idempotency_conflict")

        reopened = Store(Path(self.tmp.name) / "runner.sqlite")
        try:
            restarted = Engine(
                reopened, FakeOpenShell(), self.engine.config, self.engine.artifact_root
            )
            replay, status, is_new = restarted.accept("retain briefly", "", "retention")
            self.assertEqual(
                (replay.id, status, is_new), (created["run_id"], 200, False)
            )
            self.assertEqual(restarted.client.created, [])
        finally:
            reopened.close()

    def test_tar_is_validated_before_materializing_unsafe_content(self) -> None:
        archive = Path(self.tmp.name) / "unsafe.tar"
        outside = Path(self.tmp.name) / "outside.txt"
        outside.write_text("must not be read", encoding="utf-8")
        with tarfile.open(archive, "w") as stream:
            link = tarfile.TarInfo("out/result.json")
            link.type = tarfile.SYMTYPE
            link.linkname = str(outside)
            stream.addfile(link)
        destination = Path(self.tmp.name) / "received"
        with patch.object(
            Path, "read_bytes", side_effect=AssertionError("outside file read")
        ):
            with self.assertRaises(RequestError):
                extract_bounded_tar(archive, destination)
        self.assertFalse(destination.exists())

    def test_oversized_receive_is_stopped_before_extraction(self) -> None:
        destination = Path(self.tmp.name) / "bounded.tar"
        process = subprocess.Popen(
            [
                "python3",
                "-c",
                "import sys,time; sys.stdout.buffer.write(b'x'*8192); sys.stdout.flush(); time.sleep(30)",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        with self.assertRaises(OpenShellError):
            _receive_bounded(process, destination, 2, 1024)
        self.assertFalse(destination.exists())
        self.assertIsNotNone(process.poll())

    def test_timeout_reaps_child_and_descendant_after_streams_close(self) -> None:
        child_pid = Path(self.tmp.name) / "child.pid"
        descendant_pid = Path(self.tmp.name) / "descendant.pid"
        script = (
            "import os,subprocess,time; "
            f"open({str(child_pid)!r},'w').write(str(os.getpid())); "
            f"p=subprocess.Popen(['python3','-c',\"import os,time; open({str(descendant_pid)!r},'w').write(str(os.getpid())); time.sleep(30)\"]); "
            "d=os.open('/dev/null',os.O_WRONLY); os.dup2(d,1); os.dup2(d,2); time.sleep(30)"
        )
        process = subprocess.Popen(
            ["python3", "-c", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        with self.assertRaises(subprocess.TimeoutExpired):
            _bounded_communicate(process, 1)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and not descendant_pid.exists():
            time.sleep(0.01)
        for pid_path in (child_pid, descendant_pid):
            self.assertTrue(pid_path.exists())
            pid = int(pid_path.read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)


if __name__ == "__main__":
    unittest.main()
