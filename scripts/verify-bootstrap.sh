#!/usr/bin/env bash
# Checks the deployed bootstrap against the M1 spec. Exits 1 if any check fails.
# Required env: EXPECTED_SUBSCRIPTION_ID, EXPECTED_TENANT_ID

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

# check DESC FILTER JSON [jq args...]: FILTER must evaluate to true.
check() {
  local desc=$1 filter=$2 json=$3
  shift 3
  if jq -e "$@" "$filter" >/dev/null 2>&1 <<<"$json"; then
    printf 'ok: %s\n' "$desc"
  else
    printf 'FAIL: %s\n' "$desc"
    return 1
  fi
}

check_storage() {
  local j=$1 rc=0
  check "shared-key access disabled" '.allowSharedKeyAccess == false' "$j" || rc=1
  check "Entra auth is the default" '.defaultToOAuthAuthentication == true' "$j" || rc=1
  check "cross-tenant replication disabled" '.allowCrossTenantReplication == false' "$j" || rc=1
  check "anonymous blob access disabled" '.allowBlobPublicAccess == false' "$j" || rc=1
  check "minimum TLS 1.2" '.minimumTlsVersion == "TLS1_2"' "$j" || rc=1
  check "HTTPS only" '.enableHttpsTrafficOnly == true' "$j" || rc=1
  return "$rc"
}

check_blob_service() {
  local j=$1 rc=0
  check "blob versioning on" '.isVersioningEnabled == true' "$j" || rc=1
  check "blob soft delete, 7 days" '.deleteRetentionPolicy.enabled == true and .deleteRetentionPolicy.days == 7' "$j" || rc=1
  check "container soft delete, 7 days" '.containerDeleteRetentionPolicy.enabled == true and .containerDeleteRetentionPolicy.days == 7' "$j" || rc=1
  return "$rc"
}

check_lock() {
  check "CanNotDelete lock on the state account" 'any(.[]; .level == "CanNotDelete")' "$1"
}

# check_role_assignments JSON ENV: exactly one assignment, on tfstate-ENV, with the custom role.
check_role_assignments() {
  check "id-pf-$2 holds only the state role on tfstate-$2" \
    'length == 1 and (.[0].scope | endswith("/blobServices/default/containers/tfstate-" + $env)) and .[0].roleDefinitionName == $role' \
    "$1" --arg env "$2" --arg role "$PF_ROLE_NAME"
}

# check_federated_credentials JSON SUBJECT: exactly one credential, trusting SUBJECT only.
check_federated_credentials() {
  check "federated credential trusts only $2" \
    'length == 1 and .[0].subject == $s and .[0].issuer == "https://token.actions.githubusercontent.com" and .[0].audiences == ["api://AzureADTokenExchange"]' \
    "$1" --arg s "$2"
}

# check_role_definition IDS: the custom role is visible to the same lookup teardown uses.
check_role_definition() {
  if [[ -n "$1" ]]; then
    printf 'ok: custom role %s exists\n' "$PF_ROLE_NAME"
  else
    printf 'FAIL: custom role %s exists\n' "$PF_ROLE_NAME"
    return 1
  fi
}

expected_subject() { printf 'repository_owner_id:%s:repository_id:%s:environment:%s\n' "$1" "$2" "$3"; }

main() {
  set -euo pipefail
  require_cmd az gh jq
  assert_az_context
  assert_gh_user

  local owner_id repo_id acct env pid rc=0
  owner_id=$(gh api "repos/$PF_REPO" --jq .owner.id)
  repo_id=$(gh api "repos/$PF_REPO" --jq .id)
  acct=$(state_account)
  [[ -n "$acct" ]] || die "no stpf* storage account in $PF_RG; run make bootstrap first"

  check_storage "$(az storage account show --name "$acct" --resource-group "$PF_RG" -o json)" || rc=1
  check_blob_service "$(az storage account blob-service-properties show --account-name "$acct" --resource-group "$PF_RG" -o json)" || rc=1
  check_lock "$(az lock list --resource-group "$PF_RG" --resource-name "$acct" --resource-type Microsoft.Storage/storageAccounts -o json)" || rc=1
  check_role_definition "$(find_role_definition_ids)" || rc=1
  for env in dev prod; do
    pid=$(az identity show --name "id-pf-$env" --resource-group "$PF_RG" --query principalId -o tsv)
    check_role_assignments "$(az role assignment list --assignee "$pid" --all -o json)" "$env" || rc=1
    check_federated_credentials "$(az identity federated-credential list --identity-name "id-pf-$env" --resource-group "$PF_RG" -o json)" \
      "$(expected_subject "$owner_id" "$repo_id" "$env")" || rc=1
  done

  if (( rc == 0 )); then
    log "bootstrap verified"
  else
    die "bootstrap verification failed"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
