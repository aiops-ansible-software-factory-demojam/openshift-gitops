.PHONY: render demo-reset aap-ee aap-configure

aap-ee:
	bash cluster/forgejo-demo/fixtures/aap-config-as-code/scripts/aap.sh build

aap-configure:
	bash cluster/forgejo-demo/fixtures/aap-config-as-code/scripts/aap.sh configure

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
