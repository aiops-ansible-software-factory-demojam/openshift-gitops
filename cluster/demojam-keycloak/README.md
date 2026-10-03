# Demo login and users

`demojam-keycloak` provides realm `demo` on Red Hat build of Keycloak 26.6.
Bootstrap configures OpenShift and application login, retaining existing
providers for recovery. The host and applications must trust the
ingress certificate; TLS verification stays enabled.

## Sign in or configure users

The default `demo-user` belongs to `demo-users` and `demo-admins`, with
application administrator and OpenShift cluster-admin access. New users get
`.env`'s `DEMO_USER_PASSWORD` (default `changeme`). Changing that
setting does not reset existing passwords.

From the repository root:

```bash
cp bootstrap/users.example.json bootstrap/users.local.json
"${EDITOR:-vi}" bootstrap/users.local.json
# Set DEMO_USERS_FILE='bootstrap/users.local.json' in .env.
make identity
```

Use `make bootstrap` for a first install; `make identity` requires the
application stack and AAP authenticator.

The JSON file must have a nonempty `users` array with unique usernames
and emails. Usernames start with a letter, use lowercase letters, digits, `_`
or `-`, and have at most 40 characters; service account names are reserved.
Optional fields: `firstName`, `lastName`, `enabled`, and `groups`. Groups
default to `demo-users`; only `demo-users` and `demo-admins` are supported.
Password fields are rejected. Credentials stay in Kubernetes Secrets.
`demo-user-passwords` records initial passwords only; keep it private.

To revoke an account, retain its entry with `enabled: false` and run
`make identity`. Removing an entry does not delete the account. Reconciliation
preserves changed passwords and does not rotate client secrets.

## Access and sessions

| Application | Demo access |
| --- | --- |
| OpenShift / Argo CD | Admins get cluster-admin / Argo administration; Argo users are read only |
| Developer Hub / Forgejo | Hub permission enforcement is disabled; Forgejo admins get site administration |
| AAP / AO | AAP admins are superusers; AO maps users/admins to its built-in groups |
| Keycloak | Admins manage realm `demo` at `/admin/demo/console/` |
| Homepage / webapp | Demo group membership required |
| Omnigent | Verified email, per-session permissions, and a configured admin email roster |

AAP organization membership alone does not grant every job permission. Removing
an email from Omnigent's admin roster does not demote an existing administrator;
demote that user in Omnigent too. Sign out and back in after group changes;
sessions and logout are independent.

AO exchanges its machine credential at Omnigent's `/oauth/token`;
Keycloak tokens are not Omnigent API tokens. Enabled configured users get
read access to new workflow sessions;
existing sessions keep their permissions. The internal webapp probe bypasses
browser login, while its public Route requires OIDC.

## Migrating an old workshop installation

If preflight reports legacy `rhbk` ownership, verify its source path is
`cluster/rhbk`, then detach it before selecting the new published revision:

```bash
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
oc -n openshift-gitops get application rhbk -o jsonpath='{.spec.source.path}{"\n"}'
oc -n openshift-gitops patch application cluster --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
oc -n openshift-gitops patch application rhbk --type=merge \
  -p '{"metadata":{"finalizers":null},"spec":{"syncPolicy":{"automated":null}}}'
oc -n openshift-gitops delete application rhbk
make bootstrap
```

Bootstrap restores root auto-sync. Preserve the workshop server, database,
operator, Routes, and Secrets. Do not delete the `keycloak` namespace.
Provider username collisions may require explicit identity mapping.
