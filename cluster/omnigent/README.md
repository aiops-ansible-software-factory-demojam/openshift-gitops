# Omnigent

Omnigent's server creates managed sessions through the internal OpenShell
gateway. Its session database is a single CNPG instance and artifacts live on a
5 GiB PVC. The server uses the OpenShell-specific image with the SDK installed;
it has no Kubernetes runner Job permissions or Kata node selector. Managed hosts
and runners use Omnigent's single-user callback over the internal Service. An
NGINX sidecar protects the HTTPS Route with Basic Auth; bootstrap creates its
credential for Automation Orchestrator. The Route is the only public API path.

Bootstrap creates two Secrets: `omnigent-model` contains the OpenCode inference
key and generated OpenCode provider config, and `omnigent-agent` contains the
seeded `opencode-go-test` agent specification. The model can be OpenCode Go
(`kimi-k3` by default) or the official OpenAI API (`gpt-4.1-mini` by default).
The key is injected into each OpenShell sandbox and forwarded to OpenCode.

The gateway registration is a plaintext internal Service endpoint stored in
`omnigent-gateway-config`. Omnigent's managed host image has an OpenShell egress
policy admitting the Omnigent callback, selected model endpoints, package
registry, and the Forgejo demo Service. Open the Omnigent Route with the generated
machine credential to inspect sessions in the UI.
