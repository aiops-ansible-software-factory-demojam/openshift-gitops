#!/usr/bin/python3
"""Prepare an issue branch through Backstage before AO launches an agent."""

import base64
import json
import os
import time
from threading import Lock
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlsplit
import re
from urllib.request import Request, urlopen


BACKSTAGE = os.environ["BACKSTAGE_URL"].rstrip("/")
REPOSITORIES = {"demo-owner/ansible-collection-demo.webapp", "demo-owner/ansible-collection-demo.pythonapp"}
DEFAULT_REPOSITORY = "demo-owner/ansible-collection-demo.webapp"


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


_incident_locks = {}
_incident_locks_guard = Lock()


def prepare(number, repository=DEFAULT_REPOSITORY):
    # Claims are repository-scoped: duplicate EDA deliveries must not create
    # another author or deployment, including when issue numbers overlap.
    if repository not in REPOSITORIES:
        raise ValueError("Unsupported application repository")
    with _incident_locks_guard:
        lock = _incident_locks.setdefault((repository, number), Lock())
    with lock:
        return _prepare(number, repository)


def _prepare(number, repository=DEFAULT_REPOSITORY):
    if repository not in REPOSITORIES:
        raise ValueError("Unsupported application repository")
    token = os.environ["BACKSTAGE_TOKEN"]
    issue = backstage(
        f"/api/proxy/forgejo/repos/{repository}/issues/{number}",
        token=token,
        missing_ok=True,
    )
    if not issue or issue.get("pull_request") or issue.get("state") != "open":
        raise ValueError(f"Issue #{number} is not an open collection issue")
    branch = f"feature/issue-{number}"
    branch_path = quote(branch, safe="")
    path = f"/api/proxy/forgejo/repos/{repository}/branches/{branch_path}"
    existing = backstage(path, token=token, missing_ok=True)
    task_id = None
    if not existing:
        result = backstage(
            "/api/scaffolder/v2/tasks",
            "POST",
            {
                "templateRef": "template:default/ansible-collection-feature",
                "values": {"issue_number": number, "repository": repository},
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
        "repository": repository,
        "branch": branch,
        "task_id": task_id,
        "author_required": not existing,
        "issue": {key: issue.get(key) or "" for key in ("title", "body", "html_url")},
    }


INVOICE_REPOSITORY = "demo-owner/ansible-collection-demo.pythonapp"


def incident_pr(number, repository, pr_number=None, head_sha=None, require_merged=False):
    """Read one incident PR; fail closed on ambiguity, closure or source drift."""
    if repository not in REPOSITORIES:
        raise ValueError("Unsupported application repository")
    if type(number) is not int or number < 1:
        raise ValueError("issue_number must be a positive integer")
    if head_sha is not None and not re.fullmatch(r"[0-9a-f]{40}", head_sha):
        raise ValueError("Expected a full source commit")
    token = os.environ["BACKSTAGE_TOKEN"]
    root = f"/api/proxy/forgejo/repos/{repository}"
    if pr_number is not None:
        if type(pr_number) is not int or pr_number < 1:
            raise ValueError("pr_number must be a positive integer")
        matches = [backstage(f"{root}/pulls/{pr_number}", token=token)]
    else:
        matches = []
        for page in range(1, 101):
            batch = backstage(f"{root}/pulls?state=all&limit=50&page={page}", token=token)
            matches.extend(pr for pr in batch if pr.get("head", {}).get("ref") == f"feature/issue-{number}")
            if len(batch) < 50:
                break
        else:
            raise ValueError("PR history exceeds the reconciliation bound")
    if not matches:
        return {"ready": False, "merged": False, "number": 0, "head_sha": ""}
    if len(matches) != 1:
        raise ValueError("Multiple PRs match this incident; resolve ambiguity before continuing")
    pr = matches[0]
    if (pr["head"]["ref"] != f"feature/issue-{number}" or pr["base"]["ref"] != "main"
            or any(pr[side].get("repo", {}).get("full_name") != repository for side in ["head", "base"])):
        raise ValueError("PR does not belong to the expected incident branch and repository")
    sha = pr["head"]["sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("PR has no exact source identity")
    if head_sha is not None and sha != head_sha:
        raise ValueError("PR head changed after validation; a new independent validation is required")
    merged = pr.get("merged", False)
    if pr["state"] == "closed" and not merged:
        raise ValueError("PR was closed without merging; remediation stops")
    if merged and not require_merged:
        raise ValueError("PR was already merged; inspect its original remediation execution")
    if merged:
        # Forgejo's compare API has no merge-base/ancestry field. Walk its
        # bounded main history rather than trusting the PR's merged flag alone.
        for page in range(1, 101):
            commits = backstage(f"{root}/commits?sha=main&limit=50&page={page}", token=token)
            if any(commit.get("sha") == sha for commit in commits):
                break
            if len(commits) < 50:
                raise ValueError("The tested source commit is not contained in main")
        else:
            raise ValueError("Main ancestry exceeds the reconciliation bound")
    return {"ready": not pr.get("draft", False), "merged": merged,
            "number": pr["number"], "head_sha": sha, "url": pr["html_url"],
            "base_sha": pr.get("merge_base", "")}


def invoice_pr(number, pr_number=None, head_sha=None, require_merged=False):
    return incident_pr(number, INVOICE_REPOSITORY, pr_number, head_sha, require_merged)


def ci_candidate(number, repository):
    """A failed SHA waits for a new commit; only an independently green SHA is done."""
    result = incident_pr(number, repository)
    result.update(ci_passed=False, ci_failed=False, validation_required=False)
    if not result['ready']:
        return result
    root = '/api/proxy/forgejo/repos/' + repository
    status = backstage(root + '/commits/' + result['head_sha'] + '/status', token=os.environ['BACKSTAGE_TOKEN'])
    context = 'webapp/regression-validation' if repository == DEFAULT_REPOSITORY else 'invoice/ec2-validation'
    prefix = 'webapp-ci-v2 ' if repository == DEFAULT_REPOSITORY else 'invoice-ci-v2 '
    checks = [s for s in status.get('statuses', []) if s.get('context') == context
              and (s.get('creator') or {}).get('login') == 'demo-reviewer'
              and s.get('description', '').startswith(prefix)]
    result['validation_required'] = not checks
    if checks:
        result['ci_failed'] = checks[0].get('status') in ['failure', 'error']
        result['ci_passed'] = checks[0].get('status') == 'success'
        if result['ci_passed']:
            expected = ('webapp-ci-v2 base=' + result['base_sha'] + ' checks=passed red=passed green=passed durable=passed'
                        if repository == DEFAULT_REPOSITORY else 'invoice-ci-v2 checks=passed')
            result['ci_passed'] = checks[0].get('description') == expected
            result['validation_required'] = not result['ci_passed']
    return result


def webapp_pr(number, pr_number=None, head_sha=None, require_merged=False):
    result = incident_pr(number, DEFAULT_REPOSITORY, pr_number, head_sha, require_merged)
    if result["ready"]:
        require_webapp_regression(result["base_sha"], result["head_sha"])
    if result["merged"]:
        root = "/api/proxy/forgejo/repos/" + DEFAULT_REPOSITORY
        receipt = backstage(root + "/commits/" + result["head_sha"] + "/status", token=os.environ["BACKSTAGE_TOKEN"])
        checks = [check for check in (receipt.get("statuses") or [])
                  if check.get("context") == "webapp/regression-validation"]
        expected = "webapp-ci-v2 base=" + result["base_sha"] + " checks=passed red=passed green=passed durable=passed"
        if (not checks or checks[0].get("status") != "success" or checks[0].get("description") != expected
                or (checks[0].get("creator") or {}).get("login") != "demo-reviewer"):
            raise ValueError("Independent webapp/regression-validation must pass for this exact head and merge base")
        result["regression_validated"] = True
    return result


def require_webapp_regression(base_sha, head_sha):
    """Structural gate; independent red/green execution is still required.

    Forgejo preserves merge_base after merging; base.sha then points at main.
    """
    if not isinstance(base_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", base_sha) or base_sha == head_sha:
        raise ValueError("The regression check requires the incident's original merge base")
    path = "/api/proxy/forgejo/repos/" + DEFAULT_REPOSITORY + "/contents/extensions/molecule/nginx/tasks/regression.yml"
    token = os.environ["BACKSTAGE_TOKEN"]
    candidate = backstage(path + "?ref=" + head_sha, token=token, missing_ok=True)
    original = backstage(path + "?ref=" + base_sha, token=token, missing_ok=True)

    def contents(record):
        if not isinstance(record, dict) or record.get("type") != "file" or record.get("encoding") != "base64":
            raise ValueError("The nginx PR must add or extend extensions/molecule/nginx/tasks/regression.yml")
        try:
            return base64.b64decode(record["content"]).decode().strip()
        except (KeyError, ValueError, UnicodeError, TypeError):
            raise ValueError("The nginx regression file must contain readable Ansible tasks") from None

    authored = contents(candidate)
    if not authored or (original and authored == contents(original)):
        raise ValueError("The nginx PR must add incident-specific regression tasks; unchanged tests are insufficient")


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        parsed = urlsplit(self.path)
        if parsed.path == "/healthz":
            return self.respond(200, {"status": "ok"})
        if parsed.path not in ["/invoice/pr", "/webapp/pr", "/invoice/candidate", "/webapp/candidate", "/invoice/validated", "/webapp/validated"]:
            return self.respond(404, {"error": "Unknown path"})
        try:
            query = parse_qs(parsed.query, strict_parsing=True)
            if any(len(v) != 1 for v in query.values()) or set(query) - {"issue_number", "pr_number", "head_sha", "require_merged"}:
                raise ValueError("Unsupported PR query")
            if query.get("require_merged", ["false"])[0] not in ["true", "false"]:
                raise ValueError("Invalid merge requirement")
            if parsed.path.endswith(('/candidate', '/validated')):
                if set(query) != {'issue_number'}:
                    raise ValueError('Candidate discovery only accepts an issue number')
                repository = INVOICE_REPOSITORY if parsed.path.startswith('/invoice/') else DEFAULT_REPOSITORY
                result = ci_candidate(int(query['issue_number'][0]), repository)
                if parsed.path.endswith('/validated') and not result['ci_passed']:
                    raise ValueError('The current PR head has not passed independent CI')
                return self.respond(200, result)
            observer = invoice_pr if parsed.path == "/invoice/pr" else webapp_pr
            result = observer(int(query["issue_number"][0]),
                                int(query["pr_number"][0]) if "pr_number" in query else None,
                                query.get("head_sha", [None])[0],
                                query.get("require_merged", ["false"])[0] == "true")
            self.respond(200, result)
        except ValueError as error:
            self.respond(409, {"error": str(error)})
        except KeyError:
            self.respond(409, {"error": "Incident PR has incomplete source or regression metadata."})
        except (HTTPError, URLError, RuntimeError):
            self.respond(502, {"error": "PR observation unavailable; no remediation action was taken."})

    def do_POST(self):
        if self.path != "/prepare":
            return self.respond(404, {"error": "Unknown path"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size < 1024:
                raise ValueError("Expected a small JSON request")
            body = json.loads(self.rfile.read(size))
            number = body["issue_number"]
            repository = body.get("repository", DEFAULT_REPOSITORY)
            if not isinstance(repository, str) or repository not in REPOSITORIES:
                raise ValueError("Unsupported application repository")
            if isinstance(number, str) and number.isdecimal():
                number = int(number)
            if type(number) is not int or number < 1:
                raise ValueError("issue_number must be a positive integer")
        except (ValueError, KeyError) as error:
            self.respond(400, {"error": str(error)})
            return
        try:
            self.respond(200, prepare(number, repository))
        except ValueError as error:
            self.respond(400, {"error": str(error)})
        except (RuntimeError, URLError, KeyError, TypeError, OSError) as error:
            self.respond(502, {"error": str(error)})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
