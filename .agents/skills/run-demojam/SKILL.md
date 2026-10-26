---
name: run-demojam
description: Run an authorized end-to-end SELinux outage demo with automated independent CI feedback to the same agent; merge the Forgejo fix only when its published commit passes tests, then deploy and verify it.
---

# Run the demo

Work from the `openshift-gitops` repository. Use the existing populated `.env`
and `export KUBECONFIG="$HOME/.kube/config"`. Use the `github-auth` skill for
GitHub operations. Bootstrap and lifecycle logic live in `bootstrap/bootstrap.sh`.

When the user asks for a reset and demo, that authorizes the disposable demo
reset, the test-gated Forgejo merge and the recovery launch below. Preserve AAP.
Do not merge the GitHub implementation PRs as part of this demo.

## Separate application scenarios

For the Python vulnerability scenario, follow `docs/invoice-lightwell-demo.md`. For `both`, reset/bootstrap once, then run both incidents: the invoice detection from that runbook and the nginx fault sequence below. Deploying both baselines does not trigger either incident. Record each scenario's issue, session, PR, tests and outcome separately; a failed scenario stays failed while the other can still run. The invoice collection is `demo.pythonapp` in `ansible-collection-demo.pythonapp`, deployed only to `pythonapps`; nginx remains in `demo.webapp` on `webapps`. With both deployed, the nginx host may be permissive during setup while the Python host must remain enforcing. Preserve independent validation and the human merge and production approval gates. Keep CI feedback and repair attempts visible in the same session and PR; never hide failed checks.

## Walk through

1. Select the requested models independently in the ignored `.env`. Keep
   credentials private. For Qwen decisions and Go Haiku coding, use
   `AO_MODEL_PROVIDER=litellm`, `AO_MODEL=qwen38-27b`,
   `OMNIGENT_MODEL_PROVIDER=opencode-go`,
   `OMNIGENT_MODEL=claude-haiku-5-5` and `OMNIGENT_MODEL_PROTOCOL=anthropic`.
   Empty overrides inherit the existing shared provider defaults; see
   [.env.example](../../../.env.example) for endpoint/key and reasoning overrides.
   Verify access to both selected providers before resetting. Before fault
   launch, verify AO's integration/workflow model and the native Omnigent
   model/SDK separately. Apply Qwen reasoning checks only to a Qwen consumer.
   Preserve the selected source
   branches so bootstrap seeds the intended published implementation.

2. Run these commands once, in order, and record their start/end times:

   ```bash
   bash bootstrap/bootstrap.sh demo-reset --confirm-demo-reset
   bash bootstrap/bootstrap.sh
   ```

   Bootstrap protects both collection main branches with human review and
   application-specific independent checks. On an existing deployment, run
   `make webapp-protect` to reconcile that policy before triggering an incident.

   Require a healthy HTTP probe, Permissive SELinux, the unfixed collection,
   both EDA listeners running, and no old incident sessions or fix PRs.
   Bootstrap provisions the VM, runs the separate permissive setup playbook,
   then installs nginx. Do not prepare or repair the guest yourself.

3. Start the incident clock and run the fault job once:

   ```bash
   bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable
   ```

   Confirm Enforcing and an HTTP failure. Observe, without changing anything:
   alert → RCA → Forgejo issue → webhook → EDA/AO → Omnigent session → PR.
   Do not dispatch the issue manually, send the model a message, review its
   code, edit its branch, compact/resume it, or change the guest or cluster.

4. Observe the existing authoring session and incident PR. PR submission does
   not complete authoring. The agent uses `demo-goldenpath ci <issue> --wait`
   (with the Python repository option for invoice incidents) until independent
   CI passes for the current head. Exit 75 means pending, not success.

5. AO runs independent CI automatically against the exact published SHA.
   Both collections require lint, a build, all unit tests and every Molecule
   scenario with cleanup. Python additionally requires trusted RHEL 9/10
   acceptance and a raw AAP-checkout preflight. Nginx additionally requires
   the identical authored regression to fail on the original code and pass
   on the repaired code, followed by trusted durable relabel recovery.
   The validator receives only disposable-test credentials. A separate trusted
   publisher binds its result to the exact job/project/SHA, publishes the
   required reviewer status and sanitized diagnostics on the same PR.

   Failed CI is normal feedback: the same agent fixes the same branch and PR,
   reruns local checks after its final edit, pushes a new commit and waits for
   CI on that commit. AO resumes an idle author with failed diagnostics; it
   does not create a second session or validate a failed unchanged SHA again.
   An agent can temporarily idle between asynchronous callbacks; AO must keep
   the authoring task unfinished until its latest head is independently green.
   Do not manually edit the candidate, coach it with operator fixes, forge a
   status or weaken tests. Automated feedback and agent-authored repair are
   intended workflow behavior, not hidden operator intervention. Record the
   failed SHAs and subsequent validation jobs. Cleanup or infrastructure
   failures that require operator action remain blocked, never green.

6. Only after all checks pass, merge the Forgejo PR using the tested head SHA
   as the merge guard. Recheck that its base has not changed. Confirm the PR
   is merged and `main` contains the merge commit. Resolve an uncertain merge
   response with reads; do not blindly submit another merge request.

7. The updated AO execution observes the exact human merge and launches
   `webapp_promote`. Inspect its saved source SHA and incident/PR identities,
   then approve the matching native AAP production gate once. The trusted
   recheck and pinned deployment run automatically. If this session has not
   authorized production approval, leave that gate for the operator.
   Do not also launch the baseline `webapp_nginx` recovery job.

   ```bash
   bash bootstrap/bootstrap.sh webapp verify-enforcing
   ```

   Require the AO deployment-proof step and native workflow to succeed,
   Enforcing, HTTP 200, a successful probe and resolved outage alerts under
   normal alert handling. The command only verifies state. Do not run a
   permissive setup or another enforcement job after deployment. If recovery
   fails, record that outcome and stop without repairing it.

8. Report the result, tested/merged SHAs, job IDs, stage timings, prompts,
   test failures and any deviations. Distinguish automatic incident-to-PR
   time from operator tests, merge and recovery. Keep credentials, raw native
   reasoning, live hostnames and runtime IDs out of committed reports.

Read-only observation is allowed. Normal reset/bootstrap, the single fault
launch, independent tests, a passing-test merge, and one recovery launch are
the intended operator actions. Everything else that changes the run must be
reported as intervention; never conceal it as part of a successful demo.
