.PHONY: help lint template package index release kind-install kind-create clean

REPO_NAME := llm-center
CHARTS := $(wildcard charts/*/)
HELM_VERSION := 3.14.0
KIND_VERSION := 0.20.0

help:
	@echo "Helm LLM Inference Repository - Make targets:"
	@echo "  make lint          - Lint all charts (requires Helm)"
	@echo "  make template      - Render all charts (dry-run)"
	@echo "  make package       - Package all charts to .tgz"
	@echo "  make index         - Generate index.yaml"
	@echo "  make release       - Full release: package + index + commit + tag"
	@echo "  make kind-install  - Install a chart to kind cluster"
	@echo "  make kind-create   - Create kind cluster"
	@echo "  make clean         - Clean packaged charts"

lint:
	@for chart in $(CHARTS); do \
		echo "Linting $$chart..."; \
		helm lint $$chart || exit 1; \
	done
	@echo "All charts passed lint"

template:
	@for chart in $(CHARTS); do \
		echo "Templating $$chart..."; \
		helm template test-$$(basename $$chart) $$chart | head -20; \
		echo "---"; \
	done

package:
	@mkdir -p packages
	@for chart in $(CHARTS); do \
		helm package $$chart --destination packages/; \
	done
	@echo "Packaged all charts to packages/"

index: package
	@helm repo index packages --url https://axeprpr.github.io/helm-llm-repo --merge packages/index.yaml
	@cat packages/index.yaml | head -30
	@echo "Index generated at packages/index.yaml"

release: index
	@git add packages/
	@git commit -m "Release charts $(shell date +%Y-%m-%d)" || true
	@git push origin main || true

kind-create:
	@kind get clusters | grep llm-test && echo "Cluster exists" || \
		kind create cluster --name llm-test

kind-install: kind-create
	@echo "Installing vllm-inference to kind..."
	@helm install test-vllm charts/vllm-inference \
		--set model.name=Qwen/Qwen2.5-0.5B-Instruct \
		--set resources.limits.nvidia.com/gpu=0 \
		--set resources.limits.cpu=1 \
		--set resources.limits.memory=2Gi \
		-n default \
		--create-namespace

kind-delete:
	@kind delete cluster --name llm-test || true

clean:
	@rm -rf packages/*.tgz
	@echo "Cleaned packages/"
