# tflab-aws - local shortcuts. The same steps run in GitHub Actions (up/down/drill/regression).
# Prereqs: aws (signed in as admin), terraform >= 1.10, kubectl, gh, jq, node 22.

SHELL := /bin/bash
TAG   ?= $(shell git rev-parse HEAD)
DRILL ?= list
REGION ?= syd
TARGET ?= app

.PHONY: help bootstrap build up down drill test leftovers kubeconfig fmt

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

bootstrap: ## one-time account setup (state bucket, OIDC role, ECR, budget guard, GitHub env)
	./bootstrap/bootstrap.sh

build: ## build + push images for the current commit (runs on GitHub's ARM runners)
	gh workflow run build.yml --ref main && gh run watch --exit-status $$(gh run list --workflow build.yml -L1 --json databaseId -q '.[0].databaseId')

up: ## stand up both regions (~30-40 min)
	./scripts/up.sh $(TAG)

down: ## DRAIN teardown + leftovers sweep
	./scripts/down.sh

drill: ## make drill DRILL=db-block REGION=syd   (make drill = catalogue)
	./drills/drill.sh $(DRILL) $(REGION)

test: ## regression suite: make test TARGET=app|syd|mel
	cd tests/regression && npm ci && npx playwright install chromium && BASE_URL=https://$(TARGET).mimidog.click npx playwright test

leftovers: ## report anything billable still running
	./scripts/leftovers.sh

kubeconfig: ## add tflab-syd / tflab-mel kubectl contexts
	./scripts/kubeconfig.sh

fmt: ## terraform fmt
	terraform fmt -recursive
