---
name: run-demojam
description: Run an authorized end-to-end SELinux outage demo without coaching or repairing the coding agent; merge the Forgejo fix only when its published commit passes tests, then deploy and verify it.
---

# Run the demo

Work from the `openshift-gitops` repository. Use the existing populated `.env`
and `export KUBECONFIG="$HOME/.kube/config"`. Use the `github-auth` skill for
GitHub operations. Bootstrap and lifecycle logic live in `bootstrap/bootstrap.sh`.

When the user asks for a reset and demo, that authorizes the disposable demo
reset, the test-gated Forgejo merge and the recovery launch below. Preserve AAP.
Do not merge the GitHub implementation PRs as part of this demo.

## Separate application scenarios

For the Python vulnerability scenario, follow `docs/invoice-lightwell-demo.md`. For `both`, reset/bootstrap once, then run both incidents: the invoice detection from that runbook and the nginx fault sequence below. Deploying both baselines does not trigger either incident. Record each scenario's issue, session, PR, tests and outcome separately; a failed scenario stays failed while the other can still run. The invoice collection is `demo.pythonapp` in `ansible-collection-demo.pythonapp`, deployed only to `pythonapps`; nginx remains in `demo.webapp` on `webapps`. With both deployed, the nginx host may be permissive during setup while the Python host must remain enforcing. Preserve independent validation and the human merge and production approval gates. Do not change or restart an agent's run to hide a failure.

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

4. Wait for the coding session to become idle. Record the actual issue, PR,
   branch and published head SHA; do not assume their numbers. Use no overall
   incident deadline unless the user supplies one. If the session ends without
   an eligible PR, report its actual failure and stop. Do not repair or restart
   the flow to get a passing result.

5. Independently test that exact published commit in its existing managed
   sandbox, without asking the model to run anything. Require a clean tracked
   worktree and matching HEAD before and after. Export `git archive <head-sha>`
   into a temporary source directory and test that export. Use a separate
   temporary collection installation root first on the native search path.
   Keep source and installation directories separate: Molecule installs the
   local collection during dependency setup and can delete its own source
   when those paths coincide.
   This excludes untracked local fixes and leaves the coding workspace alone:

   ```bash
   ansible-lint roles/nginx extensions/molecule/nginx
   ansible-galaxy collection build --force --output-path /tmp
   make molecule
   ```

   Also require changed `extensions/molecule/nginx/tasks/regression.yml`, included
   from the scenario's verify play. After the normal checks, run the trusted
   `demojam-ansible/playbooks/webapp/validate-regression.yml` from the same sandbox
   with `webapp_source_directory`, the exact `webapp_candidate_sha`, and Forgejo's
   preserved `merge_base` as `webapp_base_sha`. Use the operator-controlled
   controller checkout, never an agent-authored copy of that runner. It exports
   the two revisions, requires identical authored assertions to fail on every
   original guest and pass on every repaired guest, checks durable relabel/HTTP
   recovery, and destroys both sets of guests. Copy its `result.json` receipt to
   the operator machine and use trusted `playbooks/webapp/publish-regression.yml`
   there to publish `webapp/regression-validation` as `demo-reviewer`. The
   publisher requires the exact candidate/base SHAs and complete receipt. Keep
   its operator token outside the coding sandbox; an agent-created status is
   rejected even if it says success. Missing, unchanged, always-green
   or infrastructure-failing regressions cannot satisfy the gate. Do not create
   that success status manually or merge without it.

   Use the sandbox's preloaded dependencies and native test environment.
   A plain `oc exec` does not inherit the native harness overrides: the test
   kubeconfig is `/home/omnigent/.config/molecule/kubeconfig`, and the collection
   path is `/home/omnigent/.ansible/collections:/usr/share/ansible/collections`.
   Local cluster commands still use `~/.kube/config`.

   For an AWS deployment, source `/etc/profile.d/molecule.sh` in the existing
   sandbox instead of imposing the CNV kubeconfig. It selects `PROVISIONER=aws`,
   the scoped credential file and pinned network/images. Require both RHEL 9
   and RHEL 10 to complete the selected scenario. Do not switch providers or
   substitute local credentials when testing the candidate.

   Capture each real exit status separately. Require every discovered
   Molecule scenario to complete its full lifecycle, including idempotence,
   verification and destruction. A trailing successful shell command or a
   successful build does not establish that Molecule passed. If any required
   candidate check fails, leave the PR open and report the failure. Do not
   fix the candidate, send feedback or rerun a failed assertion. If your own
   isolated runner fails before scenario execution, correct only that runner
   and disclose the failed attempt; keep the commit, tests and dependencies
   unchanged. Never count that failed attempt as a pass.

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
