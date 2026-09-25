setup() {
  load helpers
  setup_stubs
  export EXPECTED_SUBSCRIPTION_ID=sub-1 EXPECTED_TENANT_ID=ten-1 PF_LOCATION=eastus2 PF_BUDGET_EMAIL=ops@example.invalid
  stub az '
case "$*" in
  "account show"*) echo "{\"id\":\"sub-1\",\"tenantId\":\"ten-1\"}" ;;
  "consumption budget show"*) if [[ -n "${EXISTING_BUDGET_START:-}" ]]; then echo "$EXISTING_BUDGET_START"; else exit 1; fi ;;
  "deployment sub what-if"*) echo "what-if: 12 to create" ;;
  "deployment sub create"*) echo "{\"tenantId\":{\"value\":\"ten-1\"},\"subscriptionId\":{\"value\":\"sub-1\"},\"storageAccountName\":{\"value\":\"stpfabc\"},\"devClientId\":{\"value\":\"dev-cid\"},\"prodClientId\":{\"value\":\"prod-cid\"}}" ;;
esac'
  stub gh '
case "$*" in
  "api user --jq .login") echo edward-sf ;;
  "api repos/edward-sf/platform-foundations --jq .owner.id") echo 111 ;;
  "api repos/edward-sf/platform-foundations --jq .id") echo 222 ;;
esac'
}

run_bootstrap() { run bash -c "printf '%s\n' '$1' | '$REPO_ROOT/scripts/bootstrap.sh'"; }

@test "deploys after what-if and a yes, then writes five repo variables" {
  run_bootstrap y
  [ "$status" -eq 0 ]
  [ "$(line_of 'az deployment sub what-if')" -lt "$(line_of 'az deployment sub create')" ]
  grep -qF 'main.bicepparam' "$STUB_LOG"
  grep -qF 'gh variable set AZURE_TENANT_ID --repo edward-sf/platform-foundations --body ten-1' "$STUB_LOG"
  grep -qF 'gh variable set AZURE_SUBSCRIPTION_ID --repo edward-sf/platform-foundations --body sub-1' "$STUB_LOG"
  grep -qF 'gh variable set AZURE_CLIENT_ID_DEV --repo edward-sf/platform-foundations --body dev-cid' "$STUB_LOG"
  grep -qF 'gh variable set AZURE_CLIENT_ID_PROD --repo edward-sf/platform-foundations --body prod-cid' "$STUB_LOG"
  grep -qF 'gh variable set TF_STATE_ACCOUNT --repo edward-sf/platform-foundations --body stpfabc' "$STUB_LOG"
}

@test "answering no deploys nothing" {
  run_bootstrap n
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing deployed"* ]]
  [ -n "$(line_of 'az deployment sub what-if')" ]
  [ -z "$(line_of 'az deployment sub create')" ]
  [ -z "$(line_of 'gh variable set')" ]
}

@test "refuses to run against another subscription" {
  export EXPECTED_SUBSCRIPTION_ID=other-sub
  run_bootstrap y
  [ "$status" -eq 1 ]
  [ -z "$(line_of 'az deployment')" ]
}

@test "requires the budget email before touching Azure" {
  unset PF_BUDGET_EMAIL
  run_bootstrap y
  [ "$status" -eq 1 ]
  [[ "$output" == *"PF_BUDGET_EMAIL"* ]]
  [ -z "$(line_of 'az deployment')" ]
}

@test "reuses the existing budget start date" {
  export EXISTING_BUDGET_START=2026-09-01T00:00:00Z
  source "$REPO_ROOT/scripts/bootstrap.sh"
  run budget_start_date
  [ "$output" = "2026-09-01T00:00:00Z" ]
}

@test "starts a new budget at the first of the current month" {
  source "$REPO_ROOT/scripts/bootstrap.sh"
  run budget_start_date
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-01T00:00:00Z$ ]]
}

@test "refuses to write a variable for a missing output" {
  source "$REPO_ROOT/scripts/bootstrap.sh"
  run set_github_variables '{"tenantId":{"value":"ten-1"}}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing deployment output"* ]]
}
