#!/usr/bin/env python3
"""Create the runner credential and publish the two manual workflows."""

from __future__ import annotations

import json
import os
import ssl
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = os.environ.get(
    "AO_URL", "https://orchestrator.apps.cluster-qb5wm.dyn.redhatworkshops.io"
).rstrip("/")
PROJECT = "09487e25-4f4b-492a-932b-6186e2e5c3ef"
BEARER_TYPE = "b4134c22-a6c8-4e65-a97e-36050e698bdf"


def request(method: str, path: str, token: str, body: dict | None = None) -> tuple[int, dict]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, context=tls_context(), timeout=60) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode()
        return exc.code, json.loads(raw) if raw else {}


def login() -> str:
    req = urllib.request.Request(
        BASE + "/api/v1/auth/login",
        data=json.dumps(
            {"username": os.environ.get("AO_USERNAME", "admin"), "password": os.environ["AO_PASSWORD"]}
        ).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, context=tls_context(), timeout=30) as response:
        return json.loads(response.read().decode())["access_token"]


def tls_context() -> ssl.SSLContext:
    ca_file = os.environ.get("AO_CA_FILE")
    return ssl.create_default_context(cafile=ca_file) if ca_file else ssl.create_default_context()


def credential_id(token: str, bearer: str) -> str:
    status, listed = request("GET", f"/api/v1/projects/{PROJECT}/credentials?limit=100", token)
    if status != 200:
        raise SystemExit(f"list credentials failed: {status} {listed}")
    for item in listed.get("resources", []):
        if item.get("name") == "agentic-poc-runner":
            status, updated = request(
                "PATCH",
                f"/api/v1/credentials/{item['id']}",
                token,
                {"inputs": {"token": bearer}},
            )
            if status != 200:
                raise SystemExit(f"update credential failed: {status} {updated}")
            return item["id"]
    status, created = request(
        "POST",
        "/api/v1/credentials",
        token,
        {
            "name": "agentic-poc-runner",
            "credential_type_id": BEARER_TYPE,
            "project_id": PROJECT,
            "inputs": {"token": bearer},
        },
    )
    if status not in (200, 201):
        raise SystemExit(f"create credential failed: {status} {created}")
    return created["id"]


def publish(token: str, path: Path, cred: str) -> None:
    definition = json.loads(path.read_text().replace("RUNNER_CREDENTIAL_ID", cred))
    body = {
        "name": definition["name"],
        "description": definition.get("description"),
        "project_id": PROJECT,
        "workflow_definition": definition,
    }
    status, listed = request("GET", "/api/v1/workflows?limit=100", token)
    if status != 200:
        raise SystemExit(f"list workflows failed: {status} {listed}")
    existing = next(
        (
            item
            for item in listed.get("resources", [])
            if item.get("name") == definition["name"]
            and item.get("project_id", PROJECT) == PROJECT
        ),
        None,
    )
    if existing:
        workflow_id = existing["id"]
        expected = existing.get("current_version") or existing.get("version")
        if isinstance(expected, dict):
            expected = expected.get("version")
        update = {
            "name": definition["name"],
            "description": definition.get("description"),
            "workflow_definition": definition,
        }
        if isinstance(expected, int):
            update["expected_version"] = expected
        status, saved = request("PATCH", f"/api/v1/workflows/{workflow_id}", token, update)
        if status != 200:
            raise SystemExit(f"update {definition['name']} failed: {status} {saved}")
    else:
        status, saved = request("POST", "/api/v1/workflows", token, body)
        if status not in (200, 201):
            raise SystemExit(f"create {definition['name']} failed: {status} {saved}")
        workflow_id = saved["id"]
    version = saved.get("current_version") or saved.get("version") or 1
    if isinstance(version, dict):
        version = version.get("version", 1)
    status, published = request(
        "POST",
        f"/api/v1/workflows/{workflow_id}/versions/{version}/publish",
        token,
        {"publish_name": definition["name"], "expected_version": version},
    )
    conflict_text = json.dumps(published).lower()
    already_published = status == 409 and "already" in conflict_text and "publish" in conflict_text
    if status not in (200, 201) and not already_published:
        raise SystemExit(f"publish {definition['name']} failed: {status} {published}")
    status, exported = request(
        "GET", f"/api/v1/workflows/{workflow_id}/versions/{version}/export", token
    )
    if status == 200:
        dest = ROOT / "workflows" / "exported" / f"{definition['name']}.json"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(json.dumps(exported, indent=2) + "\n")
        print(f"exported {dest}")
    print(f"published {definition['name']} {workflow_id}")


def main() -> None:
    global PROJECT
    PROJECT = os.environ.get("AO_PROJECT_ID", PROJECT)
    token = login()
    bearer = os.environ["RUNNER_TOKEN"]
    cred = credential_id(token, bearer)
    for name in ("manual-opencode-poc.json", "cancel-opencode-poc.json"):
        publish(token, ROOT / "workflows" / name, cred)


if __name__ == "__main__":
    main()
