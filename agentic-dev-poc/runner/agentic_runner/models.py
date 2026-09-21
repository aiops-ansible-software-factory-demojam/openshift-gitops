"""Run states, limits, and request checks."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any

PROMPT_MAX = 16_000
BODY_MAX = 64 * 1024
TOTAL_DEADLINE_SECONDS = 20 * 60
PROVISION_SECONDS = 180
AGENT_SECONDS = 15 * 60
COLLECT_SECONDS = 60
ARTIFACT_BYTES = 100 * 1024 * 1024
LOG_BYTES = 10 * 1024 * 1024
RETENTION_SECONDS = 7 * 24 * 60 * 60
MAX_FILES = 2_000

TERMINAL_STATES = frozenset(
    {"completed", "failed", "timed_out", "cancelled", "interrupted"}
)
ACTIVE_STATES = frozenset(
    {"accepted", "provisioning", "preparing", "running", "collecting", "cleaning"}
)
ALLOWED_FIELDS = frozenset({"prompt", "source_execution_id"})


class RequestError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


@dataclass
class RunRecord:
    id: str
    idempotency_key: str
    request_hash: str
    source_execution_id: str
    prompt: str
    state: str
    terminal: bool
    error: str
    cleanup_state: str
    sandbox_name: str
    config_hash: str
    image: str
    policy_hash: str
    created_at: str
    updated_at: str
    deadline_at: str
    provision_deadline_at: str
    agent_deadline_at: str
    collect_deadline_at: str
    agent_exit_code: int | None
    summary: str
    validation_json: str
    result_json: str
    cancel_requested: bool

    def public_status(self) -> dict[str, Any]:
        return {
            "run_id": self.id,
            "state": self.state,
            "phase": self.state,
            "terminal": self.terminal,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "deadline_at": self.deadline_at,
            "error": self.error or None,
            "cleanup": {"state": self.cleanup_state},
            "status_path": f"/v1/runs/{self.id}",
        }


def request_hash(prompt: str, source_execution_id: str) -> str:
    payload = json.dumps(
        {"prompt": prompt, "source_execution_id": source_execution_id},
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def parse_run_request(body: bytes) -> tuple[str, str]:
    if len(body) > BODY_MAX:
        raise RequestError(413, "body_too_large", "Request body exceeds 64 KiB.")
    try:
        data = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RequestError(400, "invalid_json", "Request body must be JSON.") from exc
    if not isinstance(data, dict):
        raise RequestError(400, "invalid_json", "Request body must be a JSON object.")
    extra = set(data) - ALLOWED_FIELDS
    if extra:
        raise RequestError(400, "unexpected_field", "Only prompt and source_execution_id are accepted.")
    prompt = data.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise RequestError(400, "invalid_prompt", "Prompt must be a nonblank string.")
    if len(prompt) > PROMPT_MAX:
        raise RequestError(400, "invalid_prompt", "Prompt exceeds 16000 characters.")
    source = data.get("source_execution_id", "")
    if source is None:
        source = ""
    if not isinstance(source, str) or len(source) > 256:
        raise RequestError(400, "invalid_source", "source_execution_id must be a short string.")
    return prompt, source
