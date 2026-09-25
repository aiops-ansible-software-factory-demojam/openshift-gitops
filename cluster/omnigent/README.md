# Omnigent

Omnigent's server creates managed sessions through the internal OpenShell
gateway. Its session database is a single CNPG instance and artifacts live on a
5 GiB PVC. The server uses the OpenShell-specific image with the SDK installed;
it has no Kubernetes runner Job permissions, Kata node selector, or public Route.

Bootstrap creates two Secrets: `omnigent-model` contains the OpenCode inference
key and generated OpenCode provider config, and `omnigent-agent` contains the
seeded `opencode-go-test` agent specification. The model can be OpenCode Go
(`kimi-k3` by default) or the official OpenAI API (`gpt-4.1-mini` by default).
The key is injected into each OpenShell sandbox and forwarded to OpenCode.

The gateway registration is a plaintext internal Service endpoint stored in
`omnigent-gateway-config`. Omnigent's managed host image has an OpenShell egress
policy admitting the Omnigent callback, selected model endpoints, package
registry, and the Forgejo demo Service. Use `oc -n omnigent port-forward
svc/omnigent 8000:8000` to inspect sessions in the UI.
