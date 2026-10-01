# Demo Homepage

The landing page uses the homelab's pinned Homepage image and dark slate layout.
An OAuth2 Proxy sidecar authenticates users through `demojam-keycloak`; the Route
exposes only the proxy. Members of `demo-users` or `demo-admins` can sign in.

Bootstrap creates the `homepage-endpoints` and `homepage-links` ConfigMaps,
then fills `services.yaml` from the actual Routes after the stack is ready.
The page links to the applications, OpenShift console and monitoring, Argo CD,
and the demo realm's account page. Additional Routes in demo application
namespaces are included automatically. No API credentials or Kubernetes service
account permissions are needed by Homepage.

Links refresh at bootstrap time. After adding or changing Routes, run
`make homepage-refresh` to regenerate them and reload the page. Homepage's
native discovery supports Ingress and HTTPRoute, rather than OpenShift Routes.
Generated links do not grant access; each destination enforces its own roles.

On every container start, a lifecycle hook regenerates Homepage's prebuilt page
from the mounted settings so the title and layout apply before users arrive.
An init container copies the page cache to a writable volume for OpenShift's
assigned user ID; the application runs without additional security privileges.
