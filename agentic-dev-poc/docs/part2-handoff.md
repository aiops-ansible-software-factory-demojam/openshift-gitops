# Part 2 deployment handoff

Status as of 2026-09-22: the PR revision is deployed on the separate
`cluster-qb5wm.dyn.redhatworkshops.io` demo cluster and the native OpenShell
data path is verified. End-to-end inference and the full AO acceptance matrix
remain blocked because no authorized model credential is available. Nothing in
this document claims live readiness from mock tests.

## Deployed revisions

- Runner source: `ea1d0ef832a8509b2b82787ba8bac34610350b36`
- Runner image: `image-registry.openshift-image-registry.svc:5000/agentic-poc/agentic-poc-runner@sha256:e54c1a29d64c92f4dc34cb8c3e26c16f05ff033754be31faa2f7065e4d92e0b0`
- OpenCode source: `59dd8f3a536ecf9ef3f0840bef62aff06d548715`
- OpenCode image: `image-registry.openshift-image-registry.svc:5000/agentic-poc/agentic-poc-opencode@sha256:39948eb861bb56e678eb3323e6a6020715783d31b51d82e6de598290d12c39f3`

Both source revisions are commits on `feat/openshell-opencode-poc`, not builds
from `main`. The runner contains OpenShell 0.0.116, OpenSSH 9.9, and works with
an OpenShift-assigned UID. The sandbox image includes the pinned OpenCode
version and the `find`, `ip`, and `nsenter` helpers required by OpenShell
0.0.116. The sandbox service account alone has the cross-namespace image-pull
grant for the private agent image.

## Live evidence

The real gateway path was run from the built runner image:

1. create a native OpenShell sandbox;
2. wait for the exact structured `Ready` phase;
3. upload project input;
4. execute in `/sandbox/work`;
5. receive and validate the bounded workspace archive;
6. delete the sandbox and confirm it is absent.

The downloaded runner-PVC evidence survived deletion of the task Pod and PVC:

- `out/result.json`: 94 bytes, SHA-256 `fc540d8ffe5f848d99490bc73877d677b5e423ba61029c4efcadf07273cceac5`
- `project.py`: 28 bytes, SHA-256 `aecc013c518523ca22b7e3780f87002f5cae13fabc369f2f59a1faf7058f8c76`
- `tests/test_project.py`: 73 bytes, SHA-256 `3df682ce18df926b3230a51626d5cae9c874fa459e5837630346a528e54a96cd`

A real symlink to `/etc/passwd` and a 101 MiB sparse output were each rejected
before destination materialization. The temporary receive archive was removed
after both failures. The configured limits remain 100 MiB and 2,000 files.

Sandbox isolation was also tested against numeric addresses to avoid confusing
DNS timeouts with policy enforcement. Connections to the Kubernetes API, the
runner, AO, the metadata endpoint, and an unrelated service were denied. No
environment-variable names matching token, secret, password, credential,
kubeconfig, API-key, or private-key markers were present. Cleanup was confirmed
and no task Pod or workspace PVC remained.

AO workflow publication updated the existing objects rather than duplicating
them. The manual and cancel workflow counts are each one, and the runner bearer
credential count is one. A live AO execution (`fa614321…2876`) reached the
runner and created runner run `poc-a57b…b10e`. With no provider configured,
OpenCode exited 250; the runner reported `state=failed` and
`cleanup.state=complete`, and the sandbox was deleted. This is a truthful
failure-path test, not a successful inference run.

That run exposed an AO-version-specific switch syntax defect. The workflow now
uses AO's Python-style `and` expression rather than `&&`. Tests against the real
AO evaluator selected `completed` only for execution success plus confirmed
cleanup. Execution failure and cleanup failure both selected `failed`.

## Credential and storage state

Previously exposed Keycloak client secrets and the runner bearer token were
rotated without printing their values. The existing AO bearer credential was
updated in place. The runner uses the runtime OIDC client; the administrative
bootstrap identity is not mounted into the runner.

Gateway storage was inspected before rotating the credential-encryption key.
There were no encrypted provider records, so the key was replaced without
deleting or recreating the gateway PVC. Future rotations must migrate or
recreate provider records before retiring the old key.

## Exact blocker

`agentic-poc-model` is absent, and neither an OpenAI nor Azure OpenAI credential
is available in the authorized session profiles. Consequently these gates have
not been run:

- protected inference, streaming, and a real tool-call/result cycle;
- three successful sequential AO tasks, including a non-smoke task;
- paid-session idempotency and restart behavior with a real model call;
- genuinely long-running model cancellation; and
- the complete AO success-path acceptance matrix.

Do not substitute a fake key or infer success from the mock suite. Supply a
limited-budget POC credential through the approved secret process, then use the
separate bootstrap identity to register it without placing its value on the
command line. With OpenShell 0.0.116, `--credential OPENAI_API_KEY` reads the
value from the bootstrap process environment:

```bash
openshell -g openshell provider create \
  --name openai \
  --type openai \
  --credential OPENAI_API_KEY
```

Do not use `--gateway-insecure`. Verify provider streaming and a tool call in a
single bounded sandbox before starting the AO acceptance sequence.

## Reproducible operation

Always verify the demo target first:

```bash
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
```

Publish or update the workflows after the external Secrets exist. This updates
the named AO credential and workflows in place and exports their definitions:

```bash
export AO_PASSWORD
export RUNNER_TOKEN
python3 agentic-dev-poc/scripts/publish-workflows.py
unset AO_PASSWORD RUNNER_TOKEN
```

Start `manual-opencode-poc` in AO with a `prompt` string. Its execution ID is
also the runner idempotency key. To cancel, start `cancel-opencode-poc` with the
returned `run_id`. Direct runner API troubleshooting uses verified TLS:

```bash
curl --fail --silent --show-error \
  -H "Authorization: Bearer $RUNNER_TOKEN" \
  "https://runner.apps.cluster-qb5wm.dyn.redhatworkshops.io/v1/runs/$RUN_ID"

curl --fail --silent --show-error \
  -H "Authorization: Bearer $RUNNER_TOKEN" \
  "https://runner.apps.cluster-qb5wm.dyn.redhatworkshops.io/v1/runs/$RUN_ID/result"

curl --fail --silent --show-error \
  -H "Authorization: Bearer $RUNNER_TOKEN" \
  "https://runner.apps.cluster-qb5wm.dyn.redhatworkshops.io/v1/runs/$RUN_ID/artifacts/$ARTIFACT_NAME" \
  --output "$ARTIFACT_NAME"
```

Read `ARTIFACT_NAME` from the result's `artifacts` list; do not construct an
untrusted path locally.

Use the cancel workflow for normal operation. For bounded API diagnosis only:

```bash
curl --fail --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $RUNNER_TOKEN" \
  "https://runner.apps.cluster-qb5wm.dyn.redhatworkshops.io/v1/runs/$RUN_ID/cancel"
```

## Temporary resources and promotion

The live PR test uses Argo CD Applications `openshell-pr2` and
`agentic-poc-pr2`, plus `pr2-gitops-sync` and `pr2-gitops-extra` bindings in
both target namespaces. The AO allowlist was changed only for the test window
and has already returned to the `main` value of `kubernetes.default.svc`.

After the PR is merged and the normal `main` Applications have successfully
synced the promoted manifests, remove the two PR Applications with orphan
propagation, then remove the temporary Roles and RoleBindings. Confirm the
normal Applications own healthy resources before deleting any temporary
objects. Do not delete the OpenShell PVC or rotate the encryption key as part
of that cleanup.

The rotated external Secrets, Keycloak clients, AO credential, and gateway PVC
are durable prerequisites, not disposable test resources. The built image
streams and Build history may be pruned later under the cluster's normal image
retention policy.
