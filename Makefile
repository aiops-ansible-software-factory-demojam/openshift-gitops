.DEFAULT_GOAL := help
ifneq ($(strip $(BACKEND)),)
export DEMO_BACKEND := $(BACKEND)
endif

.PHONY: help help-all preflight bootstrap teardown teardown-keep-aap identity homepage-refresh model-config sandbox-build demo-hydrate render demo-reset aap-configure aap-sync ao-configure webapp-create webapp-nginx webapp-delete webapp-verify

help:
	@printf '%s\n' \
	  'Set up and run the demo:' \
	  '' \
	  '  make bootstrap [BACKEND=cnv|aws] Set up the complete environment' \
	  '  make demo-reset      Reset disposable demo state' \
	  '  make webapp-verify   Check webapp health' \
	  '  make invoice-inputs Check inputs for the Lightwell invoice scenario' \
	  '' \
	  '  make help-all        Show all maintenance commands' \
	  '' \
	  'Before setup, populate .env and select your kubeconfig.'

help-all:
	@printf '%s\n' \
	  'make / make help   Show commands; needs only Make and a shell' \
	  'make help-all      Show all setup and maintenance commands' \
	  'make bootstrap     Install platform, provision RHEL/nginx, and verify; publish branch first' \
	  'make teardown      Remove the complete demo stack, operators and persistent data' \
	  'make teardown-keep-aap Remove the demo while preserving AAP and its database volumes' \
	  'make render        Render manifests locally into .rendered/' \
	  'make preflight     Read-only local/cluster prerequisites; .env, manifest, KUBECONFIG' \
	  'make identity      Reconcile demo users and OIDC clients/providers on an installed stack' \
	  'make homepage-refresh Refresh dashboard links, repositories and environment details' \
	  'make model-config  Apply model/agent configuration from .env for new sessions' \
	  'make sandbox-build Build/publish the sandbox image in cluster; installed operators' \
	  'make demo-hydrate  Seed Forgejo and refresh agent/Backstage credentials' \
	  'make webapp-create Provision the RHEL webapp through AAP' \
	  'make webapp-nginx  Configure nginx through AAP' \
	  'make webapp-verify Read-only VM, HTTPS and blackbox checks' \
	  'make webapp-mcp    Install or disable guest diagnostics and reconcile AO RCA' \
	  'make webapp-mcp-verify Verify AO TLS authentication and selected diagnostic tools' \
	  'make webapp-mcp-rotate Rotate the machine credential through AAP and AO' \
	  'make webapp-protect Require human review and independent application validation' \
	  'make webapp-delete Delete the webapp VM and owned disk through AAP' \
	  'make aap-configure Bootstrap/refresh AAP credentials, license and configuration' \
	  'make aap-sync      Apply seeded config-as-code through AAP' \
	  'make ao-configure  Reconcile AO integrations and publish all demo workflows' \
	  'make demo-reset    Reset disposable demo repos, sessions, VMs/disks and AAP config' \
	  'Cluster commands load .env in their scripts; see README for inputs and setup.'

bootstrap:
	bash bootstrap/bootstrap.sh

teardown:
	bash bootstrap/bootstrap.sh teardown --confirm-demo-teardown

teardown-keep-aap:
	bash bootstrap/bootstrap.sh teardown --confirm-demo-teardown --keep-aap

identity:
	bash bootstrap/bootstrap.sh identity

homepage-refresh:
	bash bootstrap/bootstrap.sh homepage-refresh

model-config:
	bash bootstrap/bootstrap.sh model-config

sandbox-build:
	bash bootstrap/bootstrap.sh sandbox-build

demo-hydrate:
	bash bootstrap/bootstrap.sh hydrate

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

.PHONY: webapp-mcp webapp-mcp-verify webapp-mcp-rotate webapp-protect
webapp-protect:
	bash bootstrap/bootstrap.sh webapp protect

webapp-mcp:
	bash bootstrap/bootstrap.sh webapp mcp

webapp-mcp-verify:
	bash bootstrap/bootstrap.sh webapp mcp-verify

webapp-mcp-rotate:
	bash bootstrap/bootstrap.sh webapp mcp-rotate

aap-configure:
	bash bootstrap/bootstrap.sh aap-configure

ao-configure:
	bash bootstrap/bootstrap.sh ao-configure

demo-reset:
	bash bootstrap/bootstrap.sh demo-reset --confirm-demo-reset

render:
	@mkdir -p .rendered
	kustomize build bootstrap > .rendered/bootstrap.yaml
	kustomize build --enable-helm cluster > .rendered/cluster.yaml
	@for config in cluster/*/kustomization.yaml; do \
		app=$$(dirname "$$config"); \
		echo "Rendering $$app"; \
		kustomize build --enable-helm --helm-kube-version v1.31.0 "$$app" > ".rendered/$$(basename "$$app").yaml" || exit 1; \
	done

.PHONY: invoice-foundation invoice-publish invoice-inputs invoice-material invoice-discover invoice-configure invoice-baseline invoice-trigger invoice-protect invoice-validate invoice-promote invoice-verify
invoice-foundation:
	bash bootstrap/bootstrap.sh invoice foundation --backend aws
invoice-publish:
	bash bootstrap/bootstrap.sh invoice publish
invoice-inputs:
	bash bootstrap/bootstrap.sh invoice inputs
invoice-material:
	bash bootstrap/bootstrap.sh invoice material
invoice-discover:
	bash bootstrap/bootstrap.sh invoice discover
invoice-configure:
	bash bootstrap/bootstrap.sh invoice configure
invoice-baseline:
	bash bootstrap/bootstrap.sh invoice baseline
invoice-trigger:
	bash bootstrap/bootstrap.sh invoice trigger
invoice-protect:
	bash bootstrap/bootstrap.sh invoice protect
invoice-validate:
	@test -n "$(SHA)" || { echo 'Usage: make invoice-validate SHA=<published-head-sha>'; exit 2; }
	bash bootstrap/bootstrap.sh invoice validate "$(SHA)"
invoice-promote:
	@test -n "$(PR)" -a -n "$(JOB)" || { echo 'Usage: make invoice-promote PR=<merged-pr> JOB=<validation-job>'; exit 2; }
	bash bootstrap/bootstrap.sh invoice promote "$(PR)" "$(JOB)"
invoice-verify:
	bash bootstrap/bootstrap.sh invoice verify

.PHONY: pythonapp-create pythonapp-delete pythonapp-verify applications-upgrade
pythonapp-create:
	bash bootstrap/bootstrap.sh pythonapp create
pythonapp-delete:
	bash bootstrap/bootstrap.sh pythonapp delete
pythonapp-verify:
	bash bootstrap/bootstrap.sh pythonapp verify
applications-upgrade:
	bash bootstrap/bootstrap.sh invoice split-prepare
	bash bootstrap/bootstrap.sh
