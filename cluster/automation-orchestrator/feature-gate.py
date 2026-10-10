#!/usr/bin/python3
"""Prepare an issue branch through Backstage before AO launches an agent."""

import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


BACKSTAGE = os.environ["BACKSTAGE_URL"].rstrip("/")
REPOSITORY = "demo-owner/ansible-collection-demo.webapp"


def backstage(path, method="GET", body=None, token=None, missing_ok=False):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    request = Request(BACKSTAGE + path, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=20) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code == 404 and missing_ok:
            return None
        raise RuntimeError(f"Backstage {method} {path} returned HTTP {error.code}") from None


def prepare(number):
    token = os.environ["BACKSTAGE_TOKEN"]
    issue = backstage(
        f"/api/proxy/forgejo/repos/{REPOSITORY}/issues/{number}",
        token=token,
        missing_ok=True,
    )
    if not issue or issue.get("pull_request") or issue.get("state") != "open":
        raise ValueError(f"Issue #{number} is not an open collection issue")
    branch = f"feature/issue-{number}"
    branch_path = quote(branch, safe="")
    path = f"/api/proxy/forgejo/repos/{REPOSITORY}/branches/{branch_path}"
    existing = backstage(path, token=token, missing_ok=True)
    task_id = None
    if not existing:
        result = backstage(
            "/api/scaffolder/v2/tasks",
            "POST",
            {
                "templateRef": "template:default/ansible-collection-feature",
                "values": {"issue_number": number},
            },
            token,
        )
        task_id = result["id"]
        for _ in range(100):
            task = backstage(f"/api/scaffolder/v2/tasks/{task_id}", token=token)
            if task["status"] == "completed":
                break
            if task["status"] in ("failed", "cancelled"):
                raise RuntimeError(f"Backstage task {task_id} {task['status']}")
            time.sleep(3)
        else:
            raise RuntimeError(f"Backstage task {task_id} timed out")
    if not backstage(path, token=token, missing_ok=True):
        raise RuntimeError(f"Backstage did not create {branch}")
    return {
        "issue_number": number,
        "branch": branch,
        "task_id": task_id,
        "issue": {key: issue.get(key) or "" for key in ("title", "body", "html_url")},
    }


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self.respond(200 if self.path == "/healthz" else 404, {"status": "ok"})

    def do_POST(self):
        if self.path != "/prepare":
            return self.respond(404, {"error": "Unknown path"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size < 1024:
                raise ValueError("Expected a small JSON request")
            body = json.loads(self.rfile.read(size))
            number = body["issue_number"]
            if isinstance(number, str) and number.isdecimal():
                number = int(number)
            if type(number) is not int or number < 1:
                raise ValueError("issue_number must be a positive integer")
        except (ValueError, KeyError) as error:
            self.respond(400, {"error": str(error)})
            return
        try:
            self.respond(200, prepare(number))
        except ValueError as error:
            self.respond(400, {"error": str(error)})
        except (RuntimeError, URLError, KeyError, TypeError, OSError) as error:
            self.respond(502, {"error": str(error)})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
