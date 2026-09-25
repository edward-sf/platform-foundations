#!/usr/bin/env bash
# Deploys the Bicep bootstrap and writes its outputs to GitHub repo variables.
# Run once, as subscription Owner, from the operator's laptop.
# Required env: EXPECTED_SUBSCRIPTION_ID, EXPECTED_TENANT_ID, PF_LOCATION, PF_BUDGET_EMAIL
# Optional env: PF_DEPLOY_BUDGET (default true; set false if the offer rejects budgets)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

PARAMS_FILE="$HERE/../infra/bootstrap/main.bicepparam"
DEPLOYMENT_NAME="pf-bootstrap"

# Keeps an existing budget's start date so redeploys don't try to move it.
budget_start_date() {
  local existing
  existing=$(az consumption budget show --budget-name pf-budget --query timePeriod.startDate -o tsv 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    printf '%s\n' "$existing"
  else
    date -u +%Y-%m-01T00:00:00Z
  fi
}

# set_github_variables OUTPUTS_JSON: writes deployment outputs to repo variables.
set_github_variables() {
  local outputs=$1 pair name key value
  for pair in AZURE_TENANT_ID:tenantId AZURE_SUBSCRIPTION_ID:subscriptionId \
      AZURE_CLIENT_ID_DEV:devClientId AZURE_CLIENT_ID_PROD:prodClientId TF_STATE_ACCOUNT:storageAccountName; do
    name=${pair%%:*}
    key=${pair#*:}
    value=$(jq -r --arg k "$key" '.[$k].value // empty' <<<"$outputs")
    [[ -n "$value" ]] || die "missing deployment output: $key"
    gh variable set "$name" --repo "$PF_REPO" --body "$value"
  done
}

main() {
  set -euo pipefail
  require_cmd az gh jq
  require_env PF_LOCATION PF_BUDGET_EMAIL
  assert_az_context
  assert_gh_user

  PF_GITHUB_OWNER_ID=$(gh api "repos/$PF_REPO" --jq .owner.id)
  PF_GITHUB_REPO_ID=$(gh api "repos/$PF_REPO" --jq .id)
  PF_DEPLOY_BUDGET=${PF_DEPLOY_BUDGET:-true}
  PF_BUDGET_START_DATE=$(budget_start_date)
  export PF_GITHUB_OWNER_ID PF_GITHUB_REPO_ID PF_DEPLOY_BUDGET PF_BUDGET_START_DATE

  local ns
  for ns in Microsoft.Storage Microsoft.ManagedIdentity; do
    log "registering resource provider $ns"
    az provider register --namespace "$ns" --wait
  done

  local args=(--name "$DEPLOYMENT_NAME" --location "$PF_LOCATION" --parameters "$PARAMS_FILE")
  log "what-if against subscription $EXPECTED_SUBSCRIPTION_ID"
  az deployment sub what-if "${args[@]}"
  confirm "Deploy these changes?" || die "aborted; nothing deployed"

  local outputs
  outputs=$(az deployment sub create "${args[@]}" --query properties.outputs -o json)
  set_github_variables "$outputs"
  log "bootstrap deployed. Next: make verify-bootstrap"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
