# Forgejo demo repositories

Forgejo hosts writable demo copies of three GitHub repositories. It runs with
SQLite and Git data on one disposable PVC; GitOps owns the workloads and storage.

| GitHub source | Forgejo destination |
| --- | --- |
| `ansible-collection-demo.webapp` | `demo-owner/ansible-collection-demo.webapp` |
| `ansible-collection-template` | `demo-agent/ansible-collection-template` |
| `demojam-ansible` | `demo-owner/demojam-ansible` |

## Refresh and run

After [bootstrap](../../README.md), run from the repository root with
`KUBECONFIG="$HOME/.kube/config"`:

```bash
make demo-hydrate     # Refresh repositories and print the starter issue URL
make demo ISSUE=N     # Replace N with that positive issue number
```

Hydration commits the selected GitHub contents to Forgejo `main` without
importing source history. Existing feature branches and PRs survive, but changes
merged only into Forgejo `main` are replaced by the next refresh. Edit the GitHub
source to change the baseline. [seed.json](seed.json) declares sources; the
[starter issue](fixtures/readme-test-issue.md) requests one README line.
GitHub fetches use repository-scoped ghapp credentials.

Override the source branches in the root `.env` with
`ANSIBLE_COLLECTION_TEMPLATE_BRANCH`, `ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH`,
and `DEMOJAM_ANSIBLE_BRANCH`. Nonempty shell values override `.env`, then
`seed.json`'s `source_branch`, then `main`. All three branches must fetch before
any baseline changes. Tags are not accepted. These settings apply to bootstrap,
hydration, and reset; `BOOTSTRAP_BRANCH` separately selects the GitOps source.

Backstage creates the issue branch before AO launches the agent. The agent
implements and checks the change, then opens a PR against `main`. AO finishes
at handoff; follow the [Omnigent session](../omnigent/README.md) for the outcome.
Bootstrap registers a repository webhook for issue events in the example
collection. It sends authenticated JSON to the separate Forgejo EDA event
stream. Newly opened webapp incidents containing the outage marker and RCA
start AO's `omnigent-remediation` workflow; other issue actions and PRs do not
dispatch agents. There is no CI runner.

## Login and reset

Browser login uses [demo Keycloak](../demojam-keycloak/README.md).
`demo-admins` maps to site administrators. Local automation identities are
`demo-owner`, `demo-agent`, and `demo-reviewer`, with passwords equal to their
usernames on this disposable instance. The latter two have write access;
hydration creates scoped agent tokens in Kubernetes Secrets and ignored `.state/`.

`make demo-reset` removes demo sessions, VMs, and disks, wipes Forgejo, and
reseeds its repositories, issue, and tokens. It also refreshes AAP and AO and
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
