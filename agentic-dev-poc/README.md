# Manual OpenCode POC

Automation Orchestrator starts one OpenCode run inside an OpenShell sandbox. The runner, gateway, and identity client are GitOps applications:

- `cluster/openshell` — OpenShell 0.0.116
- `cluster/agentic-poc` — runner, Keycloak realm, image builds

The Agent Sandbox API is the controller already installed by `cluster/agent-sandbox-operator`. It serves `agents.x-k8s.io/v1beta1`, which this OpenShell release accepts. A second controller is not installed.

## Before the runner can call a model

Create the model credential. It is not stored in Git.

```bash
oc -n agentic-poc create secret generic agentic-poc-model \
  --from-literal=api_key="$OPENAI_API_KEY" \
  --from-literal=base_url=https://api.openai.com/v1 \
  --from-literal=model=gpt-4.1-mini
```

AO workflow HTTP uses `https://runner.apps.cluster-qb5wm.dyn.redhatworkshops.io`. AO workers trust public CAs through certifi and do not trust the OpenShift service CA, so the route uses the cluster ingress certificate. The bearer token is still required.

Publish the workflows after the runner Secret exists:

```bash
AO_PASSWORD=changeme RUNNER_TOKEN="$(oc -n agentic-poc get secret runner-auth -o jsonpath='{.data.token}' | base64 -d)" \
  python3 scripts/publish-workflows.py
```

Run the unit tests with `PYTHONPATH=runner python3 -m unittest tests.test_runner`.

## Current cluster status

The OpenShell gateway is running in `openshell` with TLS, client-certificate verification, and OIDC. Its pod is admitted under `restricted-v2`. A sandbox using the pinned community base image was created, executed `echo`, and deleted; its workspace PVC went away with it. The sandbox service account is the only identity granted the `privileged` SCC. The `agentic-poc` Keycloak realm issues a client-credentials token for `agentic-poc-runner` with audience `openshell-cli` and role `openshell-user`.

The runner Deployment is waiting for `agentic-poc-runner:1.0.0`, which is not built yet. No model API key is present, so inference routing is not configured. Argo CD will not keep the new Orchestrator allowlist or these applications until this branch is on `main`.

