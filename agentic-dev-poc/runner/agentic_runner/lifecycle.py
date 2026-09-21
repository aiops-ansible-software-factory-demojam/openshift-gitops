"""One-run lifecycle. A restart never starts a second model session."""

from __future__ import annotations

import hashlib
import json
import shutil
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable

from .artifacts import collect_tree
from .models import (
    AGENT_SECONDS,
    COLLECT_SECONDS,
    LOG_BYTES,
    PROVISION_SECONDS,
    RETENTION_SECONDS,
    TOTAL_DEADLINE_SECONDS,
    RequestError,
    RunRecord,
)
from .openshell import ExecResult, OpenShellClient, OpenShellError
from .store import Store

Clock = Callable[[], datetime]


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


class Cancelled(Exception):
    pass


class Deadline(Exception):
    def __init__(self, state: str) -> None:
        super().__init__(state)
        self.state = state


@dataclass
class EngineConfig:
    image: str
    policy_path: Path
    policy_hash: str
    config_hash: str
    cpu: str = "2"
    memory: str = "4Gi"
    workdir: str = "/sandbox/work"
    wrapper: str = "/opt/agentic-poc/wrapper.py"


class Engine:
    def __init__(
        self,
        store: Store,
        client: OpenShellClient,
        config: EngineConfig,
        artifact_root: Path,
        clock: Clock = utcnow,
    ) -> None:
        self.store = store
        self.client = client
        self.config = config
        self.artifact_root = artifact_root
        self.clock = clock
        self.artifact_root.mkdir(parents=True, exist_ok=True)

    def accept(
        self, prompt: str, source_execution_id: str, idempotency_key: str
    ) -> tuple[RunRecord, int, bool]:
        digest = _request_hash(prompt, source_execution_id)
        now = self.clock()
        run_id = "poc-" + uuid.uuid4().hex[:12]
        record = {
            "id": run_id,
            "idempotency_key": idempotency_key,
            "request_hash": digest,
            "source_execution_id": source_execution_id,
            "prompt": prompt,
            "state": "accepted",
            "terminal": 0,
            "error": "",
            "cleanup_state": "pending",
            "sandbox_name": run_id,
            "config_hash": self.config.config_hash,
            "image": self.config.image,
            "policy_hash": self.config.policy_hash,
            "created_at": iso(now),
            "updated_at": iso(now),
            "deadline_at": iso(now + timedelta(seconds=TOTAL_DEADLINE_SECONDS)),
            "provision_deadline_at": iso(now + timedelta(seconds=PROVISION_SECONDS)),
            "agent_deadline_at": "",
            "collect_deadline_at": "",
            "agent_exit_code": None,
            "summary": "",
            "validation_json": "",
            "result_json": "",
            "cancel_requested": 0,
            "execution_claimed": 0,
        }
        outcome = self.store.reserve_run(record)
        if outcome == "conflict":
            raise RequestError(409, "idempotency_conflict", "Idempotency key was reused with a different request.")
        if outcome == "busy":
            raise RequestError(409, "busy", "Another run is active or its sandbox cleanup has not finished.")
        if outcome == "replay":
            existing = self.store.get_by_idempotency(idempotency_key)
            if existing is None:
                raise RequestError(500, "persist_failed", "The run could not be stored.")
            return existing, 200, False
        created = self.store.get(run_id)
        if created is None:
            raise RequestError(500, "persist_failed", "The run could not be stored.")
        return created, 202, True

    def claim_execution(self, run_id: str) -> bool:
        return self.store.claim_execution(run_id, iso(self.clock()))

    def request_cancel(self, run_id: str) -> RunRecord:
        run = self._require(run_id)
        if run.terminal:
            return run
        run = self.store.update(run_id, cancel_requested=1, updated_at=iso(self.clock()))
        try:
            try:
                timeout = self._remaining(run.deadline_at, 60)
            except Deadline:
                timeout = 1
            self.client.interrupt(run.sandbox_name, timeout)
        except OpenShellError:
            # The lifecycle's cleanup pass retries and records a visible failure.
            pass
        return self._require(run_id)

    def reconcile_startup(self) -> None:
        """Mark uncertain in-flight work interrupted and delete its sandbox."""
        for run in self.store.list_needs_reconcile():
            if not run.terminal:
                self.store.update(
                    run.id,
                    state="interrupted",
                    terminal=1,
                    error="Runner restarted before the run finished. The model session was not resumed.",
                    updated_at=iso(self.clock()),
                )
            self._cleanup(run.id)
        self._reap_orphans()
        self.enforce_retention()

    def execute(self, run_id: str) -> None:
        if not self.store.start_execution(run_id, iso(self.clock())):
            return
        try:
            self._check_control(run_id, "provisioning")
            self._provision(run_id)
            self._check_control(run_id, "preparing")
            self._prepare(run_id)
            self._check_control(run_id, "running")
            self._run_agent(run_id)
            self._check_control(run_id, "collecting")
            self._collect(run_id)
            self._complete(run_id)
        except Cancelled:
            self._terminal(run_id, "cancelled", "Cancellation was requested.")
        except Deadline as exc:
            self._terminal(run_id, exc.state, f"The run reached its {exc.state.replace('_', ' ')} deadline.")
        except Exception as exc:  # noqa: BLE001
            current = self._require(run_id)
            if current.cancel_requested:
                self._terminal(run_id, "cancelled", "Cancellation was requested.")
            elif self._deadline_reached(current):
                self._terminal(run_id, "timed_out", "The run reached its persisted deadline.")
            else:
                self._terminal(run_id, "failed", _sanitize(str(exc)))
        finally:
            self._cleanup(run_id)
            self.enforce_retention()

    def build_result(self, run_id: str) -> dict[str, object]:
        run = self._require(run_id)
        if not run.terminal:
            raise RequestError(409, "incomplete", "The run is still in progress.")
        if run.result_json:
            payload = json.loads(run.result_json)
        else:
            payload = {
                "run_id": run.id,
                "state": run.state,
                "agent_exit_code": run.agent_exit_code,
                "summary": run.summary,
                "validation": json.loads(run.validation_json) if run.validation_json else {},
                "needs_human_review": True,
                "error": run.error or None,
            }
        payload["run_id"] = run.id
        payload["state"] = run.state
        payload["cleanup"] = {"state": run.cleanup_state}
        payload["artifacts"] = [
            {"id": row["id"], "name": row["name"]} for row in self.store.list_artifacts(run.id)
        ]
        payload["needs_human_review"] = True
        return payload

    def _provision(self, run_id: str) -> None:
        run = self._require(run_id)
        self._ensure_time(run, run.provision_deadline_at, "timed_out")
        labels = {
            "agentic-poc.io/managed": "true",
            "agentic-poc.io/run-id": run.id,
        }
        self.client.create_sandbox(
            run.sandbox_name,
            self.config.image,
            self.config.policy_path,
            self.config.cpu,
            self.config.memory,
            labels,
            self._remaining(run.provision_deadline_at, PROVISION_SECONDS),
        )
        remaining = int((parse_iso(run.provision_deadline_at) - self.clock()).total_seconds())
        self.client.wait_ready(run.sandbox_name, max(1, remaining))

    def _prepare(self, run_id: str) -> None:
        run = self._touch(run_id, "preparing")
        task = {
            "run_id": run.id,
            "prompt": run.prompt,
            "source_execution_id": run.source_execution_id,
        }
        directory = self.artifact_root / run.id
        directory.mkdir(parents=True, exist_ok=True)
        task_path = directory / "task.json"
        task_path.write_text(json.dumps(task, ensure_ascii=False), encoding="utf-8")
        self.client.upload(
            run.sandbox_name,
            task_path,
            "/sandbox/task.json",
            self._remaining(run.deadline_at, 60),
        )

    def _run_agent(self, run_id: str) -> None:
        run = self._touch(run_id, "running")
        agent_deadline = min(
            self.clock() + timedelta(seconds=AGENT_SECONDS),
            parse_iso(run.deadline_at),
        )
        self.store.update(run.id, agent_deadline_at=iso(agent_deadline), updated_at=iso(self.clock()))
        timeout = max(1, int((agent_deadline - self.clock()).total_seconds()))
        result = self.client.exec(
            run.sandbox_name,
            ["python3", self.config.wrapper, "/sandbox/task.json"],
            timeout,
            self.config.workdir,
        )
        self._store_log(run.id, "wrapper.log", result)
        if self.clock() > agent_deadline or self.clock() > parse_iso(run.deadline_at):
            raise Deadline("timed_out")
        self.store.update(run.id, agent_exit_code=result.exit_code, updated_at=iso(self.clock()))

    def _collect(self, run_id: str) -> None:
        run = self._touch(run_id, "collecting")
        collect_deadline = min(
            self.clock() + timedelta(seconds=COLLECT_SECONDS),
            parse_iso(run.deadline_at),
        )
        self.store.update(run.id, collect_deadline_at=iso(collect_deadline))
        if self.clock() > collect_deadline:
            raise Deadline("timed_out")
        download = self.artifact_root / run.id / "download"
        if download.exists():
            for child in sorted(download.rglob("*"), reverse=True):
                if child.is_file() or child.is_symlink():
                    child.unlink()
                elif child.is_dir():
                    child.rmdir()
        self.client.download(
            run.sandbox_name,
            self.config.workdir,
            download,
            self._remaining(iso(collect_deadline), COLLECT_SECONDS),
        )
        if self.clock() > collect_deadline:
            raise Deadline("timed_out")
        report_path = download / "out" / "result.json"
        report: dict[str, object] = {}
        if report_path.is_file():
            report = json.loads(report_path.read_text(encoding="utf-8"))
        archive = self.artifact_root / run.id / "workspace.tar.gz"
        manifest = collect_tree(download, archive)
        (self.artifact_root / run.id / "manifest.json").write_text(
            json.dumps(manifest, indent=2), encoding="utf-8"
        )
        publications = [("workspace", "workspace.tar.gz", archive, "application/gzip")]
        events = download / "out" / "events.ndjson"
        if events.is_file():
            publications.append(("events", "events.ndjson", events, "application/x-ndjson"))
        if report_path.is_file():
            publications.append(("report", "result.json", report_path, "application/json"))
        publications.append(
            (
                "manifest",
                "manifest.json",
                self.artifact_root / run.id / "manifest.json",
                "application/json",
            )
        )
        for _, _, path, _ in publications:
            self._validate_artifact(path)
        for artifact_id, name, path, content_type in publications:
            self._publish(run.id, artifact_id, name, path, content_type)
        current = self.store.get(run.id)
        exit_code = current.agent_exit_code if current else None
        summary = str(report.get("summary") or "")
        validation = report.get("validation") if isinstance(report.get("validation"), dict) else {}
        self.store.update(
            run.id,
            summary=summary[:2000],
            validation_json=json.dumps(validation),
            agent_exit_code=exit_code,
            updated_at=iso(self.clock()),
        )

    def _complete(self, run_id: str) -> None:
        run = self._require(run_id)
        validation = json.loads(run.validation_json) if run.validation_json else {}
        failure = ""
        if run.agent_exit_code != 0:
            failure = f"OpenCode exited with status {run.agent_exit_code}."
        elif validation.get("status") != "passed":
            failure = "Required validation did not pass."
        state = "failed" if failure else "completed"
        self._terminal(run_id, state, failure)
        fresh = self._require(run_id)
        result = {
            "run_id": fresh.id,
            "state": fresh.state,
            "agent_exit_code": fresh.agent_exit_code,
            "summary": fresh.summary,
            "validation": json.loads(fresh.validation_json) if fresh.validation_json else {},
            "needs_human_review": True,
            "cleanup": {"state": fresh.cleanup_state},
        }
        self.store.update(run.id, result_json=json.dumps(result), updated_at=iso(self.clock()))

    def _terminal(self, run_id: str, state: str, error: str) -> None:
        self.store.update(
            run_id,
            state=state,
            terminal=1,
            error=error,
            updated_at=iso(self.clock()),
        )

    def _cleanup(self, run_id: str) -> None:
        run = self.store.get(run_id)
        if run is None:
            return
        self.store.update(run_id, state=run.state if run.terminal else "cleaning", updated_at=iso(self.clock()))
        try:
            self.client.delete(run.sandbox_name, 60)
        except OpenShellError as exc:
            current = self._require(run_id)
            message = current.error or _sanitize(str(exc))
            if "cleanup failed" not in message:
                message = (message + " " if message else "") + "Sandbox cleanup failed."
            self.store.update(run_id, cleanup_state="failed", error=message[:1000], updated_at=iso(self.clock()))
            return
        try:
            inspect_deadline = time.monotonic() + 30
            while self.client.exists(run.sandbox_name, 5):
                if time.monotonic() >= inspect_deadline:
                    self.store.update(
                        run_id,
                        cleanup_state="failed",
                        error=_append_cleanup_error(self._require(run_id).error),
                        updated_at=iso(self.clock()),
                    )
                    return
                time.sleep(1)
        except OpenShellError as exc:
            self.store.update(
                run_id,
                cleanup_state="failed",
                error=_append_cleanup_error(_sanitize(str(exc))),
                updated_at=iso(self.clock()),
            )
            return
        self.store.update(run_id, cleanup_state="complete", updated_at=iso(self.clock()))

    def _reap_orphans(self) -> None:
        known = {run.sandbox_name for run in self.store.list_needs_reconcile()}
        try:
            managed = self.client.list_managed()
        except OpenShellError:
            return
        for name in managed:
            if name not in known:
                try:
                    self.client.delete(name, 60)
                except OpenShellError:
                    continue

    def enforce_retention(self) -> None:
        cutoff = iso(self.clock() - timedelta(seconds=RETENTION_SECONDS))
        for run in self.store.list_expired(cutoff):
            if run.cleanup_state != "complete":
                continue
            directory = self.artifact_root / run.id
            if directory.parent != self.artifact_root or directory.name != run.id:
                continue
            if directory.exists():
                shutil.rmtree(directory)
            self.store.delete_run(run.id)

    def _check_control(self, run_id: str, next_state: str) -> None:
        run = self._require(run_id)
        if run.cancel_requested:
            raise Cancelled
        if self.clock() > parse_iso(run.deadline_at):
            raise Deadline("timed_out")
        del next_state

    def _ensure_time(self, run: RunRecord, deadline: str, state: str) -> None:
        if deadline and self.clock() > parse_iso(deadline):
            raise Deadline(state)
        if self.clock() > parse_iso(run.deadline_at):
            raise Deadline("timed_out")

    def _remaining(self, deadline: str, cap: int) -> int:
        remaining = int((parse_iso(deadline) - self.clock()).total_seconds())
        if remaining <= 0:
            raise Deadline("timed_out")
        return max(1, min(cap, remaining))

    def _deadline_reached(self, run: RunRecord) -> bool:
        deadlines = [run.deadline_at]
        if run.state == "provisioning":
            deadlines.append(run.provision_deadline_at)
        elif run.state == "running" and run.agent_deadline_at:
            deadlines.append(run.agent_deadline_at)
        elif run.state == "collecting" and run.collect_deadline_at:
            deadlines.append(run.collect_deadline_at)
        return any(value and self.clock() >= parse_iso(value) for value in deadlines)

    def _touch(self, run_id: str, state: str) -> RunRecord:
        return self.store.update(run_id, state=state, updated_at=iso(self.clock()))

    def _require(self, run_id: str) -> RunRecord:
        run = self.store.get(run_id)
        if run is None:
            raise RequestError(404, "not_found", "Run not found.")
        return run

    def _store_log(self, run_id: str, name: str, result: ExecResult) -> None:
        text = (result.stdout + ("\n" + result.stderr if result.stderr else ""))[:LOG_BYTES]
        path = self.artifact_root / run_id / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        self._publish(run_id, "wrapper-log", name, path, "text/plain")

    def _publish(self, run_id: str, artifact_id: str, name: str, path: Path, content_type: str) -> None:
        data = self._validate_artifact(path)
        digest = hashlib.sha256(data).hexdigest()
        self.store.add_artifact(
            {
                "id": artifact_id,
                "run_id": run_id,
                "name": name,
                "path": str(path),
                "size": len(data),
                "sha256": digest,
                "content_type": content_type,
                "created_at": iso(self.clock()),
            }
        )

    def _validate_artifact(self, path: Path) -> bytes:
        info = path.lstat()
        if path.is_symlink() or not path.is_file():
            raise RequestError(422, "artifact_rejected", "Artifact is not a regular file.")
        if info.st_size > 100 * 1024 * 1024:
            raise RequestError(422, "artifact_rejected", "Artifact exceeds 100 MiB.")
        data = path.read_bytes()
        if any(
            marker in data
            for marker in (b"OPENSHELL_OIDC_CLIENT_SECRET", b"BEGIN PRIVATE KEY", b"Bearer ")
        ):
            raise RequestError(422, "artifact_rejected", "Artifact contains credential material.")
        return data


def _request_hash(prompt: str, source_execution_id: str) -> str:
    from .models import request_hash

    return request_hash(prompt, source_execution_id)


def _sanitize(message: str) -> str:
    redacted = message.replace("\n", " ")
    for marker in ("Bearer ", "OPENSHELL_OIDC_CLIENT_SECRET"):
        if marker in redacted:
            redacted = "OpenShell operation failed."
    return redacted[:500]


def _append_cleanup_error(message: str) -> str:
    if "cleanup failed" not in message.lower():
        message = (message + " " if message else "") + "Sandbox cleanup failed."
    return message[:1000]


def config_hash(image: str, policy_hash: str, model_id: str) -> str:
    return hashlib.sha256(f"{image}\n{policy_hash}\n{model_id}".encode()).hexdigest()
