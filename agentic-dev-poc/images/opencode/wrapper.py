#!/usr/bin/env python3
"""Run OpenCode from a task file. The prompt is data, never a shell command."""

from __future__ import annotations

import json
import os
import selectors
import subprocess
import sys
from pathlib import Path

WORKDIR = Path("/sandbox/work")
OUT = WORKDIR / "out"
WRAPPER = Path("/opt/agentic-poc/wrapper.py")
FIXTURES = Path("/opt/agentic-poc/fixtures")
HOME = Path("/sandbox/opencode-home")


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
                [sys.executable, "-m", "unittest", "discover", "-s", str(FIXTURES), "-v"],
                WORKDIR,
                env,
                "slugify-fixture",
            )
        )
    event_data = events.read_text(encoding="utf-8")
    summary, event_error = _summary(event_data)
    validation_ok = all(command["exit_code"] == 0 for command in commands)
    report = {
        "summary": summary or "OpenCode finished without a text summary.",
        "reported_agent_exit_code": exit_code,
        "event_error": event_error,
        "validation": {
            "status": "passed" if validation_ok else "failed",
            "commands": commands,
            "evidence": "recorded_execution",
        },
    }
    (OUT / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return 1 if event_error and exit_code == 0 else exit_code


def _run(
    argv: list[str], cwd: Path, env: dict[str, str], log_name: str
) -> dict[str, object]:
    exit_code = _stream_process(
        argv,
        cwd=cwd,
        env=env,
        stdout_path=OUT / f"{log_name}.log",
    )
    return {"command": " ".join(argv), "exit_code": exit_code, "log": f"out/{log_name}.log"}


def _summary(stream: str) -> tuple[str, str]:
    text = ""
    error = ""
    for line in stream.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        event_type = event.get("type")
        part = event.get("part")
        if event_type == "text" and isinstance(part, dict) and part.get("type") == "text":
            value = part.get("text")
            if isinstance(value, str) and value.strip():
                text = value.strip()
        elif event_type == "error":
            value = event.get("error")
            if isinstance(value, dict):
                data = value.get("data")
                value = data.get("message") if isinstance(data, dict) else value.get("message")
            error = str(value or "OpenCode emitted an error event.")[:500]
    return text[:2000], error


def _stream_process(
    argv: list[str],
    cwd: Path,
    env: dict[str, str],
    stdout_path: Path,
    stderr_path: Path | None = None,
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
                available = 10 * 1024 * 1024 - written[path]
                if available > 0:
                    files[path].write(chunk[:available])
                    written[path] += min(len(chunk), available)
    finally:
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
