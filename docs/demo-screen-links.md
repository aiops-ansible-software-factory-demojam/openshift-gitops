# Screen links for the 2026-10-28 demo run

Use with [the timed three-presenter talk track](demo-script.md). These links point
to the completed module-first AWS run: **35 minutes for parallel incident paths**,
**79.5 minutes including reset/setup retries**. IDs and links are intentionally
included at the operator's request. Credentials and raw agent reasoning are excluded.

## Preload before taking the stage

Sign into [Homepage][home], [AO][ao], [AAP][aap], [Forgejo Python PR][python-pr],
[Forgejo nginx PR][web-pr], [Omnigent][omnigent] and [Developer Hub][hub] with your
demo SSO identity. Open the [architecture SVG](diagrams/demo-architecture.svg) and
[workflow PDF](diagrams/demo-workflow.pdf) (or [overview PNG](diagrams/demo-workflow-overview.png)). Keep a terminal with the
saved independent validation and enforcing/probe logs ready.

The application links now show the recovered state. Use historical AAP results
and saved baseline evidence for the earlier vulnerable/403 views. Do not rerun
triggers, approve anything again, merge another PR, reset, or relaunch jobs to
recreate history while walking through this run. A later reset can replace the
Forgejo objects and remove sessions; match these IDs and source SHAs to the saved
run before using links. AAP/AO history can outlive disposable Forgejo data.

## AO executions

[Open AO][ao]. The stable entry point is the application root; browser deep-link
routes were not confirmed, so execution UUIDs below are the precise selectors.
Open the executions/history view. If needed, first open the named workflow and
then its execution history. Select the completed **2026-10-28** execution matching
the UUID, rather than the latest execution of the same name. If the list shows
only shortened IDs, open the candidate and compare its full ID in execution details
or the browser address. Use the graph and select the named node for its result.

| Label | Workflow / execution | What to show |
| --- | --- | --- |
| D1 | **invoice-security-detect** — `c325f60d-3c54-4930-8305-401d8bbc5a49` | Assessment → Lightwell discovery → `app_patch` router → incident. |
| P1 | **invoice-security-remediation** — `4b0c669f-07cc-43fe-83ab-8ab550c4ca29` | Author → wait PR → independent validation → wait merge → promotion → verify → close. |
| N1 | **Check Audit logs, Determine RCA, Create Issue** — `4056d98a-5b26-4a47-a83c-79c377ecd613` | AAP audit-facts path, diagnosis and nginx incident creation. |
| N2 | **omnigent-remediation** — `e0920874-7686-4937-9389-8604c9949afa` | Developer Hub preparation → coding session handoff. It ends at authoring handoff, not recovery. |

If an AO execution cannot be located quickly, show the linked AAP job and Forgejo
incident below instead. They identify the concrete evidence without guessing a
browser route. No API token needs to be displayed or pasted into the browser.

## Coding sessions

[Open Omnigent][omnigent] → sessions list → choose the exact title and full ID below.
The title alone is not unique across rehearsals. Open the existing session's
activity/tool history, scroll to the recorded test command, and expand its output.
Both sessions are idle/completed; do not send a new message or resume authoring.

| Label | Title / session ID | What to show |
| --- | --- | --- |
| S1 | **Invoice remediation issue 1** — `d90824c8d9344fb89b98131ec1a49f1e` | Release-lock update, agent development test output, PR publication. |
| S2 | **Webapp outage issue 1** — `683b5e1ae66b4b6a90ea1aed988cf951` | `sefcontext` implementation, added regression assertions, agent test output. |

Developer Hub is context rather than a required extra tab during the timed segment:
[open Hub][hub], find **Contribute to the Demo Ansible Collection** in the template
catalog, and show the contribution golden path. Use the existing task history if
available; do not execute the template. The prepared branch is `feature/issue-1`
in each application repository. The AO preparation node records its actual handoff;
there is no verified Scaffolder task deep link in the saved evidence.

## Forgejo objects

| Object | Direct link / view | Details to highlight |
| --- | --- | --- |
| Python incident | [Issue #1][python-issue] | Structured package/CVE finding and approved remediation. |
| Python change | [PR #2][python-pr] · [Files changed][python-diff] · [release file][python-release] | Only the release manifest changes; channel Lightwell, PyPDF2 `3.0.1+rhlw.1`, approved checksum. |
| Python review gate | [PR conversation/checks][python-pr] | Successful `invoice/ec2-validation`, review and merge. Expand the check or use [AAP validation][python-acceptance]. |
| nginx incident | [Issue #1][web-issue] | Alert context and completed RCA. |
| nginx change | [PR #2][web-pr] · [Files changed][web-diff] | Persistent policy module, dependency declaration and regression additions. |
| nginx policy | [SELinux task file][web-policy] | `community.general.sefcontext`, read-only content type and `restorecon`. |
| nginx regression | [verify.yml][web-tests] | Labels on root/index, HTTP response, worker account, Enforcing. |

The tested Python head is `178bd0c69a430e019b79dbc424fc7d5c2174bd36`;
the tested nginx head is `fe4cb243c448ed0b17ab11619f8ec36f9c32ef0d`.
File links use those exact commits, so branch changes do not silently change the diff.

## AAP objects and fallback navigation

Links use the gateway's job-output routes already used by this demo. If SSO drops
you at the application root or a UI version does not preserve the path, open
[AAP][aap] → **Automation Execution → Jobs** (or the Jobs list), filter by the
**numeric ID and name**, and choose **Output**. Check the ID in the page URL/details.
For workflow 2148 choose its graph/visualizer; node selection opens the child job.
The workflow displays recorded approval **2151** in place of a separate approval URL.

| Job / workflow | Link | What to expand |
| --- | --- | --- |
| `invoice_baseline` 2071 | [Baseline output][python-baseline] | Installation of the vulnerable baseline, source identity and initial health. |
| `webapp_nginx` 2097 | [nginx baseline output][web-baseline] | Initial successful deployment; use saved readiness evidence for mode/probe. |
| `webapp_selinux_enable` 2113 | [Fault output][web-fault] | The real enforcing-mode fault; pair with recorded HTTP 403/probe failure. |
| `invoice_discover` 2115 | [Lightwell discovery][lightwell-discovery] | Public selection and fixed version/artifact evidence. Redacted private inputs stay redacted. |
| `invoice_route` 2116 | [CVE router][cve-router] | Trusted observation/discovery receipts and `app_patch` route. |
| `invoice_open_issue` 2117 | [Python ticket job][python-ticket] | Incident reconciliation and Forgejo linkage. |
| `pull_audit_logs` 2119 | [Audit evidence][audit-facts] | Enforcing state and compact SELinux/AVC facts used by RCA. |
| `webapp_alert_issue` 2121 | [nginx ticket job][web-ticket] | Diagnosis and alert mapped into the incident. |
| `invoice_validate` 2131 | [Independent validation][python-acceptance] | Candidate checks followed by trusted acceptance, RHEL 9/10, idempotence, business/security/rollback checks and destruction; elapsed 858.9 seconds. |
| `invoice_validation_status` 2132 | [Status publication][python-status-job] | Evidence-backed success publication; the public result is on the PR. |
| `invoice_prepare_release` 2145 | [Release preparation][prepare-release] | Approved source/PR/validation/artifact binding. Do not expose private runtime material. |
| `invoice_promote` 2148 | [Native workflow graph][python-promotion] | Validate 2149 → approval 2151 → recheck 2153 → deploy 2154. |
| Preapproval check 2149 | [Output][preapproval-check] | Release contract validation before the human decision. |
| Production approval 2151 | [Parent workflow][python-promotion] | Select **production-approval**; show completed decision and approximately 80-second wait. No new approval action. |
| Postapproval check 2153 | [Output][postapproval-check] | Revalidation bound to the same workflow's human decision. |
| `invoice_deploy` 2154 | [Deployment output][python-deploy] | Exact tested source, approved wheel and successful activation; elapsed 41.2 seconds. |
| `invoice_verify_deployment` 2157 | [Deployment proof][deployment-proof] | Actual workflow/approval/job/source/artifact evidence. |
| `invoice_check` 2158 | [Business/security results][business-check] | Normal and regression processing, fixed package and healthy behavior. |
| `invoice_open_issue` 2159 | [Final reconciliation][close-python] | Verified fixed result closes the Python incident. |
| `webapp_nginx` 2150 | [nginx recovery output][web-deploy] | Reviewed collection deployed with enforcing mode preserved; elapsed 27.3 seconds. |

Enforcing verification used **AAP ad hoc command 2152**, which is not an ordinary
playbook job: do not invent a `/playbook/2152` link. Open the AAP Jobs list, find
ID 2152 (ad hoc `getenforce` against `webapps`), and open its output if the UI exposes
it. The saved verification log below is the dependable fallback and records its success.

## Local evidence views

These operator tests/readiness captures are local files, not AAP or AO jobs. They
are not committed into GitHub, so a repository hyperlink cannot open them there.
On the session workstation set this **specific recorded run**, not a future
`active-run` pointer:

```bash
export DEMO_WALKTHROUGH_RUN=/root/workspace/openshift-gitops/.rendered/rehearsals/20261028T161115Z-module-first-both
```

| View / when | Read-only way to open | What to highlight |
| --- | --- | --- |
| Python baseline at 0:50 | Run the filtered JSON command below. Pair with job 2071. | Baseline installed package/version and release identity; this is saved state, not current portal state. |
| Initial nginx at 1:03 | `python3 -m json.tool "$DEMO_WALKTHROUGH_RUN/pre-trigger-ready.json"` | Baseline successful job IDs, HTTP 200/probe success and empty incident/session lists. Permissive setup job 2089 belongs to this baseline; job 2113 later enables Enforcing. |
| Fault at 1:15 | `less -R "$DEMO_WALKTHROUGH_RUN/web-fault.log"` | Successful fault job; 403/probe-failure observation was recorded separately in the run. Do not claim this log contains a screenshot or probe output it does not contain. |
| nginx independent tests at 4:01 | `less -R "$DEMO_WALKTHROUGH_RUN/web-validation.log"` | Published SHA near top; build/install/lint, five unit tests and complete RHEL 9/10 lifecycle. Search `/idempotence`, then `/SCENARIO RECAP`; the final actual exit is 0. |
| Recovery at 4:35 | `less -R "$DEMO_WALKTHROUGH_RUN/web-verify.log"` | Ad hoc 2152 success, explicit Enforcing result and healthy application/probe verification. |
| Final run measurements | `python3 -m json.tool "$DEMO_WALKTHROUGH_RUN/run-status.json"` | 35.0/79.5-minute timings, validated/merged SHAs and outcome summary. Keep private companion receipts closed. |

Only print selected baseline fields rather than opening unrelated private receipts:

```bash
python3 - <<'BASELINE'
import json, os
from pathlib import Path
saved = json.loads((Path(os.environ['DEMO_WALKTHROUGH_RUN']) /
                    'python-baseline-status-private.json').read_text())
print(json.dumps({key: saved[key] for key in ('installed', 'release')}, indent=2))
BASELINE
```

If the historical timeout/403 footage was not captured, say so and show the baseline
job/installed identity, original incident and fault/RCA evidence instead. The saved
baseline status does not itself prove a displayed regression timeout, and the final
live portal cannot reproduce the old vulnerable state. Do not manufacture footage
or restart the fault to fill that gap.

## Monitoring and final health

[Homepage][home] shows current probe/alert widgets and application links. For the
underlying objects, [open the OpenShift console][console] → Administrator perspective
→ **Observe → Alerts**; search **WebappDown**, checking that there is no active firing
alert. In **Observe → Metrics**, run `probe_success{namespace="blackbox-exporter",job="webapp"}`
for probe success, or use the saved verification log. Change the monitoring time
range to the recorded run if that historical data remains retained; current empty
alerts only establish current state, not the earlier firing event.

[nginx page][web-app] is a useful visual but its OIDC login page is not backend-health
proof. Pair it with the internal probe and recorded Enforcing check.
[Python portal][python-app] → **Application release** shows release identity; expand
**Security regression verification** to identify the regression control. Use the
completed [business-check output][business-check] or recorded results when narrating
historical behavior; the **Process sample invoice** / **Run regression document**
buttons start new application requests. [Release status JSON][python-status] gives
the current installed version and exact release source/checksum directly.

## Link verification scope

Object IDs, PR/file URLs, session/execution selectors and job relationships were
cross-checked against this run's saved evidence. AAP URL formats match bootstrap's
published job/status links. AO/Omnigent/Developer Hub browser deep links were not
verified, so their confirmed roots and exact object selectors are supplied instead.
No browser renderer was connected for visual click-through testing. Rehearse login,
UI labels and local-log access before stage time; fall back to the nearest root
and the explicit ID/name rather than guessing a new route.


[home]: https://homepage.apps.cluster.example.invalid
[python-app]: https://pythonapp.apps.cluster.example.invalid
[python-status]: https://pythonapp.apps.cluster.example.invalid/api/status
[web-app]: https://webapp.apps.cluster.example.invalid
[ao]: https://automation-orchestrator-automation-orchestrator.apps.cluster.example.invalid
[omnigent]: https://omnigent.apps.cluster.example.invalid
[hub]: https://rhdh.apps.cluster.example.invalid
[aap]: https://aap-ansible-automation-platform.apps.cluster.example.invalid
[console]: https://console-openshift-console.apps.cluster.example.invalid
[python-issue]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/issues/1
[python-pr]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/pulls/2
[python-diff]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/pulls/2/files
[web-issue]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/issues/1
[web-pr]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/pulls/2
[web-diff]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/pulls/2/files
[web-policy]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/src/commit/fe4cb243c448ed0b17ab11619f8ec36f9c32ef0d/roles/nginx/tasks/selinux.yml
[web-tests]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/src/commit/fe4cb243c448ed0b17ab11619f8ec36f9c32ef0d/extensions/molecule/nginx/verify.yml
[python-release]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/src/commit/178bd0c69a430e019b79dbc424fc7d5c2174bd36/releases/invoice.json
[python-promotion]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/workflow/2148
[python-baseline]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2071/output
[web-baseline]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2097/output
[web-fault]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2113/output
[lightwell-discovery]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2115/output
[cve-router]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2116/output
[python-ticket]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2117/output
[audit-facts]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2119/output
[web-ticket]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2121/output
[python-acceptance]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2131/output
[python-status-job]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2132/output
[prepare-release]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2145/output
[preapproval-check]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2149/output
[web-deploy]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2150/output
[postapproval-check]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2153/output
[python-deploy]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2154/output
[deployment-proof]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2157/output
[business-check]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2158/output
[close-python]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2159/output
