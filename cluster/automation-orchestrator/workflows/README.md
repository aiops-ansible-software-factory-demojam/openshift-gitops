# Automation Orchestrator workflow

`omnigent-dispatch.yaml` is the portable manual workflow definition. Its
required input is `issue_number`. It creates an Agent Sandbox managed session,
then tells `automation-developer` to review the Forgejo collection issue and
open a feature PR through Omnigent's internal Service.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The machine client credential is stored in Orchestrator;
its value is never stored in this YAML.

After `bash scripts/feature-demo.sh hydrate`, run
`bash scripts/dispatch-issue.sh 1` at the repository root. It calls the
published workflow through AO's API and prints the Omnigent session ID. The
workflow finishes after Omnigent accepts the task; inspect the session for
the branch, checks, and PR URL.
