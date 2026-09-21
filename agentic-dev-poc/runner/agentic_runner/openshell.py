"""OpenShell CLI client and the operations the runner depends on."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol


class OpenShellError(Exception):
    pass


@dataclass
class ExecResult:
    exit_code: int
    stdout: str
    stderr: str


class OpenShellClient(Protocol):
    def create_sandbox(
        self,
        name: str,
        image: str,
        policy: Path,
        cpu: str,
        memory: str,
        labels: dict[str, str],
    ) -> None: ...

    def wait_ready(self, name: str, timeout_seconds: int) -> None: ...

    def upload(self, name: str, local: Path, dest: str) -> None: ...

    def exec(
        self, name: str, argv: list[str], timeout_seconds: int, workdir: str
    ) -> ExecResult: ...

    def download(self, name: str, remote: str, dest: Path) -> None: ...

    def delete(self, name: str) -> None: ...

    def list_managed(self) -> list[str]: ...


@dataclass
class FakeSandbox:
    name: str
    image: str
    labels: dict[str, str]
    ready: bool = True
    files: dict[str, bytes] = field(default_factory=dict)
    execs: list[list[str]] = field(default_factory=list)
    deleted: bool = False


class FakeOpenShell:
    """In-memory gateway used by unit tests."""

    def __init__(self) -> None:
        self.sandboxes: dict[str, FakeSandbox] = {}
        self.fail_delete: set[str] = set()
        self.created: list[str] = []
        self.before_exec = None

    def create_sandbox(
        self,
        name: str,
        image: str,
        policy: Path,
        cpu: str,
        memory: str,
        labels: dict[str, str],
    ) -> None:
        del policy, cpu, memory
        if name in self.sandboxes and not self.sandboxes[name].deleted:
            raise OpenShellError(f"sandbox {name} already exists")
        self.sandboxes[name] = FakeSandbox(name=name, image=image, labels=labels)
        self.created.append(name)

    def wait_ready(self, name: str, timeout_seconds: int) -> None:
        del timeout_seconds
        sandbox = self.sandboxes.get(name)
        if sandbox is None or sandbox.deleted or not sandbox.ready:
            raise OpenShellError(f"sandbox {name} is not Ready")

    def upload(self, name: str, local: Path, dest: str) -> None:
        sandbox = self._live(name)
        sandbox.files[dest] = local.read_bytes()

    def exec(
        self, name: str, argv: list[str], timeout_seconds: int, workdir: str
    ) -> ExecResult:
        del timeout_seconds, workdir
        sandbox = self._live(name)
        if self.before_exec is not None:
            self.before_exec(name)
        sandbox.execs.append(list(argv))
        report = {
            "summary": "Created the requested module and tests.",
            "agent_exit_code": 0,
            "validation": {
                "status": "passed",
                "commands": [
                    {"command": "python -m unittest discover -s tests -v", "exit_code": 0},
                    {
                        "command": "python -m unittest discover -s /opt/agentic-poc/fixtures -v",
                        "exit_code": 0,
                    },
                ],
                "evidence": "recorded_execution",
            },
        }
        sandbox.files["/sandbox/work/out/result.json"] = json.dumps(report).encode()
        sandbox.files["/sandbox/work/out/events.ndjson"] = b'{"type":"text"}\n'
        sandbox.files["/sandbox/work/slugify.py"] = b"def slugify(text):\n    return text\n"
        return ExecResult(exit_code=0, stdout='{"type":"text"}\n', stderr="")

    def download(self, name: str, remote: str, dest: Path) -> None:
        sandbox = self._live(name)
        dest.mkdir(parents=True, exist_ok=True)
        prefix = remote.rstrip("/") + "/"
        for path, data in sandbox.files.items():
            if path.startswith(prefix):
                relative = path[len(prefix) :]
                target = dest / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)

    def delete(self, name: str) -> None:
        if name in self.fail_delete:
            raise OpenShellError(f"delete failed for {name}")
        sandbox = self.sandboxes.get(name)
        if sandbox is not None:
            sandbox.deleted = True

    def list_managed(self) -> list[str]:
        return [
            name
            for name, sandbox in self.sandboxes.items()
            if not sandbox.deleted and sandbox.labels.get("agentic-poc.io/managed") == "true"
        ]

    def _live(self, name: str) -> FakeSandbox:
        sandbox = self.sandboxes.get(name)
        if sandbox is None or sandbox.deleted:
            raise OpenShellError(f"sandbox {name} is gone")
        return sandbox


class CliOpenShell:
    """Matching OpenShell CLI. Arguments are a list, never a shell string."""

    def __init__(self, binary: str = "openshell", gateway: str = "openshell") -> None:
        self.binary = binary
        self.gateway = gateway

    def create_sandbox(
        self,
        name: str,
        image: str,
        policy: Path,
        cpu: str,
        memory: str,
        labels: dict[str, str],
    ) -> None:
        args = [
            "sandbox",
            "create",
            "--name",
            name,
            "--from",
            image,
            "--detach",
            "--no-tty",
            "--no-auto-providers",
            "--approval-mode",
            "manual",
            "--policy",
            str(policy),
            "--cpu",
            cpu,
            "--memory",
            memory,
        ]
        for key, value in labels.items():
            args.extend(["--label", f"{key}={value}"])
        args.extend(["--", "/bin/sleep", "1200"])
        self._run(args, 180)

    def wait_ready(self, name: str, timeout_seconds: int) -> None:
        completed = self._run(
            ["sandbox", "get", name, "--output", "json"],
            timeout_seconds,
        )
        text = completed.stdout + completed.stderr
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError:
            payload = {}
        phase = ""
        if isinstance(payload, dict):
            phase = str(
                payload.get("phase")
                or payload.get("status")
                or payload.get("state")
                or ""
            )
        if phase.lower() != "ready" and "Ready" not in text:
            raise OpenShellError(f"sandbox {name} is not Ready: {text[-500:]}")

    def upload(self, name: str, local: Path, dest: str) -> None:
        self._run(["sandbox", "upload", name, str(local), dest], 60)

    def exec(
        self, name: str, argv: list[str], timeout_seconds: int, workdir: str
    ) -> ExecResult:
        args = [
            "sandbox",
            "exec",
            "-n",
            name,
            "--no-tty",
            "--timeout",
            str(timeout_seconds),
            "--workdir",
            workdir,
            "--",
            *argv,
        ]
        completed = self._run(args, timeout_seconds + 30, check=False)
        return ExecResult(completed.returncode, completed.stdout, completed.stderr)

    def download(self, name: str, remote: str, dest: Path) -> None:
        dest.mkdir(parents=True, exist_ok=True)
        self._run(["sandbox", "download", name, remote, str(dest)], 60)

    def delete(self, name: str) -> None:
        self._run(["sandbox", "delete", name], 60)

    def list_managed(self) -> list[str]:
        completed = self._run(
            [
                "sandbox",
                "list",
                "--output",
                "json",
                "--selector",
                "agentic-poc.io/managed=true",
            ],
            30,
            check=False,
        )
        if completed.returncode != 0:
            return []
        try:
            payload = json.loads(completed.stdout or "[]")
        except json.JSONDecodeError:
            return []
        names: list[str] = []
        items = payload if isinstance(payload, list) else payload.get("sandboxes", [])
        if isinstance(items, list):
            for item in items:
                if isinstance(item, str):
                    names.append(item)
                elif isinstance(item, dict) and item.get("name"):
                    names.append(str(item["name"]))
        return names

    def _run(
        self, args: list[str], timeout: int, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        command = [self.binary, "-g", self.gateway, *args]
        try:
            completed = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired as exc:
            raise OpenShellError(f"openshell timed out: {' '.join(args[:4])}") from exc
        if check and completed.returncode != 0:
            detail = (completed.stderr or completed.stdout)[-500:]
            raise OpenShellError(detail or f"openshell exited {completed.returncode}")
        return completed
