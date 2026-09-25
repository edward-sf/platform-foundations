setup() {
  load helpers
  source "$REPO_ROOT/scripts/verify-bootstrap.sh"
  GOOD_SA='{"allowSharedKeyAccess":false,"defaultToOAuthAuthentication":true,"allowCrossTenantReplication":false,"allowBlobPublicAccess":false,"minimumTlsVersion":"TLS1_2","enableHttpsTrafficOnly":true}'
  GOOD_BLOB='{"isVersioningEnabled":true,"deleteRetentionPolicy":{"enabled":true,"days":7},"containerDeleteRetentionPolicy":{"enabled":true,"days":7}}'
  GOOD_LOCKS='[{"name":"pf-state-lock","level":"CanNotDelete"}]'
  SCOPE="/subscriptions/s/resourceGroups/rg-pf-bootstrap/providers/Microsoft.Storage/storageAccounts/stpfx/blobServices/default/containers/tfstate-dev"
  GOOD_RA="[{\"scope\":\"$SCOPE\",\"roleDefinitionName\":\"Terraform State Writer (pf)\"}]"
  SUBJ="repository_owner_id:1:repository_id:2:environment:dev"
  GOOD_FIC="[{\"subject\":\"$SUBJ\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"audiences\":[\"api://AzureADTokenExchange\"]}]"
}

@test "a correctly configured storage account passes" {
  run check_storage "$GOOD_SA"
  [ "$status" -eq 0 ]
}

@test "shared-key access left on fails" {
  run check_storage "$(jq '.allowSharedKeyAccess = true' <<<"$GOOD_SA")"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: shared-key access disabled"* ]]
}

@test "a missing property fails instead of passing" {
  run check_storage "$(jq 'del(.allowSharedKeyAccess)' <<<"$GOOD_SA")"
  [ "$status" -eq 1 ]
}

@test "blob service with versioning off fails" {
  run check_blob_service "$GOOD_BLOB"
  [ "$status" -eq 0 ]
  run check_blob_service "$(jq '.isVersioningEnabled = false' <<<"$GOOD_BLOB")"
  [ "$status" -eq 1 ]
}

@test "a missing lock fails" {
  run check_lock "$GOOD_LOCKS"
  [ "$status" -eq 0 ]
  run check_lock '[]'
  [ "$status" -eq 1 ]
}

@test "exactly one container-scoped assignment passes" {
  run check_role_assignments "$GOOD_RA" dev
  [ "$status" -eq 0 ]
}

@test "an extra subscription-scope assignment fails" {
  run check_role_assignments "$(jq '. + [{"scope":"/subscriptions/s","roleDefinitionName":"Reader"}]' <<<"$GOOD_RA")" dev
  [ "$status" -eq 1 ]
}

@test "an assignment on the other environment's container fails" {
  run check_role_assignments "$GOOD_RA" prod
  [ "$status" -eq 1 ]
}

@test "a federated credential with the default repo: subject fails" {
  run check_federated_credentials "$GOOD_FIC" "$SUBJ"
  [ "$status" -eq 0 ]
  run check_federated_credentials "$(jq '.[0].subject = "repo:edward-sf/platform-foundations:environment:dev"' <<<"$GOOD_FIC")" "$SUBJ"
  [ "$status" -eq 1 ]
}

@test "a missing custom role fails" {
  run check_role_definition "/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/abc"
  [ "$status" -eq 0 ]
  run check_role_definition ""
  [ "$status" -eq 1 ]
}

@test "expected_subject uses numeric IDs" {
  run expected_subject 1 2 dev
  [ "$output" = "$SUBJ" ]
}
