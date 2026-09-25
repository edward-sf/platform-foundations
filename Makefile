# Operator entry points for platform-foundations. Run `make` for the list.
REPO := edward-sf/platform-foundations

.DEFAULT_GOAL := help
.PHONY: help doctor lint test github-setup bootstrap verify-bootstrap proof teardown

help: ## List targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check the local toolchain
	@scripts/doctor.sh

lint: ## Run the local lint suite (mirrors ci.yml except PSRule)
	pre-commit run --all-files

test: ## Run the bats tests
	bats tests

github-setup: ## Create and harden the GitHub repo (idempotent)
	scripts/github-setup.sh

bootstrap: ## Deploy the Bicep bootstrap (what-if, then confirm)
	scripts/bootstrap.sh

verify-bootstrap: ## Check the deployed bootstrap against the spec
	scripts/verify-bootstrap.sh

proof: ## Run oidc-proof.yml on main and wait for the result
	gh workflow run oidc-proof.yml --repo $(REPO) --ref main
	sleep 5
	gh run watch --repo $(REPO) --exit-status $$(gh run list --repo $(REPO) --workflow oidc-proof.yml --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')

teardown: ## Delete every bootstrap resource and verify it is gone
	scripts/teardown.sh
