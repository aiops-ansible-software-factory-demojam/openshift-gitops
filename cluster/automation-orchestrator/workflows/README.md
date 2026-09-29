# Automation Orchestrator workflow

`omnigent-dispatch.yaml` is the portable manual workflow definition. Its
required input is `issue_number`. AO calls the internal Backstage feature gate,
which validates the issue, runs the Developer Hub feature template if the
branch is missing, waits for the Scaffolder task to complete, and confirms
`feature/issue-N` exists. Only then does AO create an Agent Sandbox session
and tell `automation-developer` to implement the issue and open a PR.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The machine client credential is stored in Orchestrator;
its value is never stored in this YAML.

After `bash scripts/feature-demo.sh hydrate`, run
`bash scripts/dispatch-issue.sh 1` at the repository root. It calls the
published workflow through AO's API and prints the Omnigent session ID. The
workflow finishes after Backstage prepares the branch and Omnigent accepts the
task; inspect the session for the checks and PR URL.
