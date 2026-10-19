# Demo runs

For `DEMO_SCENARIO=invoice`, follow
[the invoice runbook](docs/invoice-lightwell-demo.md). In AWS, application and
test guests are EC2 instances. Preserve the independent validation, human
merge, and AAP production approval boundaries. The SELinux fault sequence
below belongs only to the original scenario.

For a requested end-to-end demo run, use
[run-demojam](.agents/skills/run-demojam/SKILL.md).
Keep bootstrap and lifecycle implementation in `bootstrap/bootstrap.sh`.
