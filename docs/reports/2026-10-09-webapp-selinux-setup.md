# Separate SELinux demo setup from nginx deployment

The nginx installation playbook no longer changes SELinux mode. A separate
`selinux-permissive.yml` playbook, exposed as `webapp_selinux_permissive`,
prepares the demo baseline. `bootstrap.sh` launches it after `webapp_vm` and
before `webapp_nginx`. The base collection was already leaving SELinux mode
unchanged and needed no edits.

This removes the caller behavior that caused the earlier MiniMax recovery to
need a second human job. The fault job establishes Enforcing; deploying the
merged collection now preserves that mode.

## Live verification

The check used `~/.kube/config`, the existing provisioned RHEL VM and the
already merged MiniMax collection fix. Only the Forgejo automation project
was refreshed from GitHub commit `c557ad5`; the collection remained at
`4991428dc897baa0cc77694de4f937d2f38b0547`. This was a deployment regression
check, without a fresh cluster bootstrap or another agent incident.

1. An independent guest check confirmed Enforcing before the test.
2. AAP applied the new configuration. The separate setup job succeeded, and
   an independent check confirmed Permissive.
3. The existing fault-mode job restored Enforcing, confirmed independently.
4. **One nginx deployment** succeeded. Its HTTP check returned 200; an
   independent guest check still found Enforcing.
5. `bootstrap.sh webapp verify-enforcing` passed its guest mode, VM readiness,
   HTTPS authentication redirect and blackbox probe checks. Both EDA
   activations remained enabled and running. No enforcement job ran after
   nginx deployment.

All jobs used automation-project revision
`2f2c8db9064eb080b6f2217a564628e0407746af`. The record is in the
[redacted evidence](evidence/2026-10-09/webapp-selinux-setup.json).

## Timings

Command time includes project and inventory dependency refreshes. Job time
measures the execution of the named AAP job. Times are UTC.

| Step | Command start | Command finish | Command seconds | AAP job | Job seconds |
|---|---|---|---:|---:|---:|
| Apply AAP configuration | 20:59:52.849 | 21:08:41.853 | 529.004 | 266 | 235.943 |
| Separate permissive setup | 21:08:41.882 | 21:11:04.722 | 142.840 | 276 | 8.963 |
| Restore fault-mode Enforcing | 21:11:12.425 | 21:13:30.656 | 138.231 | 283 | 7.955 |
| Single nginx deployment | 21:13:37.907 | 21:17:01.075 | 203.168 | 290 | 19.571 |
| Final mode and HTTP verification | 21:17:08.858 | 21:17:21.345 | 12.488 | Read-only check | — |

Configuration through final verification took **17m28.497s**. The nginx
deployment command took **3m23.168s**, with **19.571s** in the application job.
No edits to the agent fix or manual cluster repairs were required.

## Local checks

Ansible lint passed for both modified playbooks and the job-template data.
It ran offline with preloaded development dependencies because the project's
requirements reference certified collections installed in the supported EE.
Syntax checks passed in that Red Hat EE. Bash syntax, warning-level ShellCheck,
whitespace checks and the bootstrap provisioning/setup/install ordering check
passed. The collection and its Molecule scenario were unchanged.
