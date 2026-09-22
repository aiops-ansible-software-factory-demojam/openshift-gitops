"""OpenShell CLI client and the operations the runner depends on."""

from __future__ import annotations

import json
import os
import re
import selectors
import signal
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

from .artifacts import TRANSFER_BYTES, extract_bounded_tar


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
        timeout_seconds: int,
    ) -> None: ...

    def wait_ready(self, name: str, timeout_seconds: int) -> None: ...

    def upload(
        self, name: str, local: Path, dest: str, timeout_seconds: int
    ) -> None: ...

    def exec(
        self, name: str, argv: list[str], timeout_seconds: int, workdir: str
    ) -> ExecResult: ...

    def download(
        self, name: str, remote: str, dest: Path, timeout_seconds: int
    ) -> None: ...

    def interrupt(self, name: str, timeout_seconds: int) -> None: ...

    def delete(self, name: str, timeout_seconds: int) -> None: ...

    def exists(self, name: str, timeout_seconds: int) -> bool: ...

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
        self.exec_started = threading.Event()
        self.exec_released = threading.Event()
        self.block_exec = False
        self.fail_inspect = False
        self.block_delete = False
        self.delete_started = threading.Event()
        self.delete_released = threading.Event()
        self.exec_exit_code = 0
        self.report_exit_code = 0
        self.validation_status = "passed"

    def create_sandbox(
        self,
        name: str,
        image: str,
        policy: Path,
        cpu: str,
        memory: str,
        labels: dict[str, str],
        timeout_seconds: int,
    ) -> None:
        del policy, cpu, memory, timeout_seconds
        if name in self.sandboxes and not self.sandboxes[name].deleted:
            raise OpenShellError(f"sandbox {name} already exists")
        self.sandboxes[name] = FakeSandbox(name=name, image=image, labels=labels)
        self.created.append(name)

    def wait_ready(self, name: str, timeout_seconds: int) -> None:
        del timeout_seconds
        sandbox = self.sandboxes.get(name)
        if sandbox is None or sandbox.deleted or not sandbox.ready:
            raise OpenShellError(f"sandbox {name} is not Ready")

    def upload(self, name: str, local: Path, dest: str, timeout_seconds: int) -> None:
        del timeout_seconds
        sandbox = self._live(name)
        sandbox.files[dest] = local.read_bytes()

    def exec(
        self, name: str, argv: list[str], timeout_seconds: int, workdir: str
    ) -> ExecResult:
        del workdir
        sandbox = self._live(name)
        if self.before_exec is not None:
            self.before_exec(name)
        self.exec_started.set()
        if self.block_exec:
            self.exec_released.wait(timeout_seconds)
            if sandbox.deleted:
                return ExecResult(exit_code=137, stdout="", stderr="sandbox deleted")
        sandbox.execs.append(list(argv))
        report = {
            "summary": "Created the requested module and tests.",
            "reported_agent_exit_code": self.report_exit_code,
            "validation": {
                "status": self.validation_status,
                "commands": [
                    {
                        "command": "python -m unittest discover -s tests -v",
                        "exit_code": 0,
                    },
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
        sandbox.files["/sandbox/work/slugify.py"] = (
            b"def slugify(text):\n    return text\n"
        )
        return ExecResult(
            exit_code=self.exec_exit_code,
            stdout='{"type":"text","part":{"type":"text","text":"done"}}\n',
            stderr="",
        )

    def download(
        self, name: str, remote: str, dest: Path, timeout_seconds: int
    ) -> None:
        del timeout_seconds
        sandbox = self._live(name)
        dest.mkdir(parents=True, exist_ok=True)
        prefix = remote.rstrip("/") + "/"
        for path, data in sandbox.files.items():
            if path.startswith(prefix):
                relative = path[len(prefix) :]
                target = dest / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)

    def interrupt(self, name: str, timeout_seconds: int) -> None:
        self.delete(name, timeout_seconds)

    def delete(self, name: str, timeout_seconds: int) -> None:
        self.delete_started.set()
        if self.block_delete:
            self.delete_released.wait(timeout_seconds)
        if name in self.fail_delete:
            raise OpenShellError(f"delete failed for {name}")
        sandbox = self.sandboxes.get(name)
        if sandbox is not None:
            sandbox.deleted = True
        self.exec_released.set()

    def exists(self, name: str, timeout_seconds: int) -> bool:
        del timeout_seconds
        if self.fail_inspect:
            raise OpenShellError("inspection failed")
        sandbox = self.sandboxes.get(name)
        return sandbox is not None and not sandbox.deleted

    def list_managed(self) -> list[str]:
        if self.fail_inspect:
            raise OpenShellError("inspection failed")
        return [
            name
            for name, sandbox in self.sandboxes.items()
            if not sandbox.deleted
            and sandbox.labels.get("agentic-poc.io/managed") == "true"
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
        self._auth_lock = threading.Lock()

    def create_sandbox(
        self,
        name: str,
        image: str,
        policy: Path,
        cpu: str,
        memory: str,
        labels: dict[str, str],
        timeout_seconds: int,
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
        self._run(args, timeout_seconds)

    def wait_ready(self, name: str, timeout_seconds: int) -> None:
        deadline = time.monotonic() + timeout_seconds
        last_phase = "unknown"
        while time.monotonic() < deadline:
            remaining = max(1, int(deadline - time.monotonic()))
            completed = self._run(
                ["sandbox", "get", name, "--output", "json"],
                min(10, remaining),
                check=False,
            )
            if completed.returncode == 0:
                try:
                    payload = json.loads(completed.stdout)
                except json.JSONDecodeError as exc:
                    raise OpenShellError(
                        "OpenShell returned invalid sandbox JSON"
                    ) from exc
                if not isinstance(payload, dict):
                    raise OpenShellError("OpenShell returned an invalid sandbox object")
                last_phase = _sandbox_phase(payload)
                if last_phase.lower() == "ready":
                    return
                if last_phase.lower() in {"failed", "error", "terminated"}:
                    raise OpenShellError(f"sandbox {name} entered {last_phase}")
            elif _not_found(completed, name):
                raise OpenShellError(
                    f"sandbox {name} disappeared before becoming Ready"
                )
            else:
                raise OpenShellError((completed.stderr or completed.stdout)[-500:])
            time.sleep(min(1, max(0, deadline - time.monotonic())))
        raise OpenShellError(
            f"sandbox {name} did not become Ready (last phase: {last_phase})"
        )

    def upload(self, name: str, local: Path, dest: str, timeout_seconds: int) -> None:
        self._run(["sandbox", "upload", name, str(local), dest], timeout_seconds)

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

    def download(
        self, name: str, remote: str, dest: Path, timeout_seconds: int
    ) -> None:
        started = time.monotonic()
        self._authenticate(timeout_seconds)
        remaining = timeout_seconds - (time.monotonic() - started)
        if remaining <= 0:
            raise OpenShellError("openshell timed out: sandbox exec")
        archive = dest.parent / ".workspace-transfer.tar"
        archive.unlink(missing_ok=True)
        command = [
            self.binary,
            "-g",
            self.gateway,
            "sandbox",
            "exec",
            "-n",
            name,
            "--no-tty",
            "--timeout",
            str(timeout_seconds),
            "--workdir",
            remote,
            "--",
            "python3",
            "-c",
            _BOUNDED_EXPORT_SCRIPT,
        ]
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            stderr = _receive_bounded(process, archive, int(remaining), TRANSFER_BYTES)
            if process.returncode != 0:
                raise OpenShellError(
                    stderr[-500:] or f"openshell exited {process.returncode}"
                )
            extract_bounded_tar(archive, dest)
        finally:
            archive.unlink(missing_ok=True)

    def interrupt(self, name: str, timeout_seconds: int) -> None:
        completed = self._run(["sandbox", "delete", name], timeout_seconds, check=False)
        if completed.returncode != 0 and not _not_found(completed, name):
            raise OpenShellError((completed.stderr or completed.stdout)[-500:])

    def delete(self, name: str, timeout_seconds: int) -> None:
        self.interrupt(name, timeout_seconds)

    def exists(self, name: str, timeout_seconds: int) -> bool:
        completed = self._run(
            ["sandbox", "get", name, "--output", "json"], timeout_seconds, check=False
        )
        if completed.returncode == 0:
            try:
                payload = json.loads(completed.stdout)
            except json.JSONDecodeError as exc:
                raise OpenShellError("OpenShell returned invalid sandbox JSON") from exc
            if not isinstance(payload, dict):
                raise OpenShellError("OpenShell returned an invalid sandbox object")
            observed_name = _sandbox_name(payload) or name
            if observed_name != name:
                raise OpenShellError("OpenShell returned the wrong sandbox")
            return True
        if _not_found(completed, name):
            return False
        raise OpenShellError((completed.stderr or completed.stdout)[-500:])

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
            raise OpenShellError((completed.stderr or completed.stdout)[-500:])
        try:
            payload = json.loads(completed.stdout or "[]")
        except json.JSONDecodeError as exc:
            raise OpenShellError(
                "OpenShell returned invalid sandbox list JSON"
            ) from exc
        names: list[str] = []
        if not isinstance(payload, (list, dict)):
            raise OpenShellError("OpenShell returned an invalid sandbox list")
        if isinstance(payload, dict) and "sandboxes" not in payload:
            raise OpenShellError("OpenShell returned an invalid sandbox list")
        items = payload if isinstance(payload, list) else payload.get("sandboxes")
        if not isinstance(items, list):
            raise OpenShellError("OpenShell returned an invalid sandbox list")
        for item in items:
            if isinstance(item, str) and item:
                names.append(item)
            elif isinstance(item, dict) and _sandbox_name(item):
                names.append(_sandbox_name(item))
            else:
                raise OpenShellError("OpenShell returned an invalid sandbox list item")
        return names

    def _run(
        self, args: list[str], timeout: int, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        started = time.monotonic()
        self._authenticate(timeout)
        remaining = timeout - (time.monotonic() - started)
        if remaining <= 0:
            raise OpenShellError(f"openshell timed out: {' '.join(args[:4])}")
        return self._invoke(args, max(1, int(remaining)), check)

    def _authenticate(self, timeout: int) -> None:
        if not os.environ.get("OPENSHELL_OIDC_CLIENT_SECRET"):
            return
        with self._auth_lock:
            self._invoke(
                ["gateway", "login", self.gateway],
                min(30, max(1, timeout)),
                True,
            )

    def _invoke(
        self, args: list[str], timeout: int, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        command = [self.binary, "-g", self.gateway, *args]
        try:
            process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            stdout, stderr = _bounded_communicate(process, timeout)
            completed = subprocess.CompletedProcess(
                command, process.returncode, stdout, stderr
            )
        except subprocess.TimeoutExpired as exc:
            raise OpenShellError(f"openshell timed out: {' '.join(args[:4])}") from exc
        if check and completed.returncode != 0:
            detail = (completed.stderr or completed.stdout)[-500:]
            raise OpenShellError(detail or f"openshell exited {completed.returncode}")
        return completed


def _bounded_communicate(
    process: subprocess.Popen[bytes], timeout: int, limit: int = 10 * 1024 * 1024
) -> tuple[str, str]:
    selector = selectors.DefaultSelector()
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    assert process.stdout is not None and process.stderr is not None
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    deadline = time.monotonic() + timeout
    completed = False
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(process.args, timeout)
            for key, _ in selector.select(min(1, remaining)):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                buffer = buffers[key.data]
                if len(buffer) < limit:
                    buffer.extend(chunk[: limit - len(buffer)])
        process.wait(timeout=max(0.01, deadline - time.monotonic()))
        completed = True
    except BaseException:
        _terminate_owned_group(process)
        raise
    finally:
        if not completed and process.poll() is None:
            _terminate_owned_group(process)
        selector.close()
        process.stdout.close()
        process.stderr.close()
    return tuple(
        bytes(buffers[name]).decode(errors="replace") for name in ("stdout", "stderr")
    )


def _receive_bounded(
    process: subprocess.Popen[bytes], destination: Path, timeout: int, limit: int
) -> str:
    """Receive a binary stdout stream with a hard byte cap."""
    assert process.stdout is not None and process.stderr is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    deadline = time.monotonic() + timeout
    received = 0
    errors = bytearray()
    completed = False
    try:
        with destination.open("xb") as output:
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(process.args, timeout)
                for key, _ in selector.select(min(1, remaining)):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                    elif key.data == "stdout":
                        received += len(chunk)
                        if received > limit:
                            raise OpenShellError(
                                "Workspace transfer exceeds its bounded receive limit."
                            )
                        output.write(chunk)
                    elif len(errors) < 1024 * 1024:
                        errors.extend(chunk[: 1024 * 1024 - len(errors)])
        process.wait(timeout=max(0.01, deadline - time.monotonic()))
        completed = True
        return errors.decode(errors="replace")
    except BaseException:
        _terminate_owned_group(process)
        destination.unlink(missing_ok=True)
        raise
    finally:
        if not completed and process.poll() is None:
            _terminate_owned_group(process)
        selector.close()
        process.stdout.close()
        process.stderr.close()


def _terminate_owned_group(process: subprocess.Popen[bytes]) -> None:
    """Terminate and reap only the process group created for this command."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.01)
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1)


def _not_found(completed: subprocess.CompletedProcess[str], name: str) -> bool:
    """Recognize only the pinned CLI's sandbox-specific NotFound status."""
    detail = (completed.stderr or completed.stdout).strip().lower()
    escaped = re.escape(name.lower())
    return bool(
        re.search(
            rf"\bsandbox\s+['\"]?{escaped}['\"]?\s+(?:was\s+)?not found\b", detail
        )
        or re.search(rf"\bsandbox not found\s*:\s*['\"]?{escaped}['\"]?\b", detail)
        or re.search(
            r"\bstatus:\s*notfound\b.*\bmessage:\s*[\"']sandbox not found[\"']", detail
        )
        or re.search(
            r"\bcode:\s*[\"']some requested entity was not found[\"']"
            r".*\bmessage:\s*[\"']sandbox not found[\"']",
            detail,
        )
    )


def _sandbox_phase(payload: dict[str, object]) -> str:
    status = payload.get("status")
    if isinstance(status, dict):
        value = status.get("phase") or status.get("state") or status.get("status")
    else:
        value = payload.get("phase") or status or payload.get("state")
    return str(value or "")


def _sandbox_name(payload: dict[str, object]) -> str:
    value = payload.get("name")
    metadata = payload.get("metadata")
    if not value and isinstance(metadata, dict):
        value = metadata.get("name")
    return str(value or "")


_BOUNDED_EXPORT_SCRIPT = r"""
import os, stat, sys, tarfile
root = os.path.realpath(".")
count = 0
total = 0
with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as archive:
    for directory, dirnames, filenames in os.walk(root, followlinks=False):
        for dirname in dirnames:
            path = os.path.join(directory, dirname)
            if not stat.S_ISDIR(os.lstat(path).st_mode):
                raise SystemExit("unsafe workspace directory")
        for filename in filenames:
            path = os.path.join(directory, filename)
            info = os.lstat(path)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise SystemExit("unsafe workspace file")
            count += 1
            total += info.st_size
            if count > 2000 or total > 100 * 1024 * 1024:
                raise SystemExit("workspace transfer limit exceeded")
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            fd = os.open(path, flags)
            stream = os.fdopen(fd, "rb")
            opened = os.fstat(fd)
            if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                stream.close()
                raise SystemExit("workspace file changed during transfer")
            relative = os.path.relpath(path, root)
            entry = tarfile.TarInfo(relative)
            entry.size = opened.st_size
            entry.mode = opened.st_mode & 0o777
            archive.addfile(entry, stream)
            stream.close()
"""
