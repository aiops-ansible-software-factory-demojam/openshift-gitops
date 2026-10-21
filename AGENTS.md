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
