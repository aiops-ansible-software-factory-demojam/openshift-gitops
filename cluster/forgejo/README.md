# Forgejo demo repositories

Forgejo hosts writable demo copies of four GitHub repositories. It runs with
SQLite and Git data on one disposable PVC; GitOps owns the workloads and storage.

| GitHub source | Forgejo destination |
| --- | --- |
| `ansible-collection-demo.webapp` | `demo-owner/ansible-collection-demo.webapp` |
| `ansible-collection-demo.pythonapp` | `demo-owner/ansible-collection-demo.pythonapp` |
| `ansible-collection-template` | `demo-agent/ansible-collection-template` |
| `demojam-ansible` | `demo-owner/demojam-ansible` |

## Refresh and run

After [bootstrap](../../README.md), run from the repository root with
`KUBECONFIG="$HOME/.kube/config"`:

```bash
make demo-hydrate     # Refresh repository sources and agent/Backstage credentials
```

Hydration commits the selected GitHub contents to Forgejo `main` without
importing source history. Existing feature branches and PRs survive, but changes
merged only into Forgejo `main` are replaced by the next refresh. Edit the GitHub
source to change the baseline. [seed.json](seed.json) declares sources;
incident issues are created by the alert and CVE assessment workflows.
GitHub fetches use repository-scoped ghapp credentials.

Override the source refs in the root `.env` with
`ANSIBLE_COLLECTION_TEMPLATE_BRANCH`, `ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH`,
`ANSIBLE_COLLECTION_DEMO_PYTHONAPP_BRANCH`, and `DEMOJAM_ANSIBLE_BRANCH`. Nonempty shell values override `.env`, then
`seed.json`'s `source_branch`, then `main`. Despite their historical names,
these settings accept branches and lightweight or annotated tags. All configured
sources must fetch before any baseline changes. An ambiguous branch/tag name
requires `refs/heads/...` or `refs/tags/...`. These settings apply to bootstrap,
hydration, and reset; `BOOTSTRAP_BRANCH` separately selects the GitOps source.

The release defaults in `seed.json` also record each source's exact
`source_commit`; bootstrap rejects a moved release tag. [release.json](../../release.json)
records the same pins. An explicit override to a different development ref
bypasses that release pin. Forgejo destinations stay on writable `main` so
the agent can open and merge a remediation PR.

Backstage creates the issue branch before AO launches the agent. The agent
implements and checks the change, then opens a PR against `main`. nginx AO
finishes at handoff; the operator independently validates, merges and deploys.
Python AO continues through independent acceptance, human merge, native AAP
approval, deployment proof and business verification. Follow the
[workflow guide](../automation-orchestrator/workflows/README.md).
Bootstrap registers repository issue webhooks for both application collections. It sends authenticated JSON to the separate Forgejo EDA event
stream. Newly opened webapp incidents containing the outage marker and RCA
start AO's `omnigent-remediation` workflow; other issue actions and PRs do not
dispatch agents. Python security incidents have their own repository/marker route.
There is no Forgejo Actions runner; Python's required `invoice/ec2-validation`
status comes from the independent AAP validator.

## Login and reset

Browser login uses [demo Keycloak](../demojam-keycloak/README.md).
`demo-admins` maps to site administrators. Local automation identities are
`demo-owner`, `demo-agent`, and `demo-reviewer`, with passwords equal to their
usernames on this disposable instance. The latter two have write access;
hydration creates scoped agent tokens in Kubernetes Secrets and ignored `.state/`.

`make demo-reset` removes demo sessions, VMs, and disks, wipes Forgejo, and
reseeds baseline repositories and tokens. Incident issues are created only by
the detection workflows; no starter README issue is seeded. It also refreshes AAP and AO and
removes generated collection catalog entries. Demo VMs remain absent; other
Omnigent sessions and AAP/AO history remain.

To wipe only Forgejo, stop active agent sessions first, then run:

```bash
bash scripts/feature-demo.sh reset --confirm-forgejo
```

Reset erases repositories, issues, PRs, users, tokens, and webhooks. GitOps
self-heal must be enabled to recreate the PVC. Start a new agent session to
receive the new token. A `Retain` reclaim policy may leave the old PV; reset
is not secure erasure.

## Source publication guard

The sandbox PR helper checks committed source before any push/PR API request.
Tracked collection-installation caches and absolute or escaping symlinks are
rejected. Normal requirements files and internal relative links remain valid.
Both collections ignore generated caches and exclude them from Galaxy artifacts.
Hydrating an application baseline replaces a demo fix on Forgejo main; do not
hydrate either collection during an active or completed incident you need to preserve.
Use the [tested source selector table](../../docs/stable-demo-rehearsal.md) rather
than assuming seed defaults include open implementation PRs.
