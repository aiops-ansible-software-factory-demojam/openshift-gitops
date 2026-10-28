# Demo runs

For the Python scenario, follow
[the invoice runbook](docs/invoice-lightwell-demo.md). For `DEMO_SCENARIO=both`,
reset/bootstrap once and run both the invoice detection and the nginx fault
sequence below, recording separate results. Provisioning both apps alone does
not exercise both incidents. In AWS, application and
test guests are EC2 instances. Nginx/SELinux uses `demo.webapp` on `webapps`; Python vulnerability remediation uses `demo.pythonapp` on `pythonapps`. Never direct invoice jobs or SELinux fault jobs at the other application group. Preserve the independent validation, human
merge, and AAP production approval boundaries. The SELinux fault sequence
below belongs only to the original scenario.

For a requested end-to-end demo run, use
[run-demojam](.agents/skills/run-demojam/SKILL.md).
Keep bootstrap and lifecycle implementation in `bootstrap/bootstrap.sh`.

## Ansible authoring standard

Follow [Red Hat CoP Automation Good Practices](https://redhat-cop.github.io/automation-good-practices/),
especially role design, coding style, idempotence and check mode. Repository and
operator requirements still determine application layout and acceptance boundaries.

Prefer an existing built-in or maintained collection module to `command` or
`shell`; check its interface with `ansible-doc` and declare production collection
dependencies in `galaxy.yml` when applicable. Use `ansible.builtin.uri` for HTTP
APIs. Avoid custom modules/plugins when existing modules and straightforward tasks
are sufficient; document the specific unsupported capability before adding one.
Keep application details in vars files, not role defaults or inventory.

If a command is necessary, comment why no suitable module covers it, prefer
`ansible.builtin.command` with `argv`, and provide accurate change detection,
check-mode behavior and failure handling. Use shell only when shell features are
required. Never suppress configuration/test errors with `|| true` or unconditional
`failed_when: false`, and never hide mutations with blanket `changed_when: false`.
Read-only diagnostic commands can legitimately report no change; classify expected
nonzero results explicitly and retain unexpected failures.

Keep meaningful regression assertions and the complete Molecule lifecycle,
including idempotence and verification. Run production-profile lint and all final
checks; preserve actual nonzero exit codes. Do not weaken tests or discard test
state to claim success. Report failed or unavailable checks honestly.
