setup() {
  load helpers
  setup_stubs
  source "$REPO_ROOT/scripts/lib/common.sh"
  export EXPECTED_SUBSCRIPTION_ID=sub-1 EXPECTED_TENANT_ID=ten-1
}

@test "require_cmd fails naming the missing command" {
  run require_cmd definitely-not-a-command
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required command: definitely-not-a-command"* ]]
}

@test "require_env fails for an empty variable" {
  EMPTY_VAR=""
  run require_env EMPTY_VAR
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required environment variable: EMPTY_VAR"* ]]
}

@test "require_env passes for set variables" {
  SOME_VAR=x
  run require_env SOME_VAR
  [ "$status" -eq 0 ]
}

@test "assert_az_context passes on the expected subscription and tenant" {
  stub az 'echo "{\"id\":\"sub-1\",\"tenantId\":\"ten-1\"}"'
  run assert_az_context
  [ "$status" -eq 0 ]
}

@test "assert_az_context refuses a different subscription" {
  stub az 'echo "{\"id\":\"work-sub\",\"tenantId\":\"ten-1\"}"'
  run assert_az_context
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match EXPECTED_SUBSCRIPTION_ID"* ]]
}

@test "assert_az_context refuses a different tenant" {
  stub az 'echo "{\"id\":\"sub-1\",\"tenantId\":\"work-tenant\"}"'
  run assert_az_context
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match EXPECTED_TENANT_ID"* ]]
}

@test "assert_az_context fails clearly when not signed in" {
  stub az 'exit 1'
  run assert_az_context
  [ "$status" -eq 1 ]
  [[ "$output" == *"not signed in to Azure"* ]]
}

@test "assert_az_context requires both expected IDs" {
  unset EXPECTED_TENANT_ID
  stub az 'echo "{}"'
  run assert_az_context
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXPECTED_TENANT_ID"* ]]
}

@test "assert_gh_user refuses another account" {
  stub gh 'echo someone-else'
  run assert_gh_user
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected edward-sf"* ]]
}

@test "assert_gh_user passes for edward-sf" {
  stub gh 'echo edward-sf'
  run assert_gh_user
  [ "$status" -eq 0 ]
}

@test "confirm accepts y and yes" {
  run confirm "Proceed?" <<<"y"
  [ "$status" -eq 0 ]
  run confirm "Proceed?" <<<"yes"
  [ "$status" -eq 0 ]
}

@test "confirm rejects anything else, including empty input and EOF" {
  run confirm "Proceed?" <<<"n"
  [ "$status" -eq 1 ]
  run confirm "Proceed?" <<<""
  [ "$status" -eq 1 ]
  run confirm "Proceed?" </dev/null
  [ "$status" -eq 1 ]
}
