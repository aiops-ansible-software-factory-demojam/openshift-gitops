# Demojam Keycloak

`demojam-keycloak` owns a separate Red Hat build of Keycloak 26.6 instance and a
single-instance CNPG PostgreSQL database. Its issuer is
`https://demojam-keycloak.<ingress-domain>/realms/demo`. OpenShift console and
supported application logins use this instance. Bootstrap merges only its
`demojam-keycloak` identity provider into `OAuth/cluster`; existing providers
remain available for recovery. It does not modify the workshop Keycloak server.

The Deployment uses the documented Keycloak container `start` command. It
does not install another Keycloak operator or share that operator's CRDs with
the cluster-provided instance. An edge Route uses the default ingress
certificate; TLS verification remains enabled. The bootstrap host and
application containers must trust that certificate. Database storage uses
the cluster's default StorageClass.

GitOps creates the server, database, Service and Route. Bootstrap generates
credentials before workload startup, waits for Keycloak, and reconciles the
realm through the administration API. This supports updates and reruns;
the operator's realm import creates realms but does not update existing ones.

## Initial users

With no `DEMO_USERS_FILE`, bootstrap uses `bootstrap/users.example.json` and
creates `demo-user` in both `demo-users` and `demo-admins`. This disposable
demo account has administrator access to the applications and `cluster-admin`
access to OpenShift. The `demo-admins` Keycloak group also receives
`realm-management/realm-admin` for managing realm `demo`. The initial password for every new user
comes from `DEMO_USER_PASSWORD` in `.env`, defaulting to `changeme` when unset or
empty. For example:

```bash
DEMO_USER_PASSWORD='changeme'
```

Changing this setting does not reset existing accounts. To customize users:

```bash
cp bootstrap/users.example.json bootstrap/users.local.json
"${EDITOR:-vi}" bootstrap/users.local.json
# Set DEMO_USERS_FILE='bootstrap/users.local.json' in .env.
make bootstrap
```

`bootstrap/users.local.json` is ignored by Git. The JSON document contains a
nonempty `users` array. Each user supplies a unique `username` and `email`;
`firstName`, `lastName`, `enabled`, and `groups` are optional. Usernames use
lowercase letters, digits, `_` and `-`, start with a letter, and are at most
40 characters. Bootstrap reserves its service account names. Groups default
to `demo-users`; the supported groups are `demo-users` and `demo-admins`.
Password fields in the JSON file are rejected; `.env` supplies the shared
initial password. Keycloak administrative and client credentials remain random.

Initial passwords are stored in `demojam-keycloak/demo-user-passwords`. After
verifying the active cluster and identity, retrieve a user's initial password:

```bash
oc whoami --show-server
oc whoami
oc -n demojam-keycloak get secret demo-user-passwords \
  -o go-template='{{index .data "passwords.json" | base64decode}}' |
  jq -r '."demo-user"'
```

Keep the Secret private. Passwords changed in Keycloak are preserved on rerun;
the Secret records initial passwords and does not track later changes. User
profile, enabled state and the two managed group memberships reconcile from
the file. To revoke an account, retain its entry with `enabled: false` and run
`make identity`. Removing an entry does not delete its Keycloak account.
RHDH catalog users are generated from enabled entries in the same file.

## Application login

Each application has a distinct confidential OIDC client and secret with
specific callback URLs. The code flow issues `groups` claims; application
clients have password grants and service accounts disabled. A Keycloak browser
session is reused across applications, while each application owns its session
and authorization. Existing application sessions may outlive a group change;
sign out and sign back in to refresh claims. Logout does not guarantee logout
from every application.

| Application | Login and access |
| --- | --- |
| OpenShift console / CLI browser login | Native OpenID provider; configured `demo-admins` users join OpenShift group `demojam-admins`, bound to `cluster-admin` |
| OpenShift GitOps / Argo CD | Native OIDC; `demo-users` read only, `demo-admins` administrators |
| Developer Hub | Native OIDC; preferred username resolves to the generated catalog User; permission enforcement is disabled for unrestricted demo access |
| Forgejo | Native OIDC source `demojam-keycloak`; first login creates an account, `demo-admins` administrators |
| Keycloak | `demo-admins` can administer realm `demo` at `/admin/demo/console/`; the master realm retains its bootstrap administrator |
| Homepage | OAuth2 Proxy; navigation generated from the demo Routes, demo groups allowed; no separate administrator role |
| AAP gateway | Inventory-defined OIDC authenticator and group maps; demo organization membership, `demo-admins` superusers |
| Automation Orchestrator | Generic OIDC; demo groups map to built-in `users` / `admins` groups |
| Omnigent | Native OIDC with verified email identity and per-user session permissions; configured `demo-admins` emails populate its admin roster |
| RHEL nginx demo web app | OAuth2 Proxy fronts the public Route; demo group membership is required |
| Console extensions and monitoring views | Inherit OpenShift login where they use the cluster OAuth server |

For regular users, AAP organization membership does not itself grant permission
to execute every job template. Additional application permissions remain an
application concern. Bootstrap reconciles OpenShift group `demojam-admins`
from enabled users with `demo-admins` membership in the users file. GitOps owns
that group's `cluster-admin` binding; OIDC group claims alone do not populate
OpenShift Groups. Omnigent does not map OIDC groups
natively: its file-backed admin roster promotes listed emails, and removing an
email does not demote an already promoted administrator. Demote that user in
Omnigent when removing administrator access.

Automation retains dedicated credentials. AO and agent sandboxes call
Backstage with a static service token restricted to catalog, scaffolder and
proxy plugins, replacing guest-token generation. Forgejo API tokens and the
Omnigent API's native machine credentials serve the automation workflow.
Omnigent does not accept Keycloak access tokens directly as API bearer tokens:
AO exchanges its stored credential at Omnigent's `/oauth/token` endpoint for a
short-lived bearer token. The same flow is used by reset and reconciliation.
The workflow grants each enabled configured user read access to newly created
machine-owned sessions before sending the task. Existing sessions keep their
existing permissions; users can share their own sessions through Omnigent.

Databases, VM SSH, Kubernetes ServiceAccounts and application API tokens retain
their protocol-specific credentials. The web app's internal Service remains
available to the blackbox probe without browser login; its public Route requires
OIDC. There are no Omnigent proxy sidecars.
Forgejo hydration restores its OIDC source after a data reset.

The root credential Secret lives only in `demojam-keycloak`; consumers receive their
own client credentials. AAP receives its client secret through the runtime
dispatch credential and applies authentication with `ansible.platform` modules
from its supported execution environment. Bootstrap then registers the exact
callback generated by the gateway. Local application admin accounts remain
available for bootstrap and recovery. The Keycloak `bootstrap-admin` credential
is retained for repeated administration API reconciliation in this disposable
demo; production would use a dedicated administration service account and
remove the temporary bootstrap administrator.

After the initial bootstrap, use `make identity` to reconcile users and
application identity settings and workflow session sharing without rerunning VM
or sandbox provisioning.
This command requires the application stack and AAP authenticator to exist.
It does not rotate client secrets or reset user passwords. Normal bootstrap
also performs this reconciliation.

## Existing workshop installation

The previous `rhbk` Argo application adopted the preinstalled `keycloak`
namespace. The root application has pruning disabled, so replacing its values
entry does not remove that old child automatically. Before publishing and
bootstrapping this change on an existing installation, orphan the old child
Application. Removing its finalizer prevents deletion of its managed resources.
Preflight rejects an installation that still has that legacy ownership. To
detach it while preserving the workshop resources:

```bash
oc whoami --show-server
oc whoami
oc -n openshift-gitops get application rhbk \
  -o jsonpath='{.spec.source.path}{"\n"}'
# Verify the old path is cluster/rhbk, then stop root reconciliation briefly.
oc -n openshift-gitops patch application cluster --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
oc -n openshift-gitops patch application rhbk --type=merge \
  -p '{"metadata":{"finalizers":null},"spec":{"syncPolicy":{"automated":null}}}'
oc -n openshift-gitops delete application rhbk
# Publish/select the new GitOps revision, then run make bootstrap.
# Bootstrap restores the root application's normal automatic sync policy.
```

Preserve the workshop Keycloak server, database, operator, Routes and Secrets.
Do not delete the `keycloak` namespace. Demo users in the new realm can sign in
to OpenShift through the new provider; existing cluster usernames may require
explicit identity mapping if they collide with another provider. Existing local demo application data is
preserved; first OIDC login may create a distinct account in that application.

## References and validation

- [Red Hat build of Keycloak 26.6 containers](https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.6/html/server_configuration_guide/containers-)
- [Operator installation and shared CRDs](https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.6/html/operator_guide/installation-)
- [OpenShift OpenID provider configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/configuring-identity-providers)
- [Omnigent authentication](https://omnigent.ai/docs/collaborate/auth)
- [Realm import limitations](https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.6/html/operator_guide/realm-import-)

Local validation:

```bash
make render
shellcheck -S warning bootstrap/bootstrap.sh bootstrap/identity.sh bootstrap/homepage.sh
```

Browser login was verified on a fresh OpenShift 4.22.15 cluster on 2026-10-01
for Keycloak account management, Homepage, OpenShift console, Argo CD, Developer
Hub, Forgejo, Automation Orchestrator, Omnigent, AAP and the nginx webapp. The
same Keycloak browser session was reused across application logins. AAP's
organization mapping was applied through its Controller, and the RHEL VM,
nginx installation and blackbox probe were verified live.
