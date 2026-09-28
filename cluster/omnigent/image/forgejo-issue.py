#!/usr/bin/env python3
"""Small, credential-safe Git/Forgejo bridge for the disposable demo repo."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


REPOSITORY = "demo-owner/ansible-collection-demo"


def api(method, path, body=None):
    base = os.environ["FORGEJO_URL"].rstrip("/")
    token = os.environ["FORGEJO_TOKEN"]
    payload = None if body is None else json.dumps(body).encode()
    request = Request(
        f"{base}/api/v1{path}",
        data=payload,
        method=method,
        headers={
            "Authorization": f"token {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urlopen(request, timeout=60) as response:
            return json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"Forgejo {method} {path} returned HTTP {error.code}") from None
    except URLError:
        raise RuntimeError(f"Forgejo {method} {path} is unreachable") from None


def issue(number):
    item = api("GET", f"/repos/{REPOSITORY}/issues/{number}")
    if item.get("pull_request") or item.get("state") != "open":
        raise RuntimeError(f"Issue #{number} is not an open issue")
    return item


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


def checkout(number):
    item = issue(number)
    directory = Path.cwd() / f"issue-{number}"
    remote = f"{os.environ['FORGEJO_URL'].rstrip('/')}/{REPOSITORY}.git"
    if not directory.exists():
        git(Path.cwd(), "clone", remote, str(directory))
    if git(directory, "remote", "get-url", "origin", capture=True) != remote:
        raise RuntimeError(f"{directory} has a different origin")
    branch = f"issue-{number}"
    if branch not in git(directory, "branch", "--format=%(refname:short)", capture=True).splitlines():
        git(directory, "checkout", "-b", branch, "origin/main")
    else:
        git(directory, "checkout", branch)
    git(directory, "config", "user.name", "Automation Developer")
    git(directory, "config", "user.email", "agent@example.test")
    print(f"Repository: {directory}\nBranch: {branch}")
    print(f"Issue #{number}: {item['title']}\n\n{item.get('body') or ''}")


def submit(number, body_file):
    item = issue(number)
    directory = Path.cwd() / f"issue-{number}"
    if not directory.exists():
        directory = Path.cwd()
    branch = f"issue-{number}"
    remote = f"{os.environ['FORGEJO_URL'].rstrip('/')}/{REPOSITORY}.git"
    if git(directory, "remote", "get-url", "origin", capture=True) != remote:
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
    if not re.search(rf"(?i)\bcloses\s+#{number}\b", body):
        body += f"\n\nCloses #{number}"
    git(directory, "push", "-u", "origin", branch)
    pulls = api("GET", f"/repos/{REPOSITORY}/pulls?state=all&limit=100")
    existing = next(
        (pull for pull in pulls if pull.get("head", {}).get("ref") == branch), None
    )
    if existing:
        print(existing["html_url"])
        return
    pull = api(
        "POST",
        f"/repos/{REPOSITORY}/pulls",
        {"head": branch, "base": "main", "title": item["title"], "body": body},
    )
    print(pull["html_url"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    start = subcommands.add_parser("start", help="Read issue, clone, and create branch")
    start.add_argument("issue", type=int)
    finish = subcommands.add_parser("submit", help="Push committed branch and open PR")
    finish.add_argument("issue", type=int)
    finish.add_argument("--body-file", type=Path, required=True)
    args = parser.parse_args()
    if args.issue < 1:
        parser.error("issue must be positive")
    for name in ("FORGEJO_URL", "FORGEJO_TOKEN", "FORGEJO_USERNAME"):
        if not os.environ.get(name):
            parser.error(f"{name} is missing; hydrate the Forgejo demo first")
    try:
        if args.command == "start":
            checkout(args.issue)
        else:
            submit(args.issue, args.body_file)
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"forgejo-issue: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
