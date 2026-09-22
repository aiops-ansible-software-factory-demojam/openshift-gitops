"""Tests for the fixed OpenCode wrapper contract."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

WRAPPER_PATH = Path(__file__).parents[1] / "images" / "opencode" / "wrapper.py"
SPEC = importlib.util.spec_from_file_location("agentic_poc_wrapper", WRAPPER_PATH)
assert SPEC and SPEC.loader
wrapper = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = wrapper
SPEC.loader.exec_module(wrapper)


class WrapperTest(unittest.TestCase):
    def _run_real_wrapper(self, mode: str) -> tuple[int, dict[str, object], bytes]:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            work = root / "work"
            work.mkdir()
            (work / "test_generated.py").write_text(
                "import unittest\n\n"
                "class GeneratedTest(unittest.TestCase):\n"
                "    def test_passes(self):\n"
                "        self.assertEqual(2 + 2, 4)\n",
                encoding="utf-8",
            )
            task = root / "task.json"
            task.write_text(
                json.dumps({"prompt": "exercise the stub"}), encoding="utf-8"
            )
            binary = root / "bin"
            binary.mkdir()
            opencode = binary / "opencode"
            opencode.write_text(
                """#!/usr/bin/python3
import json
import os
import sys

mode = os.environ["STUB_OPENCODE_MODE"]

def emit(value, chunked=False):
    data = (json.dumps(value, ensure_ascii=False) + "\\n").encode("utf-8")
    if chunked:
        for byte in data:
            os.write(1, bytes([byte]))
    else:
        os.write(1, data)

error = {"type": "error", "error": {"data": {"message": "provider échoué"}}}
if mode == "error-before":
    emit(error)
elif mode in {"error-after", "valid-large"}:
    filler = {"type": "tool_use", "part": {"type": "tool", "data": "x" * 64000}}
    written = 0
    while written < 11 * 1024 * 1024:
        data = (json.dumps(filler) + "\\n").encode("utf-8")
        os.write(1, data)
        written += len(data)
    if mode == "error-after":
        emit(error)
    else:
        emit({"type": "text", "part": {"type": "text", "text": "final after cap"}})
elif mode == "chunked-error":
    emit(error, chunked=True)
elif mode == "oversized":
    os.write(1, b"{" + b"x" * (1024 * 1024 + 1) + b"}\\n")
elif mode == "malformed":
    os.write(1, b"not-json\\n")
else:
    raise SystemExit(2)
""",
                encoding="utf-8",
            )
            opencode.chmod(0o755)

            wrapper.WORKDIR = work
            wrapper.OUT = work / "out"
            wrapper.HOME = root / "home"
            wrapper.FIXTURES = root / "fixtures"
            environment = {
                "PATH": f"{binary}:{os.environ['PATH']}",
                "STUB_OPENCODE_MODE": mode,
                "AGENTIC_POC_SMOKE_FIXTURE": "",
            }
            with patch.object(sys, "argv", ["wrapper.py", str(task)]), patch.dict(
                os.environ, environment, clear=False
            ):
                exit_code = wrapper.main()
            report = json.loads(
                (wrapper.OUT / "result.json").read_text(encoding="utf-8")
            )
            events = (wrapper.OUT / "events.ndjson").read_bytes()
            return exit_code, report, events

    def test_summary_parses_actual_nested_text_and_error_events(self) -> None:
        stream = "\n".join(
            [
                json.dumps({"type": "text", "part": {"type": "text", "text": "first"}}),
                json.dumps({"type": "tool_use", "part": {"type": "tool"}}),
                json.dumps({"type": "text", "part": {"type": "text", "text": "final"}}),
                json.dumps(
                    {"type": "error", "error": {"data": {"message": "provider failed"}}}
                ),
            ]
        )
        self.assertEqual(wrapper._summary(stream), ("final", "provider failed"))

    def test_slugify_fixture_runs_only_for_explicit_smoke(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            work = root / "work"
            work.mkdir()
            task = root / "task.json"
            task.write_text(
                json.dumps({"prompt": "create any project"}), encoding="utf-8"
            )

            def fake_stream(
                *args, stdout_path: Path, stderr_path: Path | None = None, **kwargs
            ):
                del args, kwargs
                stdout_path.write_text(
                    json.dumps(
                        {"type": "text", "part": {"type": "text", "text": "done"}}
                    ),
                    encoding="utf-8",
                )
                if stderr_path:
                    stderr_path.write_text("", encoding="utf-8")
                return 0

            def run_once(smoke: bool) -> int:
                wrapper.WORKDIR = work
                wrapper.OUT = work / "out"
                wrapper.HOME = root / "home"
                wrapper.FIXTURES = root / "fixtures"
                wrapper.OUT.mkdir(parents=True, exist_ok=True)
                with patch.object(
                    wrapper, "_stream_process", side_effect=fake_stream
                ), patch.object(
                    wrapper,
                    "_run",
                    return_value={
                        "command": "tests",
                        "exit_code": 0,
                        "log": "out/tests.log",
                    },
                ) as run, patch.object(
                    sys, "argv", ["wrapper.py", str(task)]
                ), patch.dict(
                    os.environ,
                    {"AGENTIC_POC_SMOKE_FIXTURE": "true"} if smoke else {},
                    clear=True,
                ):
                    self.assertEqual(wrapper.main(), 0)
                    return run.call_count

            self.assertEqual(run_once(False), 1)
            self.assertEqual(run_once(True), 2)

    def test_process_logs_are_streamed_with_a_hard_cap(self) -> None:
        with TemporaryDirectory() as directory:
            output = Path(directory) / "bounded.log"
            exit_code = wrapper._stream_process(
                [
                    sys.executable,
                    "-c",
                    "import sys; sys.stdout.write('x' * (11 * 1024 * 1024))",
                ],
                Path(directory),
                os.environ.copy(),
                output,
            )
            self.assertEqual(exit_code, 0)
            self.assertEqual(output.stat().st_size, wrapper.LOG_LIMIT)

    def test_error_before_and_after_log_cap_both_fail_with_passing_tests(self) -> None:
        for mode in ("error-before", "error-after"):
            with self.subTest(mode=mode):
                exit_code, report, events = self._run_real_wrapper(mode)
                self.assertEqual(exit_code, 1)
                self.assertEqual(report["reported_agent_exit_code"], 0)
                self.assertEqual(report["event_error"], "provider échoué")
                self.assertEqual(report["validation"]["status"], "passed")
                self.assertEqual(report["validation"]["commands"][0]["exit_code"], 0)
                self.assertEqual(report["event_status"]["parser_error"], "")
                if mode == "error-after":
                    self.assertEqual(len(events), wrapper.LOG_LIMIT)
                    self.assertNotIn("provider".encode(), events)
                    self.assertTrue(report["event_status"]["log_truncated"])

    def test_valid_large_stream_keeps_final_status_without_unbounded_log(self) -> None:
        exit_code, report, events = self._run_real_wrapper("valid-large")
        self.assertEqual(exit_code, 0)
        self.assertEqual(len(events), wrapper.LOG_LIMIT)
        self.assertEqual(report["summary"], "final after cap")
        self.assertEqual(report["event_error"], "")
        self.assertEqual(report["event_status"]["parser_error"], "")
        self.assertTrue(report["event_status"]["log_truncated"])

    def test_chunked_utf8_error_is_detected(self) -> None:
        exit_code, report, _ = self._run_real_wrapper("chunked-error")
        self.assertEqual(exit_code, 1)
        self.assertEqual(report["event_error"], "provider échoué")
        self.assertEqual(report["event_status"]["parser_error"], "")

    def test_oversized_or_malformed_event_fails_closed(self) -> None:
        expected = {
            "oversized": "exceeds",
            "malformed": "malformed",
        }
        for mode, detail in expected.items():
            with self.subTest(mode=mode):
                exit_code, report, _ = self._run_real_wrapper(mode)
                self.assertEqual(exit_code, 1)
                self.assertEqual(report["reported_agent_exit_code"], 0)
                self.assertEqual(report["validation"]["status"], "passed")
                self.assertIn(detail, report["event_status"]["parser_error"])


if __name__ == "__main__":
    unittest.main()
