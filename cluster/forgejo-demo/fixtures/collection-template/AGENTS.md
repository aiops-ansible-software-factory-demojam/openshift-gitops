# Collection development

Use fully qualified Ansible module names and keep roles idempotent. Put
configuration defaults in `roles/<role>/defaults/main.yml` and prefix their
names with the role name. Keep secret lookups outside roles.

Run `ansible-lint`, build the collection, and run the Molecule scenario before
opening a pull request. Update `extensions/molecule/default/verify.yml` to
check the feature's behavior. Never commit credentials.
