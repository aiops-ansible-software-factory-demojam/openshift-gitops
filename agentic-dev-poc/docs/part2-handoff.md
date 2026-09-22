# Part 2 deployment handoff

Status as of 2026-09-22: the corrected PR revision is deployed on the separate
`cluster-qb5wm.dyn.redhatworkshops.io` demo cluster, the native OpenShell data
path is verified, and AO-to-runner connectivity remains active under a narrow
PR override. End-to-end inference and the full AO acceptance matrix remain
blocked because no authorized model credential is available. Nothing in this
document claims live readiness from mock tests or stub output.

## Deployed revisions

- Runner source: `ea1d0ef832a8509b2b82787ba8bac34610350b36`
- Runner image: `image-registry.openshift-image-registry.svc:5000/agentic-poc/agentic-poc-runner@sha256:e54c1a29d64c92f4dc34cb8c3e26c16f05ff033754be31faa2f7065e4d92e0b0`
- OpenCode source: `aca9fc838ac24d16c1fcf3138a810fe1dbc3a267`
- OpenCode image: `image-registry.openshift-image-registry.svc:5000/agentic-poc/agentic-poc-opencode@sha256:34fa6cf50924ec0bd7f4bad3ac24eb05dd5dbf40799364f6fe7261a1c6add691`

Both source revisions are commits on `feat/openshell-opencode-poc`, not builds
from `main`. The runner contains OpenShell 0.0.116, OpenSSH 9.9, and works with
an OpenShift-assigned UID. The sandbox image includes the pinned OpenCode
version and the `find`, `ip`, and `nsenter` helpers required by OpenShell
0.0.116. The sandbox service account alone has the cross-namespace image-pull
grant for the private agent image.

The wrapper now parses the complete event stream incrementally while retaining
at most 10 MiB in `events.ndjson`. Error and final-status metadata, a truncation
flag, and parser uncertainty are bounded separately. An error after the saved
log cap cannot be lost; malformed JSON, invalid UTF-8, or a greater-than-1-MiB
event line makes the wrapper fail closed.

## Live evidence

The real gateway path was run from the built runner image:

1. create a native OpenShell sandbox;
2. wait for the exact structured `Ready` phase;
3. upload project input;
4. execute in `/sandbox/work`;
5. receive and validate the bounded workspace archive;
6. delete the sandbox and confirm it is absent.

The corrected image was then exercised again with a synthetic OpenCode stub
from the deployed runner. The installed wrapper was present, exited zero for a
valid event stream, and reported `event_count=1`, `log_truncated=false`, and
`validation=passed`. The downloaded runner-PVC evidence survived deletion of
the task Pod and PVC:

- `out/result.json`: SHA-256 `ecf6bb96a2fdeca66e6f6fb040b34584888999fce8779f5992bdc26e09c8f0d8`
- `project.py`: SHA-256 `2921fc2c922adc90199e383c9b877d1c5a06f75ea749455a602514af3331b89d`
- `test_project.py`: SHA-256 `ad968f6d5928b0fe15ec53049ef1745d9199316b734322e1319276a2542e1436`

This proves the real gateway and bounded file-transfer path for the corrected
image. The stub used no model and is not inference acceptance.

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
credential count is one. HTTPS from the AO worker reaches only the exact runner
host: missing and invalid bearer tokens both return 401, while the stored
credential permits workflow calls.

A live serialization execution (`dbd53494…b234`, runner `poc-5cd4…5c34`)
preserved quotes, a newline, Unicode (`café 雪`), and literal shell metacharacters
byte-for-byte in the runner database. With no provider configured, it failed
and cleaned up without leaving a task Pod or PVC.

That run also showed that script nodes are disabled in the installed AO. The
failure branch now uses an authenticated, non-retrying HTTP request for a
deterministic nonexistent artifact. A second AO execution (`339a7406…44a9`,
runner `poc-0227…832c`) reached `get_result` with `state=failed` and
`cleanup.state=complete`, selected the failed switch port, and ended red on the
expected 404. OpenCode exited 250, and the sandbox was deleted. This is a
truthful AO failure-path test, not a successful inference run.

A direct live runner check returned the same run ID for an active retry,
rejected a different request with 409 while the slot was occupied, and created
only one sandbox for runner run `poc-d361…6028`. Cancellation during
provisioning ended in `state=cancelled`, `cleanup.state=complete`; no task Pod
or PVC remained. This exercises live ownership and cancellation without
claiming paid-session or model-backed acceptance.

That run exposed an AO-version-specific switch syntax defect. The workflow now
uses AO's Python-style `and` expression rather than `&&`. Tests against the real
AO evaluator selected `completed` only for execution success plus confirmed
cleanup. Execution failure and cleanup failure both selected `failed`.

## Tests run for the corrected revision

`make test` passed on 2026-09-22. It ran 34 Python regressions, including the
actual wrapper with a stub OpenCode subprocess; repository shell tests; strict
render validation; and `kubeconform` over 159 resources (105 valid, 0 invalid,
0 errors, and 54 skipped for unavailable schemas). `git diff --check` also
passed. These are local/mock checks and do not replace model-backed acceptance.

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

`agentic-poc-model` is absent, `openshell provider list --names` is empty, and
`openshell inference get` reports that neither the user nor system route is
configured. Neither an OpenAI nor Azure OpenAI credential is available in the
authorized session profiles. Consequently these gates have
not been run:

- protected inference, streaming, and a real tool-call/result cycle;
- three successful sequential AO tasks, including a non-smoke task;
- paid-session idempotency and restart behavior with a real model call;
- genuinely long-running model cancellation; and
- the complete AO success-path acceptance matrix.

Do not substitute a fake key or infer success from the mock suite. The smallest
remaining operator action is to supply a limited-budget POC credential from a
protected file through the approved secret process:

```bash
umask 077
oc -n agentic-poc create secret generic agentic-poc-model \
  --from-file=api_key=/secure/path/openai-api-key \
  --from-literal=base_url=https://api.openai.com/v1 \
  --from-literal=model=gpt-4.1-mini
```

Then use the separate bootstrap identity and a short-lived Pod to expose the
Secret key as `OPENAI_API_KEY`. With OpenShell 0.0.116,
`--credential OPENAI_API_KEY` reads the value from that process environment.
Provider bootstrap is rerunnable and route selection is a separate required
step:

```bash
if openshell -g openshell provider get openai >/dev/null 2>&1; then
  openshell -g openshell provider update openai --credential OPENAI_API_KEY
else
  openshell -g openshell provider create \
    --name openai \
    --type openai \
    --credential OPENAI_API_KEY
fi
openshell -g openshell inference set --provider openai --model gpt-4.1-mini
openshell -g openshell inference get
```

Do not use `--gateway-insecure` or `--no-verify`. Delete the bootstrap Pod and
any namespace-local admin Secret copy after configuration. Verify provider
streaming and a tool call in a single bounded sandbox before starting the AO
acceptance sequence.

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
both target namespaces. AO connectivity remains active at handoff. The
`automation-orchestrator` child Application temporarily targets
`feat/openshell-opencode-poc`; the root `cluster` Application has an exact
ignore rule only for that child's `/spec/source/targetRevision` and has
`RespectIgnoreDifferences=true`. The resulting allowlist preserves
`kubernetes.default.svc` and adds only
`runner.apps.cluster-qb5wm.dyn.redhatworkshops.io`.

After the PR is merged and the normal `main` Applications have successfully
synced the promoted manifests, remove the two PR Applications with orphan
propagation, then remove the temporary Roles and RoleBindings. Confirm the
normal Applications own healthy resources before deleting any temporary
objects. Do not delete the OpenShell PVC or rotate the encryption key as part
of that cleanup.

After `main` contains the runner host and the normal AO Application has synced,
restore the child target revision to `main`, then remove only the exact root
ignore rule and the added `RespectIgnoreDifferences=true` option. Verify the AO
worker still has both allowed hosts before removing the PR ownership controls.

The rotated external Secrets, Keycloak clients, AO credential, and gateway PVC
are durable prerequisites, not disposable test resources. The built image
streams and Build history may be pruned later under the cluster's normal image
retention policy.
