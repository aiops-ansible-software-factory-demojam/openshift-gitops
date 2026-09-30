# Collection development

Use fully qualified Ansible module names and keep roles idempotent. Put
configuration defaults in `roles/<role>/defaults/main.yml` and prefix their
names with the role name. Keep secret lookups outside roles.

Run `ansible-lint`, build the collection, and run the Molecule scenario before
opening a pull request. Update `extensions/molecule/default/verify.yml` to
check the feature's behavior. Never commit credentials.

Run `molecule test` from the collection root in a demo Omnigent sandbox. The
sandbox supplies `MOLECULE_GLOB`, the Kubernetes client, and a scoped test
kubeconfig. Keep the exact provisioner version in
`extensions/molecule/requirements-test.yml` and shared scenario configuration
in `extensions/molecule/config.yml`. Use the provisioner collection's lifecycle
playbooks and the existing CentOS Stream 10 DataSource with PodIP
connections. `molecule test` provisions CentOS Stream 10. The RHEL 10 entry
stays commented out until its package repository prerequisites are configured.
Keep each host's boot source and expected distribution facts in
`utils/inventory/hosts.yml`; keep common settings in its group variables.
Shared lifecycle playbooks live in `utils/playbooks/`. Each scenario directory
contains only `molecule.yml`, `converge.yml`, and `verify.yml`; shared `config.yml`
provides the lifecycle and inventory paths. Default convergence is hello world.

Keep the declarative YAML inventory. Its fixed hostname `centos-stream10` is
also the VM name in the shared `molecule-tests` namespace.
Serialize test runs across all demo sandboxes and collections: overlapping
runs can modify or delete each other's VMs. After a failed test, run
`molecule destroy` from the same collection once no other run is using the test VM.
