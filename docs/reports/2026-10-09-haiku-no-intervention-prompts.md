# Haiku hands-off run prompts — October 9, 2026

Only submitted user messages are included. Credentials, live hostnames, runtime IDs and inline provider reasoning are removed. No assistant reasoning is published.

The [run report](2026-10-09-haiku-no-intervention.md) records the outcome.

## Readiness checks

Direct provider: `Reply with exactly: MODEL_READY`.

AO workflow: `Reply with exactly: AO-model-ready`.

No operator follow-up, review, corrective, resume or compaction prompt was sent.

## Automatic message 1

Created at epoch `1791583235`.

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
Started: 2026-10-09T21:59:12.675Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ["Confirm the current SELinux mode with 'getenforce' and 'sestatus', and review the change history to find when enforcing mode was re-enabled.", "Inspect the file's context with 'ls -Z /web/index.html' and the directory with 'ls -Zd /web', and compare them with the expected httpd content label.", 'Check the nginx document root configuration to confirm which path it serves and that /web is the intended location.', "Restore the default label for the web content using 'restorecon -Rv /web' after confirming the correct file type.", 'If /web is not a standard location, add a persistent file context rule with \'semanage fcontext -a -t httpd_sys_content_t "/web(/.*)?"\' and then run \'restorecon -Rv /web\'.', "Verify the fix by reloading nginx and requesting the page, then confirm no new AVC denials appear with 'ausearch -m AVC -ts recent' or 'grep nginx /var/log/audit/audit.log'.", "Use 'audit2why' on the denial records to confirm the root cause and check whether any custom SELinux policy modules were recently installed or removed.", 'Review how /web/index.html was created or moved (deployment scripts, copy without context preservation, or manual edits) and update the process to preserve or set the correct SELinux labels.', 'Check nginx error logs (/var/log/nginx/error.log) around the outage window for 403 or permission-denied entries to confirm customer impact and timing.', "Avoid using 'setenforce 0' or permissive mode as a permanent workaround. If it was used during the incident, document it and restore enforcing mode after the labels are corrected."], 'rootCause': 'SELinux denied nginx (running as httpd_t) access to /web/index.html, which carries the default_t label instead of an httpd-readable type such as httpd_sys_content_t. Early denials were logged with permissive=1, so access was allowed. From audit time 1791583078 onward, the denials show permissive=0 (enforcing) with exit=-13 (EACCES), so nginx could no longer stat, read, or open the file. This blocked content delivery and caused the outage. The mislabeled file is the likely trigger, and the enforcing mode change exposed it.'}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.
```
