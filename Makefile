.PHONY: test render test-health

render:
	@mkdir -p .rendered
	kustomize build bootstrap > .rendered/bootstrap.yaml
	kustomize build --enable-helm cluster > .rendered/cluster.yaml
	@for config in cluster/*/kustomization.yaml; do \
		app=$$(dirname "$$config"); \
		echo "Rendering $$app"; \
		kustomize build --enable-helm --helm-kube-version v1.31.0 "$$app" > ".rendered/$$(basename "$$app").yaml" || exit 1; \
	done

test: render
	bash -n bootstrap/*.sh scripts/*.sh tests/*.sh cluster/automation-orchestrator/*.sh cluster/forgejo-demo/scripts/*.sh
	bash tests/bootstrap.sh
	bash tests/model-config.sh
	bash tests/app-of-apps.sh
	bash tests/set-gitops-branch.sh
	kubeconform -strict -summary -ignore-missing-schemas .rendered/
	git diff --check

test-health:
	bash tests/health.sh
