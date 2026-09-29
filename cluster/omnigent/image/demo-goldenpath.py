#!/usr/bin/python3
"""Run the demo Backstage golden paths and open the resulting Forgejo PR."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
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


def git(cwd, *args, capture=False):
    with tempfile.TemporaryDirectory() as temp:
        askpass = Path(temp) / "askpass"
        askpass.write_text(
            '#!/bin/sh\ncase "$1" in\n'
            '  *Username*) printf "%s\\n" "$FORGEJO_USERNAME" ;;\n'
            '  *) printf "%s\\n" "$FORGEJO_TOKEN" ;;\n'
            'esac\n'
        )
        askpass.chmod(0o700)
        environment = os.environ.copy()
        environment.update(GIT_ASKPASS=str(askpass), GIT_TERMINAL_PROMPT="0")
        result = subprocess.run(
            ["git", "-c", "credential.helper=", *args],
            cwd=cwd,
            env=environment,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            check=True,
        )
        return result.stdout.strip() if capture else None


def prepare_feature(number):
    show_issue(number)
    branch = f"feature/issue-{number}"
    branch_path = urllib.parse.quote(branch, safe="")
    try:
        request(
            forgejo,
            f"/api/v1/repos/demo-owner/ansible-collection-demo/branches/{branch_path}",
            token=os.environ["FORGEJO_TOKEN"],
        )
    except RuntimeError as error:
        if "returned HTTP 404" in str(error):
            raise RuntimeError(f"{branch} does not exist; launch through AO first") from error
        raise
    directory = Path.cwd() / f"issue-{number}"
    remote = f"{forgejo}/demo-owner/ansible-collection-demo.git"
    if not directory.exists():
        git(Path.cwd(), "clone", remote, str(directory))
    if git(directory, "remote", "get-url", "origin", capture=True) != remote:
        raise RuntimeError(f"{directory} has a different origin")
    git(directory, "fetch", "origin", branch)
    branches = git(directory, "branch", "--format=%(refname:short)", capture=True).splitlines()
    if branch in branches:
        git(directory, "checkout", branch)
    else:
        git(directory, "checkout", "-b", branch, f"origin/{branch}")
    git(directory, "config", "user.name", "Automation Developer")
    git(directory, "config", "user.email", "agent@example.test")
    print(f"Repository: {directory}\nBranch: {branch}")


def open_pr(issue, body_file):
    token = os.environ["FORGEJO_TOKEN"]
    owner = "demo-owner"
    repo = "ansible-collection-demo"
    branch = f"feature/issue-{issue}"
    directory = Path.cwd() / f"issue-{issue}"
    if not directory.exists():
        directory = Path.cwd()
    if git(directory, "remote", "get-url", "origin", capture=True) != f"{forgejo}/{owner}/{repo}.git":
        raise RuntimeError("Repository origin does not match this demo")
    if git(directory, "branch", "--show-current", capture=True) != branch:
        raise RuntimeError(f"Check out {branch} before submitting")
    if git(directory, "status", "--porcelain", capture=True):
        raise RuntimeError("Commit or discard working tree changes before submitting")
    if git(directory, "rev-list", "--count", "origin/main..HEAD", capture=True) == "0":
        raise RuntimeError("The feature branch has no commits")
    body = body_file.read_text().strip()
    if not body:
        raise RuntimeError("PR body file is empty")
    if not re.search(rf"(?i)\bcloses\s+#{issue}\b", body):
        body += f"\n\nCloses #{issue}"
    git(directory, "push", "-u", "origin", branch)
    existing = request(
        forgejo,
        f"/api/v1/repos/{owner}/{repo}/pulls?state=all&limit=100",
        token=token,
    )
    for item in existing:
        if item.get("head", {}).get("ref") == branch:
            if item.get("state") != "open":
                raise RuntimeError(f"Existing PR #{item['number']} is closed")
            if item.get("body") != body:
                item = request(
                    forgejo,
                    f"/api/v1/repos/{owner}/{repo}/pulls/{item['number']}",
                    "PATCH",
                    {"body": body},
                    token,
                )
            print(item["html_url"])
            return
    result = request(
        forgejo,
        f"/api/v1/repos/{owner}/{repo}/pulls",
        "POST",
        {"base": "main", "head": branch, "title": show_issue(issue)["title"], "body": body},
        token,
    )
    print(result["html_url"])


def show_issue(issue):
    result = request(
        forgejo,
        f"/api/v1/repos/demo-owner/ansible-collection-demo/issues/{issue}",
        token=os.environ["FORGEJO_TOKEN"],
    )
    if result.get("pull_request") or result.get("state") != "open":
        raise RuntimeError(f"Issue #{issue} is not an open issue")
    print(f"{result['title']}\n\n{result.get('body') or ''}")
    return result


parser = argparse.ArgumentParser(description=__doc__)
subparsers = parser.add_subparsers(dest="command", required=True)
new = subparsers.add_parser("new", help="Create and register a collection")
new.add_argument("name")
new.add_argument("description")
checkout = subparsers.add_parser("checkout", help="Check out an existing AO-prepared issue branch")
checkout.add_argument("issue", type=int)
issue = subparsers.add_parser("issue", help="Read the example collection issue")
issue.add_argument("issue", type=int)
pr = subparsers.add_parser("pr", help="Open a pull request for an issue branch")
pr.add_argument("issue", type=int)
pr.add_argument("--body-file", type=Path, required=True)
args = parser.parse_args()
for name in ("FORGEJO_URL", "FORGEJO_TOKEN", "FORGEJO_USERNAME"):
    if not os.environ.get(name):
        parser.error(f"{name} is missing; hydrate the demo first")
if args.command == "new" and not os.environ.get("BACKSTAGE_URL"):
    parser.error("BACKSTAGE_URL is missing; hydrate the demo first")
if args.command != "new" and args.issue < 1:
    parser.error("issue must be positive")
backstage = os.environ.get("BACKSTAGE_URL", "").rstrip("/")
forgejo = os.environ["FORGEJO_URL"].rstrip("/")

try:
    if args.command == "new":
        run_template("ansible-collection", {"name": args.name, "description": args.description})
    elif args.command == "checkout":
        prepare_feature(args.issue)
    elif args.command == "issue":
        show_issue(args.issue)
    else:
        open_pr(args.issue, args.body_file)
except (KeyError, ValueError, RuntimeError, urllib.error.URLError, OSError, subprocess.CalledProcessError) as error:
    print(f"demo-goldenpath: {error}", file=sys.stderr)
    sys.exit(1)
