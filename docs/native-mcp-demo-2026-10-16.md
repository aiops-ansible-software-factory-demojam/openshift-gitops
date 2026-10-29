# AWS native MCP demo: configuration and executed commands

> Historical release/run record. Its refs, models and timings describe that run.
> For the current implementation, use the [tested-state guide](stable-demo-rehearsal.md).

The 2026-10-16 run used AWS in `us-east-2`, native guest MCP enabled, and
`qwen38-27b` through the Red Hat MaaS endpoint for both AO and Omnigent.
Both consumers used Chat Completions with thinking disabled. The focused
[environment example](../.env.demo.example) contains the effective settings
used for that run, with private credential values left blank. It now pins
repository refs and the discovered AMIs for the coordinated
[v0.1.0-alpha.2 release](releases/v0.1.0-alpha.2.md). Optional
`AO_MODEL_API_KEY` and `OMNIGENT_MODEL_API_KEY` fields allow separate model
keys; leaving them blank inherits `LITELLM_API_KEY`, as the recorded run did.

From the `openshift-gitops` checkout, prepare that configuration with:

```bash
cp .env.demo.example .env
chmod 600 .env
"${EDITOR:-vi}" .env
```

Populate `LITELLM_API_KEY`, `AWS_BOOTSTRAP_ACCESS_KEY_ID` and
`AWS_BOOTSTRAP_SECRET_ACCESS_KEY`, and supply the operator-owned
`aap_manifest.zip`. The original run already had a populated `.env` and ZIP;
the copy/edit commands above are preparation instructions for a new checkout.
No generated application credentials, route URLs or guest SSH keys belong in
this example. Account, availability zone, RHEL AMIs, storage class and routes
were discovered by bootstrap rather than supplied as overrides. The release
example now supplies those recorded AMI IDs explicitly.

## Commands verified against execution history

The lifecycle commands below were checked against this run's recorded tool
invocations and saved command output. They ran from the `openshift-gitops`
repository root. The original invocations put these four assignments directly
before each `bash` command; exporting them once is equivalent. Only log
redirection and timestamp/exit-status recording are omitted here.

```bash
export KUBECONFIG="$HOME/.kube/config"
export BOOTSTRAP_BRANCH='feature/rhel-mcp-rca'
export DEMOJAM_ANSIBLE_BRANCH='feature/rhel-mcp-rca'
export WEBAPP_MCP_ENABLED='true'

bash bootstrap/bootstrap.sh preflight
bash bootstrap/bootstrap.sh
```

Preflight started at 15:38:50 UTC and reported zero required failures.
Bootstrap ran from 15:39:29 to 16:17:50 UTC and exited 0. This was a fresh
cluster, so **no `demo-reset` command was run**. There were no separate manual
guest provisioning, permissive setup, nginx install or MCP install commands:
the full bootstrap dispatched those stages through AAP.

After bootstrap, the next command verified AO's authenticated TLS connection
and nine selected native MCP tools:

```bash
bash bootstrap/bootstrap.sh webapp mcp-verify
```

At 16:18:26 UTC, the single outage launch was:

```bash
bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable
```

The fault succeeded, producing Enforcing SELinux and HTTP 403/probe failure.
The alert, initial native MCP investigation, outage issue, webhook, feature
branch and coding session then ran automatically. No issue dispatch or coding
prompt was sent manually. Initial RCA completed without the AAP audit fallback.

The published collection commit was tested independently in its existing
managed sandbox after the coding session became idle. The runner sourced
`/etc/profile.d/molecule.sh`, exported `git archive` of the published SHA to a
temporary source directory, and used a separate temporary collection-install
directory. From that source directory it ran:

```bash
ansible-lint roles/nginx extensions/molecule/nginx
ansible-galaxy collection build --force --output-path "$validation_root"
export MOLECULE_GLOB='extensions/molecule/*/molecule.yml'
molecule test --all
```

Here `validation_root` was the runner's temporary parent directory, separate
from both its `source` and `collections` subdirectories. Each check exited 0;
Molecule completed convergence, zero-change idempotence, verification and
destruction on both RHEL 9 and RHEL 10. The tracked coding workspace remained
clean at the published SHA. A duplicate installed-collection warning was
checked: all role/plugin/metadata code files and package metadata matched the
archive, with no extra role files.

Only after those checks passed was the demo Forgejo fix merged, guarded by
its tested head SHA and unchanged base. The final lifecycle commands were:

```bash
bash bootstrap/bootstrap.sh webapp nginx
bash bootstrap/bootstrap.sh webapp verify-enforcing
```

Recovery started at 17:50:17 UTC; both commands exited 0 by 17:51:41 UTC.
The first deployed the fix once. The second only verified state: Enforcing,
HTTP 200 and probe success. Outage alerts cleared naturally. No second fault
or post-recovery Permissive setup was run.

## Revisions and findings

| Component | Revision used |
| --- | --- |
| openshift-gitops | `172dab95bbe97dd660e938b07bd8984e26d29d46` |
| demojam-ansible | `b736fda0f9e05ee896921960292372ec7cbebcf7` |
| Original demo.webapp collection | `93dc37aafa79e6c48d95427a29cee7f43ac6d6b2` |
| Tested agent fix | `8d4fd82db0792af567ce728de301575d12278df7` |
| Verified Forgejo merge | `50742b2242f29b1cd5739c8c8b2448492c5f7b50` |

At the time of this run, the implementation GitHub PRs remained open; only
the demo Forgejo fix was merged. The GitHub PRs were subsequently merged for
`v0.1.0-alpha.2`. The commands above retain the original branch selections,
and the table identifies the commits actually validated. Release preparation
adds tag fetching, source pins and documentation; it does not represent
another full bootstrap or fault/recovery run.

The run had two findings: real Keycloak issuance capped the requested 90-day
MCP token at the realm's 10-hour session limit, and a repeat alert during
coding hit a model rate limit in both primary and fallback RCA. Its AAP audit
job succeeded. The original investigation, independent tests and recovery
succeeded. This live run covered AWS; it did not establish CNV network behavior.

Private evidence remains under the ignored
`.rendered/native-mcp-acceptance/` directory: `bootstrap-command-history.json`
contains the six original lifecycle invocations, `preflight.log` and
`bootstrap.log` record setup, and `independent-checks/`, `fault.log`,
`recovery.log`, `recovery-verify.log` and `report.md` record validation and
recovery. No bootstrap or fault was rerun while preparing this command record.
