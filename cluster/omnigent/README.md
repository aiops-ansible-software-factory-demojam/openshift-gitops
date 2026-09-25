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
seeded `opencode-demo` agent specification. The same base URL, model name, and
API key inputs configure OpenCode Go (`kimi-k3` by default) or LiteLLM MaaS
(`gpt-oss-120b` in the supplied example). Both use OpenCode's
`@ai-sdk/openai-compatible` adapter for `/v1/chat/completions`.
The key is injected into each OpenShell sandbox and forwarded to OpenCode.
The sandbox image writes the generated provider definition to the sandbox user's
OpenCode config on login; Omnigent imports it into each isolated native session.

The gateway registration is a plaintext internal Service endpoint stored in
`omnigent-gateway-config`. Omnigent's managed host image has an OpenShell egress
policy admitting the Omnigent callback, selected model endpoints, package
registry, and the Forgejo demo Service. Open the Omnigent Route with the generated
machine credential to inspect sessions in the UI.
