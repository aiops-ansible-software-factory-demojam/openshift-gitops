The `demo.greetings.nginx` role installs and starts nginx using the distribution's
nginx account. Add an optional `nginx_uid` parameter to select the numeric UID used
by **nginx worker processes** on Rocky Linux 9.

Acceptance criteria:

- Omitting `nginx_uid` preserves the package-provided UID and existing behavior.
- Setting `nginx_uid: 1500` makes the nginx account and running worker processes use
  UID 1500. The privileged master process may remain root to bind port 80.
- Validate the argument as a positive, non-root integer; do not silently reuse a UID
  owned by an unrelated account or impose an arbitrary range cap (for example,
  65535 is valid when unoccupied).
- Handle changing an existing installation from UID 1500 to 1501: update necessary
  nginx-owned writable paths recursively, including existing files under
  `/var/log/nginx` and `/var/cache/nginx`; stop running nginx workers before
  changing their account UID, then restore HTTP service. Linux `usermod`
  rejects UID changes while that user has running processes. Leave configuration
  and static content root-owned.
- A second run with the same UID reports no changes.
- Add/update role defaults, argument specs, and README examples.
- Report how you verified default behavior, a custom UID, UID changes,
  invalid/conflicting UIDs, HTTP 200, and the actual worker process UID.
- Exercise any UID-dependent Ansible condition or template with a YAML integer
  value (`nginx_uid: 1500`) using `ansible-playbook`. A syntax check or a
  rewritten approximation of the expression does not prove it executes.
- If using Ansible `getent_passwd` facts, verify the UID field using an existing
  account whose UID and primary GID differ. Apply that field consistently to
  conflict detection and current-UID comparison; a second run must remain
  unchanged after the UID differs from its original GID.
- Run ansible-lint, default yamllint, and a collection build. If this sandbox
  cannot run a real Rocky Linux 9 service, mark those runtime checks unverified;
  do not modify the sandbox's account database to simulate them.
- Keep changes scoped to this role and its docs; open a feature-branch PR
  against `main` with `Closes #<this issue number>`. Do not merge it.
