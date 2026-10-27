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
- Native Molecule lifecycle sequences destroy owned test guests before every
  separate test, converge, create or check command. Cleanup failure stops the
  command. Idempotence and verification retain the fresh guest within one test.
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

## Clean guest lifecycle regression check

`tests/molecule-clean-hosts.py` executes the checked-in lifecycle sequences with
the pinned Molecule version and local guest-state fixtures. It tests repeated
convergence after a code-change marker, standalone creation, failed cleanup, full
idempotence/verification/destruction and check mode. It requires neither a VM nor
cloud credentials. Supply each collection shared config, the trusted invoice
acceptance config and the MCP scenario with repeated `--config` arguments.

The agent prompts require a full final run on new RHEL 9/10 test guests after
the final edit. The shell tool needs at least 30 minutes for the complete EC2
lifecycle. A shorter shell timeout, skipped creation or truncated output cannot
be reported as a passing final test. Preserve ownership records after interruption
so the next destroy can clean partial resources.
