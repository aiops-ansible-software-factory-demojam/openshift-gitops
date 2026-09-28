# Omnigent and Agent Sandbox

Omnigent serves the API in `omnigent` and uses the Red Hat Agent Sandbox
operator to create one `Sandbox` per managed session in `omnigent-sandboxes`.
The server ServiceAccount can manage Sandboxes, inspect their Pods, and create
short-lived launch-token Secrets only in that runner namespace. The runner has
no Kubernetes API token. Its fixed non-root UID uses the `nonroot-v2` SCC.

`omnigent-model` in `omnigent-sandboxes` holds the OpenCode Go key and inline
OpenCode configuration for `demo/glm-5.3-flash`. `omnigent-agent` in `omnigent`
holds the `demo` API agent specification, whose YAML name is `opencode-demo`.
Bootstrap creates both; no key is
committed. The image built from `image/` adds OpenCode and Ansible tooling to
Omnigent's host image. The server and host base images use the same Omnigent
v0.15.0 release. The Sandbox has a 5 GiB HOME claim, which survives idle
suspension, and uses the cluster's normal container runtime. This demo has no
warm pool or separate sandbox network policy.

The `omnigent-dispatch` Automation Orchestrator workflow calls the internal
Omnigent API to create a managed session and then send its task. A sidecar
protects Omnigent's Route with the same machine credential for inspection.
The Forgejo and Backstage feature flow is a later stage of this demo.

Check the resources with the selected kubeconfig:

```bash
KUBECONFIG="$HOME/.kube/config" oc -n omnigent rollout status deployment/omnigent
KUBECONFIG="$HOME/.kube/config" oc -n omnigent-sandboxes get builds,imagestream,sandboxes,pods
```

See [Omnigent's Kubernetes sandbox configuration](https://omnigent.ai/docs/reference/configuration/kubernetes)
for the provider's lifecycle and optional warm-pool settings.
