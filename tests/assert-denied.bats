setup() {
  load helpers
  A="$REPO_ROOT/scripts/assert-denied.sh"
  B="$BATS_TEST_TMPDIR/body"
}

@test "passes on the expected status and error code" {
  echo '<Error><Code>AuthorizationPermissionMismatch</Code></Error>' > "$B"
  run "$A" --status 403 --body-file "$B" --expect-status 403 --expect-error AuthorizationPermissionMismatch
  [ "$status" -eq 0 ]
  [[ "$output" == PASS:* ]]
}

@test "passes on an Entra error code with no status expectation" {
  echo '{"error":"invalid_client","error_description":"AADSTS700213: No matching federated identity record found"}' > "$B"
  run "$A" --status 400 --body-file "$B" --expect-error AADSTS700213
  [ "$status" -eq 0 ]
}

@test "fails on unexpected success and never prints the body" {
  echo '{"access_token":"SECRET-VALUE"}' > "$B"
  run "$A" --status 200 --body-file "$B" --expect-error AADSTS700213
  [ "$status" -eq 1 ]
  [[ "$output" == *"request succeeded with HTTP 200"* ]]
  [[ "$output" != *"SECRET-VALUE"* ]]
}

@test "fails on a different status" {
  echo '<Code>AuthorizationPermissionMismatch</Code>' > "$B"
  run "$A" --status 401 --body-file "$B" --expect-status 403 --expect-error AuthorizationPermissionMismatch
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected HTTP 403, got HTTP 401"* ]]
}

@test "fails when the error code differs" {
  echo '<Error><Code>InvalidAuthenticationInfo</Code></Error>' > "$B"
  run "$A" --status 403 --body-file "$B" --expect-status 403 --expect-error AuthorizationPermissionMismatch
  [ "$status" -eq 1 ]
  [[ "$output" == *"lacks 'AuthorizationPermissionMismatch'"* ]]
}

@test "fails when no response arrived" {
  : > "$B"
  run "$A" --status 000 --body-file "$B" --expect-error AADSTS700213
  [ "$status" -eq 1 ]
  [[ "$output" == *"no response"* ]]
}

@test "fails on a non-numeric status" {
  : > "$B"
  run "$A" --status "" --body-file "$B" --expect-error X
  [ "$status" -eq 2 ]
}

@test "exits 2 when arguments are missing" {
  run "$A" --status 403
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
