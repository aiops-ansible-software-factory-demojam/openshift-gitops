# LiteLLM sweep 4: gpt-oss-120b prompts

Only submitted user messages and visible automatic helper prompts are included. Credentials, live hostnames, private addresses, runtime IDs and inline reasoning are removed. Native assistant reasoning and compaction summaries are excluded.

See the [sweep report](2026-10-09-litellm-model-sweep.md).

Provider access probe: `Reply with exactly: MODEL_READY`.

AO readiness prompt, if reached: `Reply with exactly: AO-model-ready`.

No operator follow-up, review, corrective, resume or compaction prompt was sent.

## Automatic task message 1

Created at epoch `1791595035`.

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
URL: https://cluster.demo.example/demo-owner/ansible-collection-demo.webapp/issues/2
Issue and root cause analysis:
<!-- demojam-webapp-outage -->
Blackbox exporter reports that the demo webapp is unavailable.

Alert: `WebappDown`
Target: `http://webapp.webapp-vms.svc.cluster.local/`
Started: 2026-10-10T01:15:42.675Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ['Run `getenforce` to confirm SELinux is in Enforcing mode.', 'Check the current SELinux context of the file with `ls -Z /web/index.html`.', "Assign the proper httpd content type, e.g., `semanage fcontext -a -t httpd_sys_content_t '/web(/.*)?'`.", 'Apply the new context with `restorecon -Rv /web` or `chcon -R -t httpd_sys_content_t /web`.', 'Reload or restart nginx and verify access logs for successful file reads.', 'If needed, create a custom policy module to allow the required access.', 'Monitor audit logs (`auditctl -w /var/log/audit/audit.log`) to ensure no further denials.'], 'rootCause': 'SELinux enforcement is blocking nginx (httpd_t) from accessing /web/index.html because the file has the generic default_t context, resulting in AVC denials and EACCES errors.'}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.
```
