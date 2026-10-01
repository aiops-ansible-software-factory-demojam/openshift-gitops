.DEFAULT_GOAL := help
export ISSUE

.PHONY: help preflight bootstrap sandbox-build demo-hydrate demo render demo-reset aap-configure aap-sync webapp-create webapp-nginx webapp-delete webapp-verify

help:
	@printf '%s\n' \
	  'make help          Show commands; needs only Make and a shell' \
	  'make render        Render manifests locally into .rendered/' \
	  'make preflight     Read-only local/cluster prerequisites; .env, manifest, KUBECONFIG' \
	  'make bootstrap     Install/configure the demo cluster; publish branch first' \
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

sandbox-build:
	bash bootstrap/sandbox-image.sh

demo-hydrate:
	bash scripts/feature-demo.sh hydrate

demo:
	@case "$${ISSUE:-}" in ''|0*|*[!0-9]*) \
	  echo 'Usage: make demo ISSUE=N (positive issue number)' >&2; exit 2 ;; \
	esac; \
	bash scripts/feature-demo.sh hydrate && bash scripts/dispatch-issue.sh "$$ISSUE"

preflight:
	bash bootstrap/preflight.sh

aap-sync:
	bash scripts/webapp-demo.sh sync

webapp-create:
	bash scripts/webapp-demo.sh create

webapp-nginx:
	bash scripts/webapp-demo.sh nginx

webapp-delete:
	bash scripts/webapp-demo.sh delete

webapp-verify:
	bash scripts/webapp-demo.sh verify

aap-configure:
	bash bootstrap/aap-configure.sh

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
