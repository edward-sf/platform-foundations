setup_file() {
  export TEMPLATE="$BATS_FILE_TMPDIR/main.json"
  bicep build "$BATS_TEST_DIRNAME/../infra/bootstrap/main.bicep" --outfile "$TEMPLATE"
}

setup() {
  load helpers
}

resources_of_type() { jq -c --arg t "$1" '[.. | objects | select(.type? == $t)]' "$TEMPLATE"; }

@test "storage account disables shared keys, anonymous access and cross-tenant replication" {
  sa=$(resources_of_type Microsoft.Storage/storageAccounts | jq '.[0].properties')
  [ "$(jq .allowSharedKeyAccess <<<"$sa")" = "false" ]
  [ "$(jq .defaultToOAuthAuthentication <<<"$sa")" = "true" ]
  [ "$(jq .allowCrossTenantReplication <<<"$sa")" = "false" ]
  [ "$(jq .allowBlobPublicAccess <<<"$sa")" = "false" ]
  [ "$(jq -r .minimumTlsVersion <<<"$sa")" = "TLS1_2" ]
  [ "$(jq .supportsHttpsTrafficOnly <<<"$sa")" = "true" ]
}

@test "blob service keeps versions and soft-deleted blobs and containers for 7 days" {
  blob=$(resources_of_type Microsoft.Storage/storageAccounts/blobServices | jq '.[0].properties')
  [ "$(jq .isVersioningEnabled <<<"$blob")" = "true" ]
  [ "$(jq '.deleteRetentionPolicy.days' <<<"$blob")" = "7" ]
  [ "$(jq '.containerDeleteRetentionPolicy.days' <<<"$blob")" = "7" ]
}

@test "storage account carries a CanNotDelete lock" {
  resources_of_type Microsoft.Authorization/locks | jq -e '.[0].properties.level == "CanNotDelete"'
}

@test "custom role grants exactly three blob data actions and no control-plane actions" {
  perms=$(resources_of_type Microsoft.Authorization/roleDefinitions | jq '.[0].properties.permissions[0]')
  jq -e '(.dataActions | sort) == [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write"]' <<<"$perms"
  jq -e '(.actions // []) == []' <<<"$perms"
}

@test "federated credentials trust only the GitHub issuer and the Azure audience" {
  fic=$(resources_of_type Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials | jq '.[0].properties')
  [ "$(jq -r .issuer <<<"$fic")" = "https://token.actions.githubusercontent.com" ]
  jq -e '.audiences == ["api://AzureADTokenExchange"]' <<<"$fic"
}

@test "the federated subject is built from numeric repo IDs and the environment" {
  grep -qF 'repository_owner_id:{0}:repository_id:{1}:environment:{2}' "$TEMPLATE"
}

@test "role assignments name a service principal" {
  resources_of_type Microsoft.Authorization/roleAssignments | jq -e '.[0].properties.principalType == "ServicePrincipal"'
}

@test "the param file fails without PF_BUDGET_EMAIL" {
  run env -u PF_BUDGET_EMAIL PF_LOCATION=eastus2 PF_GITHUB_OWNER_ID=1 PF_GITHUB_REPO_ID=2 \
    PF_BUDGET_START_DATE=2026-09-01T00:00:00Z bicep build-params "$REPO_ROOT/infra/bootstrap/main.bicepparam" --stdout
  [ "$status" -ne 0 ]
}

@test "the param file reads its values from PF_ environment variables" {
  run env PF_LOCATION=eastus2 PF_GITHUB_OWNER_ID=1 PF_GITHUB_REPO_ID=2 PF_BUDGET_EMAIL=ops@example.invalid \
    PF_BUDGET_START_DATE=2026-09-01T00:00:00Z bicep build-params "$REPO_ROOT/infra/bootstrap/main.bicepparam" --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"ops@example.invalid"* ]]
}

@test "the deployment outputs the custom role ID for teardown" {
  jq -e '.outputs | has("roleDefinitionId")' "$TEMPLATE"
}
