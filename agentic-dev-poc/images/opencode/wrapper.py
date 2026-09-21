#!/usr/bin/env python3
"""Run OpenCode from a task file. The prompt is data, never a shell command."""

from __future__ import annotations

import json
import os
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
    completed = subprocess.run(
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
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    events.write_text(completed.stdout or "", encoding="utf-8")
    (OUT / "opencode.stderr").write_text((completed.stderr or "")[: 10 * 1024 * 1024], encoding="utf-8")
    agent_tests = _run([sys.executable, "-m", "unittest", "discover", "-s", str(WORKDIR), "-v"], WORKDIR, env)
    fixture = _run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(FIXTURES), "-v"],
        WORKDIR,
        env,
    )
    summary = _summary(completed.stdout or "")
    fixture_ok = fixture["exit_code"] == 0
    report = {
        "summary": summary or "OpenCode finished without a text summary.",
        "agent_exit_code": completed.returncode,
        "validation": {
            "status": "passed" if fixture_ok and agent_tests["exit_code"] == 0 else "failed",
            "commands": [agent_tests, fixture],
            "evidence": "recorded_execution",
        },
    }
    (OUT / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return 0 if completed.returncode == 0 else completed.returncode


def _run(argv: list[str], cwd: Path, env: dict[str, str]) -> dict[str, object]:
    completed = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = (completed.stdout or "")[: 10 * 1024 * 1024]
    (OUT / (Path(str(argv[4])).name + ".log")).write_text(output, encoding="utf-8")
    return {"command": " ".join(argv), "exit_code": completed.returncode}


def _summary(stream: str) -> str:
    text = ""
    for line in stream.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            part = event.get("text") or event.get("content") or ""
            if isinstance(part, str) and part.strip():
                text = part.strip()
    return text[:2000]


if __name__ == "__main__":
    sys.exit(main())
