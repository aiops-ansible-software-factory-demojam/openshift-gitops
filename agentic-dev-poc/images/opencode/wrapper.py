#!/usr/bin/env python3
"""Run OpenCode from a task file. The prompt is data, never a shell command."""

from __future__ import annotations

import json
import os
import selectors
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

WORKDIR = Path("/sandbox/work")
OUT = WORKDIR / "out"
WRAPPER = Path("/opt/agentic-poc/wrapper.py")
FIXTURES = Path("/opt/agentic-poc/fixtures")
HOME = Path("/sandbox/opencode-home")
LOG_LIMIT = 10 * 1024 * 1024
EVENT_LINE_LIMIT = 1024 * 1024
ERROR_LIMIT = 500
SUMMARY_LIMIT = 2000


@dataclass
class EventStatus:
    """Incrementally retain bounded status while the event artifact is capped."""

    summary: str = ""
    error: str = ""
    parser_error: str = ""
    last_event_type: str = ""
    final_status: str = ""
    event_count: int = 0
    log_truncated: bool = False
    _pending: bytearray = field(default_factory=bytearray, repr=False)
    _discarding_oversized_line: bool = field(default=False, repr=False)

    def feed(self, chunk: bytes) -> None:
        offset = 0
        while offset < len(chunk):
            if self._discarding_oversized_line:
                newline = chunk.find(b"\n", offset)
                if newline < 0:
                    return
                self._discarding_oversized_line = False
                offset = newline + 1
                continue

            newline = chunk.find(b"\n", offset)
            if newline < 0:
                remainder = chunk[offset:]
                if len(self._pending) + len(remainder) > EVENT_LINE_LIMIT:
                    self._uncertain(
                        f"OpenCode event line exceeds {EVENT_LINE_LIMIT} bytes."
                    )
                    self._pending.clear()
                    self._discarding_oversized_line = True
                else:
                    self._pending.extend(remainder)
                return

            line = chunk[offset:newline]
            if len(self._pending) + len(line) > EVENT_LINE_LIMIT:
                self._uncertain(
                    f"OpenCode event line exceeds {EVENT_LINE_LIMIT} bytes."
                )
                self._pending.clear()
            else:
                self._pending.extend(line)
                self._parse_line(bytes(self._pending))
                self._pending.clear()
            offset = newline + 1

    def finish(self) -> None:
        if not self._discarding_oversized_line and self._pending:
            self._parse_line(bytes(self._pending))
        self._pending.clear()

    def _parse_line(self, line: bytes) -> None:
        line = line.rstrip(b"\r")
        if not line:
            return
        try:
            decoded = line.decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            self._uncertain("OpenCode emitted invalid UTF-8 event data.")
            return
        try:
            event = json.loads(decoded)
        except json.JSONDecodeError:
            self._uncertain("OpenCode emitted malformed JSON event data.")
            return
        if not isinstance(event, dict):
            self._uncertain("OpenCode emitted a non-object JSON event.")
            return

        self.event_count += 1
        event_type = event.get("type")
        if isinstance(event_type, str):
            self.last_event_type = event_type[:100]
        part = event.get("part")
        if isinstance(part, dict):
            for key in ("status", "reason"):
                value = part.get(key)
                if isinstance(value, str):
                    self.final_status = value[:100]
        for key in ("status", "reason"):
            value = event.get(key)
            if isinstance(value, str):
                self.final_status = value[:100]

        if (
            event_type == "text"
            and isinstance(part, dict)
            and part.get("type") == "text"
        ):
            value = part.get("text")
            if isinstance(value, str) and value.strip():
                self.summary = value.strip()[:SUMMARY_LIMIT]
        elif event_type == "error" and not self.error:
            value = event.get("error")
            if isinstance(value, dict):
                data = value.get("data")
                value = (
                    data.get("message")
                    if isinstance(data, dict)
                    else value.get("message")
                )
            self.error = str(value or "OpenCode emitted an error event.")[:ERROR_LIMIT]

    def _uncertain(self, message: str) -> None:
        if not self.parser_error:
            self.parser_error = message[:ERROR_LIMIT]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: wrapper.py TASK.json", file=sys.stderr)
        return 2
    task = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    prompt = task.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        print("task prompt is missing", file=sys.stderr)
        return 2
    OUT.mkdir(parents=True, exist_ok=True)
    HOME.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["HOME"] = str(HOME)
    env["XDG_CONFIG_HOME"] = str(HOME / "config")
    env["XDG_DATA_HOME"] = str(HOME / "data")
    env["XDG_CACHE_HOME"] = str(HOME / "cache")
    model = env.get("OPENCODE_MODEL", "poc/gpt-4.1-mini")
    events = OUT / "events.ndjson"
    event_status = EventStatus()
    exit_code = _stream_process(
        [
            "opencode",
            "run",
            "--format",
            "json",
            "--model",
            model,
            "--dir",
            str(WORKDIR),
            prompt,
        ],
        cwd=WORKDIR,
        env=env,
        stdout_path=events,
        stderr_path=OUT / "opencode.stderr",
        event_status=event_status,
    )
    agent_tests = _run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(WORKDIR), "-v"],
        WORKDIR,
        env,
        "generated-tests",
    )
    commands = [agent_tests]
    if env.get("AGENTIC_POC_SMOKE_FIXTURE", "").lower() in {"1", "true", "yes"}:
        commands.append(
            _run(
                [
                    sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    str(FIXTURES),
                    "-v",
                ],
                WORKDIR,
                env,
                "slugify-fixture",
            )
        )
    validation_ok = all(command["exit_code"] == 0 for command in commands)
    report = {
        "summary": event_status.summary or "OpenCode finished without a text summary.",
        "reported_agent_exit_code": exit_code,
        "event_error": event_status.error,
        "event_status": {
            "event_count": event_status.event_count,
            "last_event_type": event_status.last_event_type,
            "final_status": event_status.final_status,
            "log_truncated": event_status.log_truncated,
            "parser_error": event_status.parser_error,
        },
        "validation": {
            "status": "passed" if validation_ok else "failed",
            "commands": commands,
            "evidence": "recorded_execution",
        },
    }
    (OUT / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    untrusted_status = event_status.error or event_status.parser_error
    return 1 if untrusted_status and exit_code == 0 else exit_code


def _run(
    argv: list[str], cwd: Path, env: dict[str, str], log_name: str
) -> dict[str, object]:
    exit_code = _stream_process(
        argv,
        cwd=cwd,
        env=env,
        stdout_path=OUT / f"{log_name}.log",
    )
    return {
        "command": " ".join(argv),
        "exit_code": exit_code,
        "log": f"out/{log_name}.log",
    }


def _summary(stream: str) -> tuple[str, str]:
    status = EventStatus()
    status.feed(stream.encode("utf-8"))
    status.finish()
    return status.summary, status.error


def _stream_process(
    argv: list[str],
    cwd: Path,
    env: dict[str, str],
    stdout_path: Path,
    stderr_path: Path | None = None,
    event_status: EventStatus | None = None,
) -> int:
    """Drain process output continuously while persisting at most 10 MiB per stream."""
    process = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE if stderr_path else subprocess.STDOUT,
    )
    selector = selectors.DefaultSelector()
    assert process.stdout is not None
    selector.register(process.stdout, selectors.EVENT_READ, stdout_path)
    if stderr_path:
        assert process.stderr is not None
        selector.register(process.stderr, selectors.EVENT_READ, stderr_path)
    written: dict[Path, int] = {stdout_path: 0}
    if stderr_path:
        written[stderr_path] = 0
    files = {path: path.open("wb") for path in written}
    try:
        while selector.get_map():
            for key, _ in selector.select():
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                path = key.data
                if path == stdout_path and event_status is not None:
                    event_status.feed(chunk)
                available = LOG_LIMIT - written[path]
                if available > 0:
                    files[path].write(chunk[:available])
                    written[path] += min(len(chunk), available)
                if (
                    len(chunk) > available
                    and path == stdout_path
                    and event_status is not None
                ):
                    event_status.log_truncated = True
    finally:
        if event_status is not None:
            event_status.finish()
        selector.close()
        if process.stdout:
            process.stdout.close()
        if process.stderr:
            process.stderr.close()
        for stream in files.values():
            stream.close()
    return process.wait()


if __name__ == "__main__":
    sys.exit(main())
