setup() {
  load helpers
  setup_stubs
  source "$REPO_ROOT/scripts/lib/common.sh"
  source "$REPO_ROOT/scripts/lib/http.sh"
  source "$REPO_ROOT/scripts/lib/token.sh"
}

b64url() { printf '%s' "$1" | base64 | tr -d '=\n' | tr '/+' '_-'; }
make_jwt() { printf '%s.%s.sig' "$(b64url '{"alg":"RS256"}')" "$(b64url "$1")"; }

@test "jwt_claims keeps only the identifying claims" {
  jwt=$(make_jwt '{"sub":"repository_owner_id:1:repository_id:2:environment:dev","aud":"api://AzureADTokenExchange","iss":"https://token.actions.githubusercontent.com","environment":"dev","repository_id":"2","repository_owner_id":"1","extra":"x"}')
  run jwt_claims "$jwt"
  [ "$status" -eq 0 ]
  [ "$(jq -r .sub <<<"$output")" = "repository_owner_id:1:repository_id:2:environment:dev" ]
  [ "$(jq -r .aud <<<"$output")" = "api://AzureADTokenExchange" ]
  [ "$(jq -r 'has("extra")' <<<"$output")" = "false" ]
}

@test "jwt_claims decodes payloads of every padding length" {
  local p
  for p in '{"sub":"a"}' '{"sub":"ab"}' '{"sub":"abc"}'; do
    run jwt_claims "$(make_jwt "$p")"
    [ "$status" -eq 0 ]
    [ "$(jq -r .sub <<<"$output")" = "$(jq -r .sub <<<"$p")" ]
  done
}

@test "mask emits add-mask only inside GitHub Actions" {
  GITHUB_ACTIONS=true run mask secret-value
  [ "$output" = "::add-mask::secret-value" ]
  GITHUB_ACTIONS= run mask secret-value
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "http_request reports 000 when curl cannot connect" {
  stub curl 'printf 000; exit 7'
  run http_request GET https://unreachable.invalid "$BATS_TEST_TMPDIR/out"
  [ "$output" = "000" ]
}

@test "http_request prints the status and writes the body" {
  stub curl 'for a; do if [[ $prev == -o ]]; then echo body > "$a"; fi; prev=$a; done; printf 201'
  run http_request POST https://example.invalid "$BATS_TEST_TMPDIR/out" --data x
  [ "$output" = "201" ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "body" ]
}

@test "gh_oidc_token fails clearly without id-token permission" {
  unset ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN
  run gh_oidc_token
  [ "$status" -eq 1 ]
  [[ "$output" == *"ACTIONS_ID_TOKEN_REQUEST_URL"* ]]
}

@test "gh_oidc_token requests the Azure audience and prints the token" {
  export ACTIONS_ID_TOKEN_REQUEST_URL="https://example.invalid/token?x=1" ACTIONS_ID_TOKEN_REQUEST_TOKEN=rt
  http_request() { printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/req"; echo '{"value":"gh-jwt"}' > "$3"; echo 200; }
  run gh_oidc_token
  [ "$status" -eq 0 ]
  [ "$output" = "gh-jwt" ]
  grep -qxF 'https://example.invalid/token?x=1&audience=api://AzureADTokenExchange' "$BATS_TEST_TMPDIR/req"
}

@test "gh_oidc_token fails on a non-200 response" {
  export ACTIONS_ID_TOKEN_REQUEST_URL="https://example.invalid/token?x=1" ACTIONS_ID_TOKEN_REQUEST_TOKEN=rt
  http_request() { echo '{}' > "$3"; echo 403; }
  run gh_oidc_token
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP 403"* ]]
}

@test "entra_token_request posts a client-credentials federated assertion" {
  export AZURE_TENANT_ID=ten-1
  http_request() { printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/req"; echo 200; }
  run entra_token_request client-1 the-assertion "$BATS_TEST_TMPDIR/out"
  [ "$output" = "200" ]
  local r="$BATS_TEST_TMPDIR/req"
  grep -qxF 'POST' "$r"
  grep -qxF 'https://login.microsoftonline.com/ten-1/oauth2/v2.0/token' "$r"
  grep -qxF 'client_id=client-1' "$r"
  grep -qxF 'client_assertion=the-assertion' "$r"
  grep -qxF 'grant_type=client_credentials' "$r"
  grep -qxF 'scope=https://storage.azure.com/.default' "$r"
  grep -qxF 'client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer' "$r"
}
