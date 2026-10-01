.PHONY: preflight render demo-reset aap-configure aap-sync webapp-create webapp-nginx webapp-delete webapp-verify

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
