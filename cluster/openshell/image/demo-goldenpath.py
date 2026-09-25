#!/opt/venv/bin/python
"""Run the demo Backstage golden paths and open the resulting Forgejo PR."""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


def request(base, path, method="GET", payload=None, token=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}" if base == backstage else f"token {token}"
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # API error bodies may contain server details; keep credentials private.
        raise RuntimeError(f"{method} {path} returned HTTP {error.code}") from error


def backstage_token():
    result = request(backstage, "/api/auth/guest/refresh", "POST", {})
    return result["backstageIdentity"]["token"]


def run_template(name, values):
    token = backstage_token()
    response = request(
        backstage,
        "/api/scaffolder/v2/tasks",
        "POST",
        {"templateRef": f"template:default/{name}", "values": values},
        token,
    )
    task_id = response["id"]
    print(f"Backstage task: {task_id}", flush=True)
    for _ in range(120):
        task = request(backstage, f"/api/scaffolder/v2/tasks/{task_id}", token=token)
        if task["status"] == "completed":
            print(json.dumps(task.get("output", {}), indent=2))
            return
        if task["status"] in ("failed", "cancelled"):
            raise RuntimeError(f"Backstage task {task_id} {task['status']}; inspect its task log")
        time.sleep(3)
    raise RuntimeError(f"Backstage task {task_id} did not finish within six minutes")


def open_pr(issue, title):
    token = os.environ["FORGEJO_TOKEN"]
    owner = "demo-owner"
    repo = "ansible-collection-demo"
    branch = f"feature/issue-{issue}"
    existing = request(
        forgejo,
        f"/api/v1/repos/{owner}/{repo}/pulls?state=all&limit=100",
        token=token,
    )
    for item in existing:
        if item.get("head", {}).get("ref") == branch:
            print(item["html_url"])
            return
    result = request(
        forgejo,
        f"/api/v1/repos/{owner}/{repo}/pulls",
        "POST",
        {"base": "main", "head": branch, "title": title, "body": f"Closes #{issue}"},
        token,
    )
    print(result["html_url"])


def show_issue(issue):
    result = request(
        forgejo,
        f"/api/v1/repos/demo-owner/ansible-collection-demo/issues/{issue}",
        token=os.environ["FORGEJO_TOKEN"],
    )
    print(f"{result['title']}\n\n{result['body']}")


parser = argparse.ArgumentParser(description=__doc__)
subparsers = parser.add_subparsers(dest="command", required=True)
new = subparsers.add_parser("new", help="Create and register a collection")
new.add_argument("name")
new.add_argument("description")
feature = subparsers.add_parser("feature", help="Start an issue branch through Backstage")
feature.add_argument("issue", type=int)
issue = subparsers.add_parser("issue", help="Read the example collection issue")
issue.add_argument("issue", type=int)
pr = subparsers.add_parser("pr", help="Open a pull request for an issue branch")
pr.add_argument("issue", type=int)
pr.add_argument("title")
args = parser.parse_args()
backstage = os.environ["BACKSTAGE_URL"].rstrip("/")
forgejo = os.environ["FORGEJO_URL"].rstrip("/")

try:
    if args.command == "new":
        run_template("ansible-collection", {"name": args.name, "description": args.description})
    elif args.command == "feature":
        run_template("ansible-collection-feature", {"issue_number": args.issue})
    elif args.command == "issue":
        show_issue(args.issue)
    else:
        open_pr(args.issue, args.title)
except (KeyError, ValueError, RuntimeError, urllib.error.URLError) as error:
    print(f"demo-goldenpath: {error}", file=sys.stderr)
    sys.exit(1)
