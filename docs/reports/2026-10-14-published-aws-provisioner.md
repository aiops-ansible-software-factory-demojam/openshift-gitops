# Published AWS provisioner test — 14 October 2026

The demo now consumes the published `david_igou.molecule_provisioners:0.0.7-alpha`
release. Bootstrap rebuilt the sandbox, and the generated collection template
passed its complete AWS Molecule lifecycle on RHEL 9 and RHEL 10.

The subsequent Go Haiku incident run reached a PR automatically, but its exact
published commit failed independent nginx verification on both guests. The
original test gate stopped the run before merge, with the app Enforcing and
returning HTTP 403.

At the user's subsequent request, the same PR was merged and one `webapp_nginx`
job deployed it. The app now returns HTTP 200 with the expected page content,
SELinux Enforcing and persistent web-content labels. The alert cleared. The
earlier Molecule failure remains recorded; this follow-up establishes live
recovery, not a passing test-gated demo.

## Release and implementation

The [release](https://github.com/david-igou/ansible-collection-molecule_provisioners/releases/tag/0.0.7-alpha)
was published at 00:27:37 UTC from `dd37c65c10259eebf57c29817976be126592af2d`.
The existing consumers already specified `0.0.7-alpha`; the sandbox previously
preloaded an unreleased source build with that version label. It now downloads
and verifies the Galaxy artifact instead:

```text
Galaxy SHA-256: efe5f587332ef7f744537c9ab7779856470725d0b85463778a633aa28d8b7440
Image digest: sha256:ed9a7b45d8ebf248a9b36034527aea360a268e0f19eb1c705c859490b03d04e6
```

The GitHub and Galaxy archives have matching payload files. Their `FILES.json`
and `MANIFEST.json` metadata differ. Runtime verification checked the Galaxy
files manifest and all 286 checksummed files, in both the disposable verification
pod and the actual coding sandbox.

The released backend uses an explicit `mp_defaults.aws` contract. Both consumer
collections now map the mounted profile to account, region, subnet, VPC, instance
type, shared security group, encrypted gp3 root disk and deployment/purpose tags.
Per-host inventory still selects the pinned RHEL 9 and RHEL 10 AMIs. Lifecycle
playbooks remain imports of the shared collection; `make molecule` still runs
all discovered scenarios. The shared provisioner source was not modified.

Bootstrap creates the test security group and retains it during ordinary resets.
The provisioner injects its generated local SSH key through cloud-init, and
retains the supplied network and group. The test policy permits launches into
that exact group and cleanup of owned interfaces. AWS's policy simulator passed
six checks: shared-group deletion denied, group-rule changes denied, owned
interface cleanup allowed, foreign interface cleanup denied, ownership retagging
denied, and IAM administration denied. All 27 previous deployment-state fields
were preserved; only the test-group ID was added. Network, AMIs and runtime key
IDs were reused. All new bootstrap/lifecycle implementation is in
`bootstrap/bootstrap.sh`.

Test dependencies now also pin `community.aws:11.0.0` and
`ansible.windows:3.5.0`, as required by the published collection. The AWS tests
exercise Linux guests. Windows and CNV were not tested live on this cluster.

Published implementation commits:

| Repository | Commit | Change |
| --- | --- | --- |
| openshift-gitops | `4d6da32311124b058b254dc831f7d22a63038adf` | Released artifact, scoped test networking and profile |
| ansible-collection-demo.webapp | `995e82e0db80423cb9f0a8672fbd27cf06ddf49a` | Released AWS inventory contract |
| ansible-collection-template | `4f4068139f64b29c19d3c5a176519830eab7d708` | Matching generated-collection contract |
| openshift-gitops | `ff249fea416db3be0e9b11c809172b7ccc131b11` | Dashboard selects the issue remediation workflow |

All three branches remain `feature/forgejo-eda-remediation`, and include the
current fetched `origin/main` commits. The AAP project source remains
`954bd8702754a3a9958d817e8416908eca48815f`.

## Bootstrap and template test

All times are UTC. CLI elapsed time includes project/inventory updates, queueing
and polling. The image build and template test overlapped the full bootstrap.

| Stage | Start → finish | Elapsed | Result |
| --- | --- | --- | --- |
| Demo reset | 00:43:54.849 → 00:53:04.228 | 9m09.380s | Passed; AAP preserved |
| Full bootstrap | 00:53:19.217 → 01:07:10.193 | 13m50.977s | Passed |
| Sandbox image build | 00:54:26 → 00:56:57 | 2m31s | Published checksum verified |
| Rendered template lint | First phase of the template test | 6.912s | Exit 0 |
| Template `make molecule` | After lint, same test run | 2m16.923s | Exit 0 |
| Template test, including lint | 00:58:35.093 → 01:00:58.952 | 2m23.859s | Passed |

The template fixture came from its published commit with the normal scaffolder
placeholders substituted. Source and collection installation directories were
separate. Its one `default` scenario completed dependency, syntax, create,
prepare, converge, idempotence, OS/connectivity verification and destroy.
Each RHEL host had four successful guest play recaps.

Independent AWS reads confirmed that the template left no test instances, disks,
interfaces, EC2 key pairs or disposable groups. The bootstrap-owned test group
remained. The verification pod was then deleted.

Before the fault, the monitored RHEL 9.6 guest returned HTTP 200 with Permissive
SELinux and `default_t` labels on `/web` and its index file. The seeded Forgejo
snapshot matched the updated consumer source after URL substitutions: 44 files,
baseline commit `ac64cb25d59948fab70bd8701f481a412ea2e81a`. There were no old
incident sessions or PRs, one starter issue, and two enabled/running EDA listeners.
The native model and AO bridge were both `claude-haiku-5-5` through OpenCode Go;
no explicit thinking override was added.

Static checks passed: 36 existing bootstrap regressions, Bash syntax,
ShellCheck, Kustomize rendering, changed-inventory lint, collection builds,
released-backend normalization of both inventories, and AWS/CNV scenario matrices.
The CNV matrices are configuration checks, not a live CNV lifecycle result.

## Original incident run and merge gate

| Stage | Timestamp or interval | Elapsed / observation |
| --- | --- | --- |
| Fault command | 01:09:12.316 → 01:10:10.526 | 58.211s; exit 0 |
| Fault job 194 | 01:09:59.766 → 01:10:08.405 | 8.640s; successful |
| Alert rule became active | 01:10:29.303 | `activeAt` from Thanos Ruler |
| Alert start in delivered issue | 01:11:29.303 | After the one-minute rule hold |
| RCA workflow | 01:11:46.608 → 01:12:17.898 | 31.290s to final activity completion |
| Audit-log activity | 01:11:47.246 → 01:11:58.355 | 11.109s |
| AI RCA activity | 01:11:58.461 → 01:12:06.514 | 8.054s |
| Issue creation activity | 01:12:06.656 → 01:12:17.898 | 11.242s |
| Forgejo issue 2 created | 01:12:13 | Automatically, with RCA |
| Remediation workflow | 01:12:22.589 → 01:12:50.892 | 28.303s to task handoff completion |
| Feature preparation | 01:12:25.053 → 01:12:28.204 | 3.151s |
| Omnigent session creation | 01:12:28.325 → 01:12:28.706 | 0.381s |
| Task delivery / runner startup | 01:12:28.870 → 01:12:50.892 | 22.022s |
| Forgejo PR 3 created | 01:15:17 | 6m04.684s after fault command |
| Native idle gate observed | 01:15:30.307 | One task; no pending tools/requests |
| Operator test start | 01:16:45.123 | 88.123s after PR publication |
| Independent lint | 01:16:45.509 → 01:16:50.523 | 5.014s; exit 0 |
| Independent collection build | 01:16:50.523 → 01:16:51.001 | 0.477s; exit 0 |
| Independent `make molecule` | 01:16:51.001 → 01:20:30.676 | 3m39.675s; exit 2 |
| Validation gate failed | 01:20:30.738 | 11m18.423s after fault command |
| Merge and recovery | Not performed | Required tests failed |

The alert observer first sampled firing at 01:12:45.558; it started after the
rule transition. The earlier alert-start timestamp comes from the delivered
issue, rather than an earlier observer sample. AAP's incident jobs were fault
194 (8.640s), alert webhook 196 (7.135s), audit logs 197 (8.367s), issue creation
198 (7.109s), and issue webhook 199 (6.857s). These job times are subsets of the
activity intervals above, not additional time.

The published candidate was `e6a49cce4fdbd8bb3e104b52f8acc1e418ba3d5f`.
The operator tested a `git archive` of that commit in its existing managed
sandbox, with a separate collection installation directory. All 46 tracked
files and HEAD were unchanged before and after; the exported source was also
unchanged. No candidate diff or role code was reviewed.

Both guests completed creation, preparation, convergence and idempotence. In
verification, connectivity, OS checks, the Enforcing assertion and HTTP request
tasks passed. The next assertion failed on both guests:

```text
object of type 'dict' has no attribute 'content'
'demojam demo' in nginx_http.content
```

The test did not reach its remaining worker-account checks. Ansible's
[URI module documentation](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/uri_module.html)
documents when the response body is returned as `content`; the observed failure
was a missing result field, not a connection or AWS launch failure. No test or
candidate change was made, and the failed assertion was not rerun.

Molecule's failure cleanup completed destruction. Independent cloud reads then
found zero disposable test instances, disks, interfaces, key pairs and groups.
The shared network/group and monitored guest remained. The monitored guest
still returned HTTP 403 at 01:22:46.688. PR 3 and issue 2 remained open; no merge
or application recovery job ran. The original test-gated run ended without
resolution.

## User-requested merge and recovery

The follow-up instruction was: `test merging the fix and fixing the webapp`.
The PR head and base still matched the independently tested candidate. The
app still returned HTTP 403 before merge. No candidate edits, code review,
agent feedback, test changes or validation reruns occurred. The merge proceeded
at the user's explicit request despite the recorded failed Molecule result.

Forgejo PR 3 was squash-merged at 01:53:10 UTC. Its candidate remained
`e6a49cce4fdbd8bb3e104b52f8acc1e418ba3d5f`; the resulting `main` commit was
`c661f7a941f268090c91059180e073c38cccc604`. Issue 2 closed, and the source branch
was deleted. One `bash bootstrap/bootstrap.sh webapp nginx` command refreshed
the AAP project and inventory, then launched recovery job 205.

| Stage | Start → finish | Elapsed / result |
| --- | --- | --- |
| Merge request and confirmation | 01:53:09.560 → 01:53:10.665 | 1.106s; merged |
| Recovery command | 01:53:51.636 → 01:55:28.092 | 1m36.455s; exit 0 |
| Recovery job 205, `webapp_nginx` | 01:55:01.445 → 01:55:26.281 | 24.836s; successful |
| Alert resolution observed | 01:55:30.283 | 2m20.283s after merge |
| HTTP and blackbox check | 01:56:49.854 → 01:56:50.158 | HTTP 200; `probe_success=1` |
| Enforcing verification command | 01:56:49.857 → 01:56:59.776 | 9.919s; exit 0 |
| Additional read-only guest check 207 | 01:57:33.279 → 01:57:38.164 | 4.885s; successful |

The merge-to-alert interval includes 41.636s before the recovery command began.
Within the recovery command, 69.809s elapsed before job execution, the job took
24.836s, and the final polling took 1.811s. Alert resolution was observed
1m38.647s after the recovery command began. These are follow-up recovery times;
the earlier wait at the failed gate is not an autonomous demo benchmark.

Read-only checks confirmed:

- The HTTP response contained `demojam demo`.
- SELinux remained Enforcing; `httpd_t` was not a permissive domain.
- `/web` and `/web/index.html` both had `httpd_sys_content_t` labels.
- The persistent fcontext rule was `/web(/.*)? → httpd_sys_content_t`.
- The dashboard showed Webapp Up, zero alerts, successful recovery job 205,
  completed issue handoff, and all 14 Argo applications Synced/Healthy.

Job 205 was the only application deployment after merge. Commands 206 and 207
were read-only verification. No SELinux-enable or permissive job ran during
recovery, and no manual guest repair was needed. The original independent
Molecule result remains exit 2 with the missing `nginx_http.content` field;
live success does not resolve that verifier failure. The environment was left
healthy and Enforcing, with the PR merged.

## Prompts, model activity and operator actions

There was one AO-generated user task and zero operator follow-up prompts. The
existing task included SELinux package/fact/module guidance and the requirement
to run `make molecule`; it was not changed for this run. No manual dispatch,
agent repair, resume, compaction, candidate edit or code review occurred.

OpenCode recorded 32 assistant requests and 31 tool calls; one tool was marked
as an error. There were zero recorded provider rate-limit errors. It reported
11,498 output tokens and 11,426 reasoning tokens. Summed assistant-turn time was
150.759s, with 26.995s overlapping tools. Dividing by the remaining 123.764s gives
about 92.9 reported output tokens/s, or 185.2 including reported reasoning.
These estimates include request startup, input processing and harness overhead;
they are not a provider decode benchmark. Qwen was not used.

Setup corrections occurred before the fault: the standalone provider probe was
adjusted to use the configured Go headers; a local matrix invocation was repeated
with the Makefile's scenario glob; and source verification was repeated after
bootstrap reseeded the updated branch. None changed the candidate or supplied
agent feedback. The old recap-parser correction was incorporated into the
operator runner before this incident; this candidate failed with a real
Molecule exit code 2.

After the failed run, the dashboard widget was corrected from
`omnigent-dispatch` to `omnigent-remediation`. Its focused routing check and live
browser verification passed. The widget now reports completed handoff executions;
at that point Webapp Down and one alert represented the unresolved incident.
All 14 Argo applications were Synced/Healthy. The failed PR and coding session
were retained for inspection, and the read-only alert observer was stopped.
The later follow-up merge and deployment changed the app and alert status as
recorded above; the coding session and original test evidence remain available.

The RCA prompt template and delivered coding task follow. Service addresses and
cloud identifiers are redacted; credentials and native reasoning are omitted.

### RCA prompt template

```text
'You are a technical expert specializing in Linux and Windows systems. Your task is to analyze the provided log file snippet and diagnose the cause of the system outage. Your response should follow this JSON format:
      {
        "rootCause": "",
        "escalateTo": "",
        "remediationSteps": []
      }
      Describe the root cause of the issue in the "rootCause" field, providing a concise textual explanation based on the log file snippet.
      Identify the best-suited role to address the issue in the "escalateTo" field (Developer, DBA, Server Engineer, Network Engineer, DevOps Engineer).
      List recommended steps for additional analysis or remediation in the "remediationSteps" array, providing actionable text strings that could help resolve the incident or gather more information.'

${auditlogs.artifacts.affected_host_log_output}
```

### Delivered task

```text
Fix the root cause of Forgejo incident #2
in demo-owner/ansible-collection-demo.webapp. Backstage has
prepared feature/issue-2. Run
demo-goldenpath checkout 2, then read
AGENTS.md and the incident. Use the RCA below as diagnostic
evidence and confirm it against the collection code.

Implement the durable fix in the collection. Keep SELinux
enforcing; correct the policy or file contexts needed by nginx.
The nginx Molecule converge play disables fact gathering;
gather any facts your new conditions require and install the
SELinux system dependencies before using them. Do not silently
skip the fix because a fact or Python binding is missing.
On these RHEL/CentOS guests, use python3-libselinux,
python3-libsemanage, and policycoreutils-python-utils. Refresh
facts after installing bindings. The SELinux policy name is
ansible_facts.selinux.type; confirm facts against the collector
or actual setup output. Report restorecon changes from its
verbose relabel output instead of unconditionally hiding them.
Confirm new Ansible modules, parameters, and return fields with
ansible-doc. Declare collection dependencies in galaxy.yml so
AAP project sync installs them; Molecule test requirements
alone do not supply production dependencies. The sandbox
preloads the pinned test requirements. If you change
extensions/molecule/requirements-test.yml, install the updated
requirements before validation.
Run validation from the checked-out collection root. Scope
ansible-lint to roles/nginx and extensions/molecule/nginx;
do not lint /tmp or installed dependency collections. Keep
the normal collection paths so provisioners remain available.
Add a regression check that nginx serves HTTP while SELinux is
enforcing in the nginx scenario. Run ansible-lint, build the
collection, and run make molecule to test every scenario.
Check the actual command exit codes. Fix failed checks,
review the diff, and commit it.
Write the PR summary and actual validation results to a file
outside the repository, then run demo-goldenpath pr
2 --body-file <path>. Report the PR URL
and any remaining limitations. Do not merge or change the
application VM; the submitted PR is the review boundary.

Incident: [WebappDown] Demo webapp is unavailable
URL: <service-url>/demo-owner/ansible-collection-demo.webapp/issues/2
Issue and root cause analysis:
<!-- demojam-webapp-outage -->
Blackbox exporter reports that the demo webapp is unavailable.

Alert: `WebappDown`
Target: `http://webapp.webapp-vms.svc.cluster.local/`
Started: 2026-10-14T01:11:29.303Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ["Confirm SELinux state with 'getenforce' and 'sestatus', and check whether httpd_t is set permissive with 'semanage permissive -l'.", "Inspect the current labels with 'ls -Z /web /web/index.html' to confirm that default_t is applied instead of httpd_sys_content_t.", "Review the full denial history with 'ausearch -m avc -ts recent' or 'grep avc /var/log/audit/audit.log' to confirm the transition from permissive=1 to permissive=0.", 'Check the nginx error log (/var/log/nginx/error.log) for 13: Permission denied entries and any resulting 403 or 500 responses.', 'Apply the correct file context persistently: \'semanage fcontext -a -t httpd_sys_content_t "/web(/.*)?"\' followed by \'restorecon -Rv /web\'.', "If nginx writes to or serves from non-standard locations, verify required booleans with 'getsebool -a | grep httpd' and enable them as needed (for example, httpd_read_user_content or httpd_unified).", "Restart or reload nginx after relabeling and confirm that index.html is served successfully with 'curl -I http://localhost/'.", "Verify that the enforcing change was intentional. If an administrator ran 'setenforce 1' or removed a 'semanage permissive' entry, document the change and check whether other services were affected.", "Prevent recurrence by ensuring deployment scripts copy web content with 'cp -Z' or run restorecon after deployment, and by adding a post-deploy SELinux label check to the pipeline."], 'rootCause': 'SELinux denied nginx (httpd_t) access to /web/index.html, which carries the label system_u:object_r:default_t:s0 instead of a web content type such as httpd_sys_content_t. The denials were logged with permissive=1 and access was allowed until about timestamp 1791940228. From that point the denials are enforced (permissive=0), so the getattr, open, and read calls fail with exit=-13 (EACCES). nginx can no longer serve the file, which causes the outage. The likely trigger is that the file or /web directory was created or moved without the correct SELinux context, and the httpd_t domain switched from permissive to enforcing.'}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.
```
