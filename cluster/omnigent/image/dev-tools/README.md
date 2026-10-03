# Sandbox development cache

These build inputs are a snapshot of `ansible-collection-demo.webapp` commit
`4308fc076e22993acafdfb546e69a6489052a04b`: `requirements-dev.txt`,
`extensions/molecule/requirements-test.yml`, and `.pre-commit-config.yaml`.
Refresh the three files together when updating the image's collection tooling.

The collection remains authoritative for its checks and dependency versions.
The image preinstalls those Python tools, includes wheels for project virtual
environments, prebuilds hook environments, and installs real Molecule test
collections. New runtime homes get their own writable pre-commit database and
collection copies. Existing caches are preserved. Changed hook dependencies
can still install normally; the image cache does not override repository rules.

`make hooks` still installs the Git hook and source namespace for each checkout.
No collection source, credentials, or Git hooks are installed into future repos
by the image.
