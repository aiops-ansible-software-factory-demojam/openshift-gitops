.PHONY: ee configure vm

ee:
	@test -n "$(AAP_EE_IMAGE)" || { echo 'Set AAP_EE_IMAGE to a registry image tag.'; exit 2; }
	ansible-builder build --container-runtime podman --tag "$(AAP_EE_IMAGE)"

configure:
	@test -n "$(AAP_EE_IMAGE)" || { echo 'Set AAP_EE_IMAGE.'; exit 2; }
	ansible-navigator run playbooks/aap/configure-aap.yml --mode stdout --execution-environment-image "$(AAP_EE_IMAGE)"

vm:
	@test -n "$(AAP_EE_IMAGE)" || { echo 'Set AAP_EE_IMAGE.'; exit 2; }
	ansible-navigator run playbooks/openshift_virtualization/virtualmachine-manage.yml --mode stdout --execution-environment-image "$(AAP_EE_IMAGE)" $(VM_ARGS)
