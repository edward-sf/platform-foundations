setup() {
  load helpers
  setup_stubs
  stub git 'exit 0'
  stub gh '
case "$*" in
  "api user --jq .login") echo "${GH_LOGIN:-edward-sf}" ;;
  "api user --jq .id") echo 999 ;;
  "repo view"*) exit 0 ;;
  "api repos/edward-sf/platform-foundations/branches/main") echo "{}" ;;
  *"deployment-branch-policies --jq"*) if [[ -n "${POLICY_EXISTS:-}" ]]; then echo main; fi ;;
  "api repos/edward-sf/platform-foundations/rulesets --jq"*) echo "${RULESET_ID:-}" ;;
  "api repos/edward-sf/platform-foundations/contents/.github/workflows?ref=main") if [[ -n "${NO_WORKFLOWS_ON_MAIN:-}" ]]; then exit 1; fi; echo "[]" ;;
esac'
}

@test "refuses to run as another GitHub account" {
  GH_LOGIN=someone-else run "$REPO_ROOT/scripts/github-setup.sh"
  [ "$status" -eq 1 ]
  ! grep -q -- '-X PUT' "$STUB_LOG"
}

@test "customises the OIDC subject to numeric IDs and the environment" {
  run "$REPO_ROOT/scripts/github-setup.sh"
  [ "$status" -eq 0 ]
  grep -qF 'actions/oidc/customization/sub' "$STUB_LOG"
  grep -qF '"include_claim_keys":["repository_owner_id","repository_id","environment"]' "$STUB_LOG"
}

@test "restricts actions to an allowlist with SHA pinning required" {
  run "$REPO_ROOT/scripts/github-setup.sh"
  grep -qF '"sha_pinning_required":true' "$STUB_LOG"
  grep -qF '"patterns_allowed":["hashicorp/setup-terraform@*","microsoft/ps-rule@*"]' "$STUB_LOG"
  grep -qF '"default_workflow_permissions":"read","can_approve_pull_request_reviews":false' "$STUB_LOG"
  grep -qF '"approval_policy":"all_external_contributors"' "$STUB_LOG"
}

@test "prod requires the owner's approval" {
  run "$REPO_ROOT/scripts/github-setup.sh"
  grep -qF '"reviewers":[{"type":"User","id":999}]' "$STUB_LOG"
}

@test "adds the main branch policy only when missing" {
  run "$REPO_ROOT/scripts/github-setup.sh"
  [ "$(grep -c 'deployment-branch-policies -f name=main' "$STUB_LOG")" -eq 2 ]
  : > "$STUB_LOG"
  POLICY_EXISTS=1 run "$REPO_ROOT/scripts/github-setup.sh"
  [ "$(grep -c 'deployment-branch-policies -f name=main' "$STUB_LOG")" -eq 0 ]
}

@test "creates the ruleset when missing and updates it when present" {
  run "$REPO_ROOT/scripts/github-setup.sh"
  grep -qF 'gh api -X POST repos/edward-sf/platform-foundations/rulesets' "$STUB_LOG"
  : > "$STUB_LOG"
  RULESET_ID=42 run "$REPO_ROOT/scripts/github-setup.sh"
  grep -qF 'gh api -X PUT repos/edward-sf/platform-foundations/rulesets/42' "$STUB_LOG"
  ! grep -qF 'gh api -X POST repos/edward-sf/platform-foundations/rulesets' "$STUB_LOG"
}

@test "the ruleset requires a PR and the ci check" {
  source "$REPO_ROOT/scripts/github-setup.sh"
  json=$(ruleset_json)
  jq -e '.rules | map(.type) | index("pull_request") and index("required_status_checks") and index("non_fast_forward") and index("deletion")' <<<"$json"
  jq -e '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks == [{"context":"ci"}]' <<<"$json"
}

@test "turns on secret scanning, push protection, Dependabot alerts and CodeQL for actions" {
  run "$REPO_ROOT/scripts/github-setup.sh"
  grep -qF '"secret_scanning_push_protection":{"status":"enabled"}' "$STUB_LOG"
  grep -qF 'repos/edward-sf/platform-foundations/vulnerability-alerts' "$STUB_LOG"
  grep -qF '"languages":["actions"]' "$STUB_LOG"
}

@test "defers CodeQL until main has workflows, and says so" {
  NO_WORKFLOWS_ON_MAIN=1 run "$REPO_ROOT/scripts/github-setup.sh"
  [ "$status" -eq 0 ]
  ! grep -qF 'code-scanning/default-setup' "$STUB_LOG"
  [[ "$output" == *"re-run make github-setup after the first merge"* ]]
}
