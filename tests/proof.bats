setup() {
  load helpers
  source "$REPO_ROOT/scripts/proof.sh"
  WORK="$BATS_TEST_TMPDIR"
  export GITHUB_ACTIONS=true AZURE_TENANT_ID=ten-1 AZURE_CLIENT_ID_DEV=dev-client \
    AZURE_CLIENT_ID_PROD=prod-client TF_STATE_ACCOUNT=stpftest
  FAKE_JWT="eyJhbGciOiJSUzI1NiJ9.$(printf '%s' '{"sub":"repository_owner_id:1:repository_id:2:environment:dev"}' | base64 | tr -d '=\n' | tr '/+' '_-').sig"
  ENTRA_DEV_CODE=200
  CONTROL_CODE=200
  DENIAL_CODE=403

  gh_oidc_token() { printf '%s\n' "$FAKE_JWT"; }
  entra_token_request() {
    if [[ "$1" == "dev-client" && "$ENTRA_DEV_CODE" == "200" ]]; then
      echo '{"access_token":"SECRET-ACCESS-TOKEN"}' > "$3"; echo 200
    else
      echo '{"error":"invalid_client","error_description":"AADSTS700213: No matching federated identity record found"}' > "$3"; echo 400
    fi
  }
  storage_request() {
    printf '%s %s\n' "$1" "$2" >> "$BATS_TEST_TMPDIR/storage.log"
    if [[ "$1" == "GET" && "$2" == "/tfstate-dev?restype=container&comp=list" ]]; then
      echo '<EnumerationResults/>' > "$4"; echo "$CONTROL_CODE"
    else
      echo '<Error><Code>AuthorizationPermissionMismatch</Code></Error>' > "$4"; echo "$DENIAL_CODE"
    fi
  }
}

@test "cross-env-state passes when the control succeeds and prod state is denied" {
  run case_cross_env_state
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/storage.log")" = "GET /tfstate-dev?restype=container&comp=list" ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/storage.log")" = "GET /tfstate-prod?restype=container&comp=list" ]
}

@test "a failing positive control fails the job before any denial is attempted" {
  CONTROL_CODE=403
  run case_cross_env_state
  [ "$status" -eq 1 ]
  [[ "$output" == *"positive control failed"* ]]
  ! grep -q tfstate-prod "$BATS_TEST_TMPDIR/storage.log"
}

@test "a refused dev token exchange fails the job as a broken control" {
  ENTRA_DEV_CODE=400
  run case_container_delete
  [ "$status" -eq 1 ]
  [[ "$output" == *"positive control failed: token exchange for dev-client"* ]]
}

@test "container-delete fails when the delete unexpectedly succeeds" {
  DENIAL_CODE=202
  run case_container_delete
  [ "$status" -eq 1 ]
  [[ "$output" == *"request succeeded with HTTP 202"* ]]
  grep -qxF "DELETE /tfstate-dev?restype=container" "$BATS_TEST_TMPDIR/storage.log"
}

@test "delegation-key passes on 403 AuthorizationPermissionMismatch" {
  run case_delegation_key
  [ "$status" -eq 0 ]
  grep -qxF "POST /?restype=service&comp=userdelegationkey" "$BATS_TEST_TMPDIR/storage.log"
}

@test "no-environment passes when Entra refuses the exchange" {
  ENTRA_DEV_CODE=400
  run case_no_environment
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: denied"*"AADSTS700213"* ]]
}

@test "no-environment fails when Entra issues a token" {
  run case_no_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"request succeeded"* ]]
}

@test "cross-identity passes when the prod exchange is refused" {
  run case_cross_identity
  [ "$status" -eq 0 ]
}

@test "tokens appear only in add-mask lines" {
  run case_cross_env_state
  [ "$status" -eq 0 ]
  local line
  while IFS= read -r line; do
    if [[ "$line" == *SECRET-ACCESS-TOKEN* || "$line" == *"$FAKE_JWT"* ]]; then
      [[ "$line" == "::add-mask::"* ]]
    fi
  done <<<"$output"
  [[ "$output" == *"::add-mask::SECRET-ACCESS-TOKEN"* ]]
  [[ "$output" == *"::add-mask::$FAKE_JWT"* ]]
}

@test "claims logs the subject without the token" {
  run case_claims
  [ "$status" -eq 0 ]
  [[ "$output" == *"repository_owner_id:1:repository_id:2:environment:dev"* ]]
}

@test "an unknown case is a usage error" {
  run main nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown case: nope"* ]]
}
