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
SPEC.loader.exec_module(wrapper)


class WrapperTest(unittest.TestCase):
    def test_summary_parses_actual_nested_text_and_error_events(self) -> None:
        stream = "\n".join(
            [
                json.dumps({"type": "text", "part": {"type": "text", "text": "first"}}),
                json.dumps({"type": "tool_use", "part": {"type": "tool"}}),
                json.dumps({"type": "text", "part": {"type": "text", "text": "final"}}),
                json.dumps({"type": "error", "error": {"data": {"message": "provider failed"}}}),
            ]
        )
        self.assertEqual(wrapper._summary(stream), ("final", "provider failed"))

    def test_slugify_fixture_runs_only_for_explicit_smoke(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            work = root / "work"
            work.mkdir()
            task = root / "task.json"
            task.write_text(json.dumps({"prompt": "create any project"}), encoding="utf-8")

            def fake_stream(*args, stdout_path: Path, stderr_path: Path | None = None, **kwargs):
                del args, kwargs
                stdout_path.write_text(
                    json.dumps({"type": "text", "part": {"type": "text", "text": "done"}}),
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
                with patch.object(wrapper, "_stream_process", side_effect=fake_stream), patch.object(
                    wrapper,
                    "_run",
                    return_value={"command": "tests", "exit_code": 0, "log": "out/tests.log"},
                ) as run, patch.object(sys, "argv", ["wrapper.py", str(task)]), patch.dict(
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
                [sys.executable, "-c", "import sys; sys.stdout.write('x' * (11 * 1024 * 1024))"],
                Path(directory),
                os.environ.copy(),
                output,
            )
            self.assertEqual(exit_code, 0)
            self.assertEqual(output.stat().st_size, 10 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
