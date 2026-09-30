export MOLECULE_GLOB := extensions/molecule/*/molecule.yml

.PHONY: test converge destroy
test:
	molecule test --all

converge:
	molecule converge --all

destroy:
	molecule destroy --all
