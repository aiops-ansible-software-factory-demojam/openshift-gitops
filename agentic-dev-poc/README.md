# Manual OpenCode POC

Automation Orchestrator starts one OpenCode run inside an OpenShell sandbox. The runner, gateway, and identity client are GitOps applications:

- `cluster/openshell` — OpenShell 0.0.116
- `cluster/agentic-poc` — runner, Keycloak realm, image builds

The Agent Sandbox API is the controller already installed by `cluster/agent-sandbox-operator`. It serves `agents.x-k8s.io/v1beta1`, which this OpenShell release accepts. A second controller is not installed.

## Externally provisioned credentials

Git contains Secret references and client identifiers only. Before syncing Part 2, provision these values through the demo environment's secret-management process:

- `agentic-poc/runner-auth`, with `token` and `oidc-client-secret` keys;
- `openshell/openshell-credential-kek`, with a `key-encryption-key` key;
- Keycloak confidential clients `agentic-poc-runner` and `agentic-poc-admin`, including their service-account role mappings and the `openshell-cli` audience mapper; and
- the AO bearer credential, updated by `scripts/publish-workflows.py` from `RUNNER_TOKEN`.

The runner OIDC Secret must match the externally provisioned `agentic-poc-runner` client. The runtime client receives `openshell-user`; the separate bootstrap client receives `openshell-admin` and is never mounted into the runner. The KEK must be generated before any model provider credential is registered.

Values previously committed on this branch must be treated as disclosed. Part 2 must revoke and replace both Keycloak client secrets and the runner bearer token. Because no model credential has been registered yet, replace the KEK Secret before provider bootstrap rather than attempting an in-place re-encryption. For later rotation, re-encrypt or recreate provider credentials before removing the old KEK; replacing a KEK alone makes existing encrypted provider data unreadable.

For a manual demo-only provisioning pass, use generated values without echoing them:

```bash
oc -n agentic-poc create secret generic runner-auth \
  --from-literal=token="$RUNNER_TOKEN" \
  --from-literal=oidc-client-secret="$OPENSHELL_OIDC_CLIENT_SECRET" \
  --dry-run=client -o yaml | oc apply -f -

oc -n openshell create secret generic openshell-credential-kek \
  --from-literal=key-encryption-key="$OPENSHELL_CREDENTIAL_KEK" \
  --dry-run=client -o yaml | oc apply -f -
```

Do not enable shell tracing around these commands. Rotate the AO credential by setting the new `RUNNER_TOKEN` and rerunning the publisher; it updates the existing credential rather than creating a duplicate.

## Before the runner can call a model

Create the model credential. It is not stored in Git.

```bash
umask 077
oc -n agentic-poc create secret generic agentic-poc-model \
  --from-file=api_key=/secure/path/openai-api-key \
  --from-literal=base_url=https://api.openai.com/v1 \
  --from-literal=model=gpt-4.1-mini
```

Using `--from-file` keeps the API key out of the process argument list. Do not
enable shell tracing. In a short-lived bootstrap Pod using the separate admin
OIDC Secret, expose that Secret key as `OPENAI_API_KEY`, then configure both the
provider and the protected route:

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

The bootstrap Pod must also mount the existing OpenShell mTLS files. Delete the
Pod and any temporary namespace-local copy of the admin OIDC Secret afterward;
do not mount either credential into the runner or sandbox.

AO workflow HTTP uses `https://runner.apps.cluster-qb5wm.dyn.redhatworkshops.io`. AO workers trust public CAs through certifi and do not trust the OpenShift service CA, so the route uses the cluster ingress certificate. The bearer token is still required.

Publish the workflows after the runner Secret exists:

```bash
AO_PASSWORD="$AO_PASSWORD" RUNNER_TOKEN="$RUNNER_TOKEN" \
  python3 scripts/publish-workflows.py
```

TLS verification is always enabled. Set `AO_CA_FILE` to a CA bundle only when the AO endpoint is not signed by the system trust store. Run the unit tests with `PYTHONPATH=runner python3 -m unittest tests.test_runner`, or run the repository-wide `make test` target.

## Current cluster status

The PR runner and OpenCode images are built and deployed by the temporary
`agentic-poc-pr2` and `openshell-pr2` Argo CD Applications. Their exact source
revisions and image digests are recorded in `versions.lock.yaml`. The native
gateway path has been exercised through create, exact readiness, upload, exec,
bounded download, and confirmed deletion. See `docs/part2-handoff.md` for the
evidence and temporary-resource cleanup procedure.

No model API key or OpenShell provider is present. The live checks therefore do
not establish inference or end-to-end AO acceptance. Local tests use a mock
OpenShell client; the handoff distinguishes those tests from real gateway and AO
checks.
