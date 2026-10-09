# Demo prompts and incident records — October 9, 2026

Companion to [the run report](2026-10-09-demo-runs.md). Text below is captured prompt content or a versioned template, labeled accordingly. The rebuilt session retained all four user messages; the earlier reset removed its predecessor session and AO activity history. Earlier manual feedback is summarized in the report because its exact text was not archived. Provider/harness internal system prompts are not exposed by the retained item API. No credentials or authentication headers are included.

Prompt wording is preserved except for privacy substitutions: live service URLs use an example hostname, and runtime identifiers and syscall memory addresses use consistent placeholders. Timestamps, diagnostic facts and public commit SHAs are unchanged. The example links do not reach the live cluster.

## Registered automation-developer prompt

Captured from the live bootstrap-managed agent specification. This sets the workflow/PR boundary; it is not a dump of OpenCode’s complete internal system prompt.

```text
AO runs the Backstage feature golden path before launching you. For an
assigned issue, run demo-goldenpath checkout <number> to check out the
existing feature/issue-<number> branch and read the issue. Read AGENTS.md.
Make only the requested change, verify it, and review the final diff before
committing. Write an accurate PR summary to a file outside the repository,
then run demo-goldenpath pr <number> --body-file <path>. Report the PR URL.
Never create the issue branch yourself or run the feature template again.
Do not merge or push to main. Never print credentials or commit them.
```

## Repository instructions

The agent read this collection’s AGENTS.md during checkout. Captured repository text:

```text
# Collection development

Use fully qualified Ansible module names and keep roles idempotent. Put
configuration defaults in `roles/<role>/defaults/main.yml` and prefix their
names with the role name. Keep secret lookups outside roles.

Run `ansible-lint`, build the collection, and run the Molecule scenario before
opening a pull request. Update `extensions/molecule/default/verify.yml` to
check the feature's behavior. Never commit credentials.

Run `molecule test` from the collection root in a demo Omnigent sandbox. The
sandbox supplies `MOLECULE_GLOB`, the Kubernetes client, and a scoped test
kubeconfig. Keep the exact provisioner version in
`extensions/molecule/requirements-test.yml` and shared scenario configuration
in `extensions/molecule/config.yml`. Use the provisioner collection's lifecycle
playbooks and the existing CentOS Stream 10 DataSource with PodIP
connections. `molecule test` provisions CentOS Stream 10. The RHEL 10 entry
stays commented out until its package repository prerequisites are configured.
Keep each host's boot source and expected distribution facts in
`utils/inventory/hosts.yml`; keep common settings in its group variables.
Shared lifecycle playbooks live in `utils/playbooks/`. Each scenario directory
contains only `molecule.yml`, `converge.yml`, and `verify.yml`; shared `config.yml`
provides the lifecycle and inventory paths. Default convergence is hello world.

Keep the declarative YAML inventory. Its fixed hostname `centos-stream10` is
also the VM name in the shared `molecule-tests` namespace.
Serialize test runs across all demo sandboxes and collections: overlapping
runs can modify or delete each other's VMs. After a failed test, run
`molecule destroy` from the same collection once no other run is using the test VM.

For this collection, test role changes with `molecule test -s nginx` and check
HTTP and actual nginx worker identity. Keep changes scoped to the issue and
update the README when public behavior changes. Push a feature branch and open
a PR against `main`, referencing the issue. Do not merge the PR or push directly
to `main`.
```

## RCA template

Versioned `rootcause.yaml`, unchanged during the October 9 runs. `${auditlogs.artifacts.affected_host_log_output}` is expanded by AO.

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

## Rebuilt RCA request, expanded

Captured from AO `airca.input_data.prompt` in execution `REDACTED_AO_EXECUTION_1`. This includes the actual audit evidence supplied to the model.

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

"type=AVC msg=audit(1791516928.089:615): avc:  denied  { open } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=SYSCALL msg=audit(1791516928.089:615): arch=c000003e syscall=257 success=yes exit=12 a0=ffffff9c a1=REDACTED_ADDRESS_1 a2=800 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=openat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517648.431:866): avc:  denied  { getattr } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=SYSCALL msg=audit(1791517648.431:866): arch=c000003e syscall=262 success=yes exit=0 a0=ffffff9c a1=REDACTED_ADDRESS_2 a2=REDACTED_ADDRESS_3 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=newfstatat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517648.432:867): avc:  denied  { read } for  pid=15516 comm="nginx" name="index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=AVC msg=audit(1791517648.432:867): avc:  denied  { open } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=SYSCALL msg=audit(1791517648.432:867): arch=c000003e syscall=257 success=yes exit=12 a0=ffffff9c a1=REDACTED_ADDRESS_1 a2=800 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=openat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517738.414:1072): avc:  denied  { getattr } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=SYSCALL msg=audit(1791517738.414:1072): arch=c000003e syscall=262 success=yes exit=0 a0=ffffff9c a1=REDACTED_ADDRESS_2 a2=REDACTED_ADDRESS_3 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=newfstatat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517738.414:1073): avc:  denied  { read } for  pid=15516 comm="nginx" name="index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=AVC msg=audit(1791517738.414:1073): avc:  denied  { open } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=1
type=SYSCALL msg=audit(1791517738.414:1073): arch=c000003e syscall=257 success=yes exit=12 a0=ffffff9c a1=REDACTED_ADDRESS_1 a2=800 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=openat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517789.226:1147): avc:  denied  { getattr } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=0
type=SYSCALL msg=audit(1791517789.226:1147): arch=c000003e syscall=262 success=no exit=-13 a0=ffffff9c a1=REDACTED_ADDRESS_2 a2=REDACTED_ADDRESS_3 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=newfstatat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517798.420:1152): avc:  denied  { getattr } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=0
type=SYSCALL msg=audit(1791517798.420:1152): arch=c000003e syscall=262 success=no exit=-13 a0=ffffff9c a1=REDACTED_ADDRESS_2 a2=REDACTED_ADDRESS_3 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=newfstatat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517828.428:1155): avc:  denied  { getattr } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=0
type=SYSCALL msg=audit(1791517828.428:1155): arch=c000003e syscall=262 success=no exit=-13 a0=ffffff9c a1=REDACTED_ADDRESS_2 a2=REDACTED_ADDRESS_3 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=newfstatat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx"
type=AVC msg=audit(1791517858.434:1162): avc:  denied  { getattr } for  pid=15516 comm="nginx" path="/web/index.html" dev="vda4" ino=83886220 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=0
type=SYSCALL msg=audit(1791517858.434:1162): arch=c000003e syscall=262 success=no exit=-13 a0=ffffff9c a1=REDACTED_ADDRESS_2 a2=REDACTED_ADDRESS_3 a3=0 items=0 ppid=15512 pid=15516 auid=4294967295 uid=994 gid=994 euid=994 suid=994 fsuid=994 egid=994 sgid=994 fsgid=994 tty=(none) ses=4294967295 comm="nginx" exe="/usr/sbin/nginx" subj=system_u:system_r:httpd_t:s0 key=(null)ARCH=x86_64 SYSCALL=newfstatat AUID="unset" UID="nginx" GID="nginx" EUID="nginx" SUID="nginx" FSUID="nginx" EGID="nginx" SGID="nginx" FSGID="nginx""
```

## Rebuilt session user message 1 — 2026-10-09T03:53:15Z

Automatic workflow task.

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
Confirm new Ansible modules, parameters, and return fields with
ansible-doc. Declare collection dependencies in galaxy.yml so
AAP project sync installs them; Molecule test requirements
alone do not supply production dependencies. Install the pinned
test requirements from
extensions/molecule/requirements-test.yml before validation.
Add a regression check that nginx serves HTTP while SELinux is
enforcing in the nginx scenario; preserve the default scenario.
Run ansible-lint, build the collection, and run molecule test
-s nginx. Check the actual command exit codes. Serialize
Molecule runs as required by AGENTS.md. Fix failed checks,
review the diff, and commit it.
Write the PR summary and actual validation results to a file
outside the repository, then run demo-goldenpath pr
2 --body-file <path>. Report the PR URL
and any remaining limitations. Do not merge or change the
application VM; the submitted PR is the review boundary.

Incident: [WebappDown] Demo webapp is unavailable
URL: https://forgejo.demo.example/demo-owner/ansible-collection-demo.webapp/issues/2
Issue and root cause analysis:
<!-- demojam-webapp-outage -->
Blackbox exporter reports that the demo webapp is unavailable.

Alert: `WebappDown`
Target: `http://webapp.webapp-vms.svc.cluster.local/`
Started: 2026-10-09T03:50:58.702Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ['Verify current file context: `ls -Z /web/index.html`', 'Apply correct SELinux context: `chcon -t httpd_sys_content_t /web/index.html`', 'Check and update SELinux booleans: `setsebool -P httpd_can_network_connect 1` (if needed for other resources)', 'Restart the nginx service: `systemctl restart nginx`', 'Verify nginx is serving the file correctly'], 'rootCause': "SELinux is enforcing access controls and denying the nginx process (httpd_t) permission to access /web/index.html because the file's context is default_t instead of the required httpd_sys_content_t."}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.
```

## Rebuilt session user message 2 — 2026-10-09T04:06:24Z

Manual reviewer/resume message. This is an intervention, not a second automatic dispatch.

```text
Review feedback: your recent lint commands repeatedly cd to /tmp; that does not validate this collection and can scan installed dependency collections. Run from /home/omnigent/workspace/issue-2 and target roles/nginx and extensions/molecule/nginx, recording the real process exit code with pipefail or PIPESTATUS. Install extensions/molecule/requirements-test.yml before tests, plus the production dependencies you declared, into the configured collection path; do not replace the normal path with a temporary path that hides david_igou.molecule_provisioners. Use ansible-doc on the installed modules. The actual demo targets are RHEL 9 and CentOS Stream 10: their package names are policycoreutils-python-utils, python3-libselinux, and python3-libsemanage, rather than the old Python 2 names. Install bindings before refreshing SELinux facts. restorecon must report a change when it relabels existing files: use restorecon -Rv, register the result, and changed_when based on its relabel output instead of changed_when:false. Review minimum Ansible compatibility against your selected dependency versions. Continue the fix, run meaningful lint/build and molecule test -s nginx, fix failures, commit and submit the PR. Preserve the default scenario and shared provisioning configuration. Do not merge or alter the application VM.
```

## Rebuilt session user message 3 — 2026-10-09T04:10:05Z

Manual reviewer/resume message. This is an intervention, not a second automatic dispatch.

```text
Your repeated lint of /tmp stalled past its timeout, so that turn was aborted while preserving your edits. Continue from the review feedback already supplied. Work from /home/omnigent/workspace/issue-2, install the pinned Molecule requirements into the normal configured collection path, fix modern RHEL/CentOS packages and accurate restorecon change reporting, then run scoped repository lint, collection build, and the isolated nginx Molecule scenario with real exit-code checks. Fix any failures and submit the tested PR; do not alter the application VM or merge.
```

## Rebuilt session user message 4 — 2026-10-09T04:19:37Z

Manual reviewer/resume message. This is an intervention, not a second automatic dispatch.

```text
The first two Molecule runs fail on the same unsupported fact, and the workspace and installed demo.webapp role files match. The installed Ansible fact collector /usr/local/lib/python3.14/site-packages/ansible/module_utils/facts/system/selinux.py sets selinux_facts["type"] from selinux_getpolicytype(); it never creates selinux_facts["policy"]. Verify that source, then fix the ansible.posix.selinux policy argument to use the actual selinux.type fact, or preserve the existing mode without an unnecessary role-side mode change and explicitly enable Enforcing in the regression scenario. Do not silently skip policy/file-context fixes. Run lint/build and a complete nginx Molecule run on the corrected candidate, check exit codes, review, commit and submit the PR.
```

## Initial integration template — e8c6aa8

Versioned template from `cluster/automation-orchestrator/workflows/omnigent-remediation.yaml`. The final template includes explicit package names and a fact field; it has not passed a separate unattended benchmark.

```text
Fix the root cause of Forgejo incident #${trigger.issue_number}
in demo-owner/ansible-collection-demo.webapp. Backstage has
prepared feature/issue-${trigger.issue_number}. Run
demo-goldenpath checkout ${trigger.issue_number}, then read
AGENTS.md and the incident. Use the RCA below as diagnostic
evidence and confirm it against the collection code.

Implement the durable fix in the collection. Keep SELinux
enforcing; correct the policy or file contexts needed by nginx.
Add a regression check that nginx serves HTTP while SELinux is
enforcing and run molecule test -s nginx. Serialize Molecule
runs as required by AGENTS.md. Review the diff and commit it.
Write the PR summary and actual validation results to a file
outside the repository, then run demo-goldenpath pr
${trigger.issue_number} --body-file <path>. Report the PR URL
and any remaining limitations. Do not merge or change the
application VM; the submitted PR is the review boundary.

Incident: ${prepare_feature.body.issue.title}
URL: ${prepare_feature.body.issue.html_url}
Issue and root cause analysis:
${prepare_feature.body.issue.body}
```

## Template published before the timed reset repeat — c6778c4

Versioned template from `cluster/automation-orchestrator/workflows/omnigent-remediation.yaml`. The final template includes explicit package names and a fact field; it has not passed a separate unattended benchmark.

```text
Fix the root cause of Forgejo incident #${trigger.issue_number}
in demo-owner/ansible-collection-demo.webapp. Backstage has
prepared feature/issue-${trigger.issue_number}. Run
demo-goldenpath checkout ${trigger.issue_number}, then read
AGENTS.md and the incident. Use the RCA below as diagnostic
evidence and confirm it against the collection code.

Implement the durable fix in the collection. Keep SELinux
enforcing; correct the policy or file contexts needed by nginx.
Confirm new Ansible modules and their parameters with
ansible-doc. Install the pinned test requirements from
extensions/molecule/requirements-test.yml before validation.
Add a regression check that nginx serves HTTP while SELinux is
enforcing in the nginx scenario; preserve the default scenario.
Run ansible-lint, build the collection, and run molecule test
-s nginx. Check the actual command exit codes. Serialize
Molecule runs as required by AGENTS.md. Fix failed checks,
review the diff, and commit it.
Write the PR summary and actual validation results to a file
outside the repository, then run demo-goldenpath pr
${trigger.issue_number} --body-file <path>. Report the PR URL
and any remaining limitations. Do not merge or change the
application VM; the submitted PR is the review boundary.

Incident: ${prepare_feature.body.issue.title}
URL: ${prepare_feature.body.issue.html_url}
Issue and root cause analysis:
${prepare_feature.body.issue.body}
```

## Template used for the rebuilt incident — fd76cef

Versioned template from `cluster/automation-orchestrator/workflows/omnigent-remediation.yaml`. The final template includes explicit package names and a fact field; it has not passed a separate unattended benchmark.

```text
Fix the root cause of Forgejo incident #${trigger.issue_number}
in demo-owner/ansible-collection-demo.webapp. Backstage has
prepared feature/issue-${trigger.issue_number}. Run
demo-goldenpath checkout ${trigger.issue_number}, then read
AGENTS.md and the incident. Use the RCA below as diagnostic
evidence and confirm it against the collection code.

Implement the durable fix in the collection. Keep SELinux
enforcing; correct the policy or file contexts needed by nginx.
The nginx Molecule converge play disables fact gathering;
gather any facts your new conditions require and install the
SELinux system dependencies before using them. Do not silently
skip the fix because a fact or Python binding is missing.
Confirm new Ansible modules, parameters, and return fields with
ansible-doc. Declare collection dependencies in galaxy.yml so
AAP project sync installs them; Molecule test requirements
alone do not supply production dependencies. Install the pinned
test requirements from
extensions/molecule/requirements-test.yml before validation.
Add a regression check that nginx serves HTTP while SELinux is
enforcing in the nginx scenario; preserve the default scenario.
Run ansible-lint, build the collection, and run molecule test
-s nginx. Check the actual command exit codes. Serialize
Molecule runs as required by AGENTS.md. Fix failed checks,
review the diff, and commit it.
Write the PR summary and actual validation results to a file
outside the repository, then run demo-goldenpath pr
${trigger.issue_number} --body-file <path>. Report the PR URL
and any remaining limitations. Do not merge or change the
application VM; the submitted PR is the review boundary.

Incident: ${prepare_feature.body.issue.title}
URL: ${prepare_feature.body.issue.html_url}
Issue and root cause analysis:
${prepare_feature.body.issue.body}
```

## Final task template, published after corrective feedback — da594d0

Versioned template from `cluster/automation-orchestrator/workflows/omnigent-remediation.yaml`. The final template includes explicit package names and a fact field; it has not passed a separate unattended benchmark.

```text
Fix the root cause of Forgejo incident #${trigger.issue_number}
in demo-owner/ansible-collection-demo.webapp. Backstage has
prepared feature/issue-${trigger.issue_number}. Run
demo-goldenpath checkout ${trigger.issue_number}, then read
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
alone do not supply production dependencies. Install the pinned
test requirements from
extensions/molecule/requirements-test.yml before validation.
Run validation from the checked-out collection root. Scope
ansible-lint to roles/nginx and extensions/molecule/nginx;
do not lint /tmp or installed dependency collections. Keep
the normal collection paths so provisioners remain available.
Add a regression check that nginx serves HTTP while SELinux is
enforcing in the nginx scenario; preserve the default scenario.
Run ansible-lint, build the collection, and run molecule test
-s nginx. Check the actual command exit codes. Serialize
Molecule runs as required by AGENTS.md. Fix failed checks,
review the diff, and commit it.
Write the PR summary and actual validation results to a file
outside the repository, then run demo-goldenpath pr
${trigger.issue_number} --body-file <path>. Report the PR URL
and any remaining limitations. Do not merge or change the
application VM; the submitted PR is the review boundary.

Incident: ${prepare_feature.body.issue.title}
URL: ${prepare_feature.body.issue.html_url}
Issue and root cause analysis:
${prepare_feature.body.issue.body}
```

## Forgejo incident #2 — repeat-after-reset

Created 2026-10-09T01:52:07Z; https://forgejo.demo.example/demo-owner/ansible-collection-demo.webapp/issues/2

```text
<!-- demojam-webapp-outage -->
Blackbox exporter reports that the demo webapp is unavailable.

Alert: `WebappDown`
Target: `http://webapp.webapp-vms.svc.cluster.local/`
Started: 2026-10-09T01:49:40.581Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ["Verify the current SELinux context of the file using 'ls -Z /web/index.html'.", "Relabel the file with the correct context using 'sudo chcon -t httpd_sys_content_t /web/index.html' or 'sudo restorecon -v /web/index.html' if a default policy applies.", "Check /etc/selinux/config or run 'getenforce' to confirm SELinux is in enforcing mode, and verify if the mode changed recently causing the outage.", 'Review audit logs for additional denied permissions to ensure no other files or resources are mislabeled.', "Ensure future file deployments use 'restorecon' or are created with the correct context to prevent recurrence."], 'rootCause': 'SELinux is configured in enforcing mode and the nginx process (domain httpd_t) is denied access (getattr/read/open) to the file /web/index.html because it is labeled with the default_t context instead of the expected httpd_sys_content_t.'}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.
```

## Forgejo incident #2 — rebuilt-stack

Created 2026-10-09T03:52:07Z; https://forgejo.demo.example/demo-owner/ansible-collection-demo.webapp/issues/2

```text
<!-- demojam-webapp-outage -->
Blackbox exporter reports that the demo webapp is unavailable.

Alert: `WebappDown`
Target: `http://webapp.webapp-vms.svc.cluster.local/`
Started: 2026-10-09T03:50:58.702Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ['Verify current file context: `ls -Z /web/index.html`', 'Apply correct SELinux context: `chcon -t httpd_sys_content_t /web/index.html`', 'Check and update SELinux booleans: `setsebool -P httpd_can_network_connect 1` (if needed for other resources)', 'Restart the nginx service: `systemctl restart nginx`', 'Verify nginx is serving the file correctly'], 'rootCause': "SELinux is enforcing access controls and denying the nginx process (httpd_t) permission to access /web/index.html because the file's context is default_t instead of the required httpd_sys_content_t."}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.
```

## Fresh throughput benchmark prompts

Five serial provider requests used `temperature=0`, `max_tokens=256`, streaming usage, and `chat_template_kwargs.enable_thinking=false`. These are synthetic throughput probes, not agent guidance. The same one-line synthetic audit entry was repeated 96 times for the audit-context sample and 768 times for each agent-scale sample. The final sample appends `Use different examples.` to the same long prefix, preventing an identical whole-request cache hit.

```text
Write a factual numbered explanation of the request lifecycle of an HTTP service behind a reverse proxy, covering TCP, HTTP parsing, filesystem access, logging, and monitoring. Continue until the token limit. Do not include a conclusion.
```

The second short sample also appends `Use different examples.`. Synthetic audit line:

```text
type=AVC msg=audit(1791517785.000:120): avc: denied { read open getattr } for pid=1274 comm="nginx" path="/web/index.html" scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:default_t:s0 tclass=file permissive=0
```
