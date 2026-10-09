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

## Walk through

1. Select the requested model in the ignored `.env`. Keep credentials private.
   For OpenCode Go Haiku, use `MODEL_PROVIDER=opencode-go`,
   `OPENCODE_GO_MODEL=claude-haiku-5-5` and `OPENCODE_GO_PROTOCOL=anthropic`.
   Verify provider access before resetting. Preserve the selected source
   branches so bootstrap seeds the intended published implementation.

2. Run these commands once, in order, and record their start/end times:

   ```bash
   bash bootstrap/bootstrap.sh demo-reset --confirm-demo-reset
   bash bootstrap/bootstrap.sh
   ```

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
   branch and published head SHA; do not assume their numbers. If there is
   no eligible PR within 30 minutes of the fault launch, report the incomplete
   stage and stop. Do not repair or restart the flow to get a passing result.

5. Independently test that exact published commit in its existing managed
   sandbox, without asking the model to run anything. Require a clean tracked
   worktree and matching HEAD before and after. Export `git archive <head-sha>`
   into a temporary `ansible_collections/demo/webapp` directory and test that
   export. Prepend its collection root to the native collection search path.
   This excludes untracked local fixes and leaves the coding workspace alone:

   ```bash
   ansible-lint roles/nginx extensions/molecule/nginx
   ansible-galaxy collection build --force --output-path /tmp
   make molecule
   ```

   Use the sandbox's preloaded dependencies and native test environment.
   A plain `oc exec` does not inherit the native harness overrides: the test
   kubeconfig is `/home/omnigent/.config/molecule/kubeconfig`, and the collection
   path is `/home/omnigent/.ansible/collections:/usr/share/ansible/collections`.
   Local cluster commands still use `~/.kube/config`.

   Capture each real exit status separately. Require every discovered
   Molecule scenario to complete its full lifecycle, including idempotence,
   verification and destruction. A trailing successful shell command or a
   successful build does not establish that Molecule passed. If any required
   check fails, leave the PR open and report the failure. Do not fix it,
   send feedback or rerun the test to turn that failure into a pass.

6. Only after all checks pass, merge the Forgejo PR using the tested head SHA
   as the merge guard. Recheck that its base has not changed. Confirm the PR
   is merged and `main` contains the merge commit. Resolve an uncertain merge
   response with reads; do not blindly submit another merge request.

7. Launch **one** application recovery job, then verify:

   ```bash
   bash bootstrap/bootstrap.sh webapp nginx
   bash bootstrap/bootstrap.sh webapp verify-enforcing
   ```

   Require Enforcing, HTTP 200, a successful probe and resolved outage alerts
   under normal alert handling. The last command only verifies state. Do not
   run the permissive setup job or another enforcement job after deployment.
   If recovery fails, record that outcome and stop without repairing it.

8. Report the result, tested/merged SHAs, job IDs, stage timings, prompts,
   test failures and any deviations. Distinguish automatic incident-to-PR
   time from operator tests, merge and recovery. Keep credentials, raw native
   reasoning, live hostnames and runtime IDs out of committed reports.

Read-only observation is allowed. Normal reset/bootstrap, the single fault
launch, independent tests, a passing-test merge, and one recovery launch are
the intended operator actions. Everything else that changes the run must be
reported as intervention; never conceal it as part of a successful demo.
