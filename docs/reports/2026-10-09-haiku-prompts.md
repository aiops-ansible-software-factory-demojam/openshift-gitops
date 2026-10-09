# Haiku bootstrap rehearsal prompts — October 9, 2026

The native client smoke test used:

```text
Reply with exactly bootstrap-ready. Do not call tools.
```

The AO smoke test used:

```text
Reply with exactly AO-Haiku-ready.
```

The RCA system task is preserved in [rootcause.yaml](../../cluster/automation-orchestrator/workflows/rootcause.yaml). It received audit logs from AAP; the full raw logs remain local. The native session received the following single automatic user message. Its live hostname is replaced with `demo.example`; no corrective user messages were sent.

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
URL: https://forgejo.demo.example/demo-owner/ansible-collection-demo.webapp/issues/2
Issue and root cause analysis:
<!-- demojam-webapp-outage -->
Blackbox exporter reports that the demo webapp is unavailable.

Alert: `WebappDown`
Target: `http://webapp.webapp-vms.svc.cluster.local/`
Started: 2026-10-09T14:42:12.675Z
Summary: The demo webapp is unavailable
Description: The blackbox HTTP probe for http://webapp.webapp-vms.svc.cluster.local/ has failed for at least one minute.
Root Cause: {'escalateTo': 'Server Engineer', 'remediationSteps': ["Confirm the current enforcement state with 'getenforce' and 'sestatus', and check whether httpd_t was removed from the permissive list with 'semanage permissive -l'.", "Inspect the current labels with 'ls -Z /web /web/index.html' to confirm the file has default_t instead of httpd_sys_content_t.", 'Check whether a custom file-context rule exists for the web root with \'semanage fcontext -l | grep /web\'. If none exists, add one with \'semanage fcontext -a -t httpd_sys_content_t "/web(/.*)?"\'.', "Apply the context to the web root with 'restorecon -Rv /web' and then verify nginx can serve /web/index.html with 'curl -I http://localhost/index.html'.", "Review the full denial history with 'ausearch -m AVC,USER_AVC -c nginx --start today' and 'sealert -a /var/log/audit/audit.log' to find when the context changed and what action triggered it.", "Check recent changes with 'journalctl --since' around the first denial timestamp (epoch 1791556858) and review any configuration management, deployment, or manual changes to /web or SELinux policy.", "If the web root must use a non-standard path, verify that the rule is persistent with 'semanage fcontext -l' and 'restorecon -n -v /web' after any file moves.", 'Avoid disabling SELinux globally as a fix. If a temporary workaround is needed, use a targeted permissive domain only with change approval, and document it for later removal.'], 'rootCause': 'SELinux is blocking nginx. The nginx process runs in the httpd_t domain and is trying to access /web/index.html, but that file carries the default_t label instead of an web-content type such as httpd_sys_content_t. Early entries show permissive=1, so the denials were logged but allowed. From about timestamp 1791556858 onward, permissive=0 and the denials are enforced: the getattr syscall (newfstatat) returns exit=-13 (EACCES), and nginx cannot serve the file. The repeated denials every 10 to 30 seconds indicate a persistent outage for this resource. The likely triggers are that the file or the /web directory was created or moved without the correct SELinux context, or that the httpd_t domain was switched from permissive to enforcing (for example, by a semanage permissive change or a setenforce change).'}

Created by Event-Driven Ansible and AAP job `webapp_alert_issue`.
Inspect the webapp VM, nginx service, and demo.webapp collection.
Close this issue after investigating; repeat alerts reuse it while it is open.


```

## Later merge-test authorization

The user requested:

> Test merging the PR and see if it resolves the issue

No additional model prompt or Omnigent task was sent. The operator corrected two
Ansible minimum declarations, merged the reviewed head through Forgejo, and
launched the existing AAP deployment and enforcement jobs. The run report records
the commands' timing, a premature read-only verification, the successful final
checks, and the AAP compatibility warnings.
