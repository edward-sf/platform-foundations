#!/usr/bin/env bash
# Deletes every bootstrap resource and verifies each one is gone. Safe to re-run.
# Required env: EXPECTED_SUBSCRIPTION_ID, EXPECTED_TENANT_ID

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

delete_lock() {
  local acct
  acct=$(state_account)
  [[ -n "$acct" ]] || return 0
  log "deleting lock $PF_LOCK_NAME"
  az lock delete --name "$PF_LOCK_NAME" --resource-group "$PF_RG" \
    --resource-name "$acct" --resource-type Microsoft.Storage/storageAccounts || log "lock already gone"
}

delete_role_assignments() {
  local env pid ids id
  for env in dev prod; do
    pid=$(az identity show --name "id-pf-$env" --resource-group "$PF_RG" --query principalId -o tsv 2>/dev/null || true)
    [[ -n "$pid" ]] || continue
    ids=$(az role assignment list --assignee "$pid" --all --query '[].id' -o tsv)
    for id in $ids; do
      log "deleting role assignment $id"
      az role assignment delete --ids "$id"
    done
  done
}

delete_role_definition() {
  [[ -n "$(find_role_definition_ids)" ]] || return 0
  log "deleting custom role $PF_ROLE_NAME"
  az role definition delete --name "$PF_ROLE_NAME" --custom-role-only true \
    --scope "/subscriptions/$EXPECTED_SUBSCRIPTION_ID/resourceGroups/$PF_RG"
}

delete_budget() {
  if az consumption budget show --budget-name pf-budget >/dev/null 2>&1; then
    log "deleting budget pf-budget"
    az consumption budget delete --budget-name pf-budget
  fi
}

verify_gone() {
  local rc=0
  if [[ "$(az group exists --name "$PF_RG")" == "false" ]]; then log "ok: $PF_RG gone"; else log "FAIL: $PF_RG still exists"; rc=1; fi
  if [[ -z "$(find_role_definition_ids)" ]]; then log "ok: custom role gone"; else log "FAIL: custom role still exists"; rc=1; fi
  if ! az consumption budget show --budget-name pf-budget >/dev/null 2>&1; then log "ok: pf-budget gone"; else log "FAIL: pf-budget still exists"; rc=1; fi
  (( rc == 0 )) || die "teardown incomplete; see FAIL lines above"
  log "teardown verified"
}

main() {
  set -euo pipefail
  require_cmd az jq
  assert_az_context
  confirm "Delete every platform-foundations bootstrap resource in subscription $EXPECTED_SUBSCRIPTION_ID? Terraform state will be lost." \
    || die "aborted; nothing deleted"

  if [[ "$(az group exists --name "$PF_RG")" == "true" ]]; then
    delete_lock
    delete_role_assignments
    delete_role_definition
    log "deleting resource group $PF_RG (takes a few minutes)"
    az group delete --name "$PF_RG" --yes
  else
    log "resource group $PF_RG already gone"
    delete_role_definition
  fi
  delete_budget
  verify_gone
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
