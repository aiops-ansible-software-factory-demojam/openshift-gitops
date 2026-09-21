"""Authenticated HTTP API."""

from __future__ import annotations

import hashlib
import hmac
import json
import stat
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable
from urllib.parse import unquote, urlsplit

from .lifecycle import Engine
from .models import ARTIFACT_BYTES, BODY_MAX, RequestError

StartRun = Callable[[str], None]


class ApiServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        engine: Engine,
        token: str,
        start_run: StartRun,
        ready: Callable[[], bool],
    ) -> None:
        self.engine = engine
        self.token = token
        self.start_run = start_run
        self.ready = ready
        self.hits: deque[float] = deque()
        self.hit_lock = threading.Lock()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    server: ApiServer
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:
        del fmt, args

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch()

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch()

    def _dispatch(self) -> None:
        self.close_connection = True
        path = unquote(urlsplit(self.path).path)
        if self.command == "POST":
            self._drain_body()
        try:
            if not self._allow_rate():
                self._json(429, {"error": "rate_limited", "message": "Too many requests."})
                return
            if path == "/healthz":
                self._json(200, {"status": "ok"})
                return
            if path == "/readyz":
                status = 200 if self.server.ready() else 503
                self._json(status, {"status": "ready" if status == 200 else "starting"})
                return
            self._require_auth()
            if self.command == "POST" and path == "/v1/runs":
                self._start()
                return
            parts = [part for part in path.split("/") if part]
            if len(parts) == 3 and parts[0] == "v1" and parts[1] == "runs" and self.command == "GET":
                self._status(parts[2])
                return
            if len(parts) == 4 and parts[:2] == ["v1", "runs"] and parts[3] == "result" and self.command == "GET":
                self._result(parts[2])
                return
            if len(parts) == 4 and parts[:2] == ["v1", "runs"] and parts[3] == "cancel" and self.command == "POST":
                self._cancel(parts[2])
                return
            if (
                len(parts) == 5
                and parts[:2] == ["v1", "runs"]
                and parts[3] == "artifacts"
                and self.command == "GET"
            ):
                self._artifact(parts[2], parts[4])
                return
            self._json(404, {"error": "not_found", "message": "Not found."})
        except RequestError as exc:
            self._json(exc.status, {"error": exc.code, "message": exc.message})
        except Exception:
            self._json(500, {"error": "internal", "message": "The runner failed the request."})

    def _start(self) -> None:
        key = self.headers.get("Idempotency-Key", "").strip()
        if not key or len(key) > 256:
            raise RequestError(400, "missing_idempotency_key", "Idempotency-Key is required.")
        body = getattr(self, "_body", b"")
        if len(body) > BODY_MAX:
            raise RequestError(413, "body_too_large", "Request body exceeds 64 KiB.")
        from .models import parse_run_request

        prompt, source = parse_run_request(body)
        run, status, created = self.server.engine.accept(prompt, source, key)
        if created and self.server.engine.claim_execution(run.id):
            self.server.start_run(run.id)
        self._json(status, run.public_status())

    def _status(self, run_id: str) -> None:
        run = self.server.engine.store.get(run_id)
        if run is None:
            raise RequestError(404, "not_found", "Run not found.")
        self._json(200, run.public_status())

    def _result(self, run_id: str) -> None:
        self._json(200, self.server.engine.build_result(run_id))

    def _cancel(self, run_id: str) -> None:
        run = self.server.engine.request_cancel(run_id)
        self._json(202, run.public_status())

    def _artifact(self, run_id: str, artifact_id: str) -> None:
        row = self.server.engine.store.get_artifact(run_id, artifact_id)
        if row is None:
            raise RequestError(404, "not_found", "Artifact not found.")
        path = Path(row["path"])
        expected_root = (self.server.engine.artifact_root / run_id).resolve()
        try:
            resolved = path.resolve(strict=True)
            resolved.relative_to(expected_root)
        except (FileNotFoundError, ValueError):
            raise RequestError(404, "not_found", "Artifact file is gone.")
        info = path.lstat()
        if path.is_symlink() or not stat.S_ISREG(info.st_mode):
            raise RequestError(422, "artifact_rejected", "Artifact is not a regular file.")
        if info.st_size != row["size"] or info.st_size > ARTIFACT_BYTES:
            raise RequestError(422, "artifact_rejected", "Artifact size changed or is unsafe.")
        data = path.read_bytes()
        if not hmac.compare_digest(hashlib.sha256(data).hexdigest(), row["sha256"]):
            raise RequestError(422, "artifact_rejected", "Artifact checksum changed.")
        self.send_response(200)
        self.send_header("Content-Type", row["content_type"])
        self.send_header("Content-Disposition", f'attachment; filename="{row["name"]}"')
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def _drain_body(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length < 0:
            length = 0
        self._body = self.rfile.read(min(length, BODY_MAX + 1)) if length else b""

    def _require_auth(self) -> None:
        header = self.headers.get("Authorization", "")
        scheme, _, presented = header.partition(" ")
        if scheme.lower() != "bearer" or not presented:
            raise RequestError(401, "unauthorized", "A bearer token is required.")
        if not hmac.compare_digest(presented.strip(), self.server.token):
            raise RequestError(401, "unauthorized", "A bearer token is required.")

    def _allow_rate(self) -> bool:
        now = time.monotonic()
        with self.server.hit_lock:
            while self.server.hits and now - self.server.hits[0] > 60:
                self.server.hits.popleft()
            if len(self.server.hits) >= 60:
                return False
            self.server.hits.append(now)
        return True

    def _json(self, status: int, payload: dict[str, object]) -> None:
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)
