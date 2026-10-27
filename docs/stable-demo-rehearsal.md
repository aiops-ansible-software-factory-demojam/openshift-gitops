# Conservative rehearsal branches

Use `feature/stable-demo-rehearsal` in GitOps, demojam-ansible and both application
collections. These branches start at each repository's published main and port
selected improvements from the existing CVE response PRs. The original PR
branches remain available unchanged.

## Included

- CVE policy routing to the existing Lightwell patch path, approved temporary
  containment, manual review or deferred evidence retention. Containment never
  marks the vulnerability fixed. The default profile still selects a patch.
- Lightwell boolean compatibility checks, the collection-local role lookup for
  raw AAP checkouts, and protected full-SHA checks for overridden deployment jobs.
- AWS account discovery from credentials, preserving deployment ownership checks.
- Retirement of the manual dispatch workflow and generated README starter issue.
- Explicit inherited scenario selection and companion source checks before reset.
- Agent instructions requiring meaningful regression coverage and honest final
  lint, unit, build and full Molecule results.

## Deferred

The independent CI repair controller, author callbacks, green-CI polling helper,
new nginx red/green test harness, and native nginx promotion workflow are not
ported. Nginx uses the existing AAP wrapper, which gathers guest facts before
calling the collection playbook. The operator independently tests the published
PR before merge and launches recovery once. Invoice retains main's independent
acceptance and production approval flow; failed checks stop that run.

## Verification boundaries

Both incident triggers must run after one reset/bootstrap. Record their outcomes
separately. Test the default patch route end to end and the alternative routing
and containment guards through isolated Ansible/AO fixtures. Passing route
fixtures does not claim a live production containment demonstration. Do not merge
GitHub implementation PRs as part of the rehearsal. Leave `.env` unchanged.
