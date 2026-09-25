# OpenShell gateway

OpenShell 0.0.116 uses the Red Hat Agent Sandbox operator but schedules each
sandbox with the ordinary CRI-O runtime. The gateway is internal only and
uses plaintext, unauthenticated gRPC because clients reach it through cluster
Services or an authenticated `oc port-forward`. Its persistent SQLite data and
sandbox workspaces use the cluster's default StorageClass. Bootstrap generates
the gateway encryption key in the `openshell` namespace.

`omnigent-opencode` is an OpenShift Docker BuildConfig. It adds the pinned
OpenCode CLI to Omnigent's OpenShell-compatible host image and installs the
sandbox egress policy. The ImageStream tag is the sandbox image used by both
OpenShell's CLI defaults and Omnigent's managed sessions. It must finish building
before the first sandbox can start.

OpenShell 0.0.116 requires the sandbox ServiceAccount to use the privileged SCC;
the binding is limited to `openshell/openshell-sandbox`. The gateway does not set
`runtimeClassName` and does not need a specially labeled worker.

Use `bash scripts/sandbox.sh create --name demo --detach` from the repository
root to launch a container through the gateway.
