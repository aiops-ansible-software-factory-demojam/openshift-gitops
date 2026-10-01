.DEFAULT_GOAL := help
export ISSUE

.PHONY: help preflight bootstrap identity homepage-refresh sandbox-build demo-hydrate demo render demo-reset aap-configure aap-sync webapp-create webapp-nginx webapp-delete webapp-verify

help:
	@printf '%s\n' \
	  'make help          Show commands; needs only Make and a shell' \
	  'make render        Render manifests locally into .rendered/' \
	  'make preflight     Read-only local/cluster prerequisites; .env, manifest, KUBECONFIG' \
	  'make bootstrap     Install platform, provision RHEL/nginx, verify; publish branch first' \
	  'make identity      Reconcile demo users and OIDC clients/providers on an installed stack' \
	  'make homepage-refresh Regenerate navigation links from demo Routes' \
	  'make sandbox-build Build/publish the sandbox image in cluster; installed operators' \
	  'make demo-hydrate  Seed Forgejo/refresh credentials; print the issue URL/number' \
	  'make demo ISSUE=N  Hydrate, then hand positive issue N to AO; agent runs asynchronously' \
	  'make webapp-create Provision the RHEL webapp through AAP' \
	  'make webapp-nginx  Configure nginx through AAP' \
	  'make webapp-verify Read-only VM, HTTPS and blackbox checks' \
	  'make webapp-delete Delete the webapp VM and owned disk through AAP' \
	  'make aap-configure Bootstrap/refresh AAP credentials, license and configuration' \
	  'make aap-sync      Apply seeded config-as-code through AAP' \
	  'make demo-reset    Reset disposable demo repos, sessions, VMs/disks and AAP config' \
	  'Cluster commands load .env in their scripts; see README for inputs and setup.'

bootstrap:
	bash bootstrap/bootstrap.sh

identity:
	bash bootstrap/bootstrap.sh identity

homepage-refresh:
	bash bootstrap/bootstrap.sh homepage-refresh

sandbox-build:
	bash bootstrap/bootstrap.sh sandbox-build

demo-hydrate:
	bash bootstrap/bootstrap.sh hydrate

demo:
	@case "$${ISSUE:-}" in ''|0*|*[!0-9]*) \
	  echo 'Usage: make demo ISSUE=N (positive issue number)' >&2; exit 2 ;; \
	esac; \
	bash scripts/feature-demo.sh hydrate && bash scripts/dispatch-issue.sh "$$ISSUE"

preflight:
	bash bootstrap/bootstrap.sh preflight

aap-sync:
	bash bootstrap/bootstrap.sh webapp sync

webapp-create:
	bash bootstrap/bootstrap.sh webapp create

webapp-nginx:
	bash bootstrap/bootstrap.sh webapp nginx

webapp-delete:
	bash bootstrap/bootstrap.sh webapp delete

webapp-verify:
	bash bootstrap/bootstrap.sh webapp verify

aap-configure:
	bash bootstrap/bootstrap.sh aap-configure

demo-reset:
	bash scripts/reset-demo.sh --confirm-demo-reset

render:
	@mkdir -p .rendered
	kustomize build bootstrap > .rendered/bootstrap.yaml
	kustomize build --enable-helm cluster > .rendered/cluster.yaml
	@for config in cluster/*/kustomization.yaml; do \
		app=$$(dirname "$$config"); \
		echo "Rendering $$app"; \
		kustomize build --enable-helm --helm-kube-version v1.31.0 "$$app" > ".rendered/$$(basename "$$app").yaml" || exit 1; \
	done
