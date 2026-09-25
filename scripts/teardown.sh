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
  az_absent_ok lock delete --name "$PF_LOCK_NAME" --resource-group "$PF_RG" \
    --resource-name "$acct" --resource-type Microsoft.Storage/storageAccounts >/dev/null
}

delete_role_assignments() {
  local env pid ids id
  for env in dev prod; do
    pid=$(az_absent_ok identity show --name "id-pf-$env" --resource-group "$PF_RG" --query principalId -o tsv)
    [[ -n "$pid" ]] || continue
    ids=$(az role assignment list --assignee "$pid" --all --query '[].id' -o tsv)
    for id in $ids; do
      log "deleting role assignment $id"
      az role assignment delete --ids "$id"
    done
  done
}

# Deletes the custom role by the ID the bootstrap deployment recorded, which
# still resolves after the resource group is gone.
delete_role_definition() {
  local id
  id=$(find_role_definition_ids) || exit 1
  [[ -n "$id" ]] || return 0
  log "deleting custom role $PF_ROLE_NAME"
  az rest --method delete --url "https://management.azure.com${id}?api-version=2022-04-01" >/dev/null
}

# Prints "pf-budget" if the budget exists, nothing if absent; fails on lookup errors.
# Callers capture it with `|| exit 1`: a failure inside $(...) or an if-condition
# would otherwise read as "absent".
budget_name() {
  az_absent_ok consumption budget show --budget-name pf-budget --query name -o tsv
}

delete_budget() {
  local budget
  budget=$(budget_name) || exit 1
  if [[ -n "$budget" ]]; then
    log "deleting budget pf-budget"
    az consumption budget delete --budget-name pf-budget
  fi
}

verify_gone() {
  local rc=0 group role budget
  group=$(az group exists --name "$PF_RG") || exit 1
  role=$(find_role_definition_ids) || exit 1
  budget=$(budget_name) || exit 1
  if [[ "$group" == "false" ]]; then log "ok: $PF_RG gone"; else log "FAIL: $PF_RG still exists"; rc=1; fi
  if [[ -z "$role" ]]; then log "ok: custom role gone"; else log "FAIL: custom role still exists"; rc=1; fi
  if [[ -z "$budget" ]]; then log "ok: pf-budget gone"; else log "FAIL: pf-budget still exists"; rc=1; fi
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
