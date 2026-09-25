#!/usr/bin/env bash
# Creates and hardens the public GitHub repo. Idempotent; runs with the operator's gh login.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

put_json() { gh api -X PUT "$1" --input - >/dev/null; }

ensure_repo() {
  if ! gh repo view "$PF_REPO" >/dev/null 2>&1; then
    log "creating public repo $PF_REPO"
    gh repo create "$PF_REPO" --public \
      --description "Secret-free platform foundations: Terraform, Bicep, OIDC federation, GitOps" \
      --source . --remote origin
  fi
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$PF_REPO.git"
}

ensure_main_pushed() {
  if ! gh api "repos/$PF_REPO/branches/main" >/dev/null 2>&1; then
    log "pushing main"
    git push origin main:main
  fi
}

configure_actions() {
  log "restricting Actions: allowlist, SHA pinning, read-only token, fork approval"
  put_json "repos/$PF_REPO/actions/permissions" <<<'{"enabled":true,"allowed_actions":"selected","sha_pinning_required":true}'
  put_json "repos/$PF_REPO/actions/permissions/selected-actions" \
    <<<'{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["hashicorp/setup-terraform@*","microsoft/ps-rule@*"]}'
  put_json "repos/$PF_REPO/actions/permissions/workflow" \
    <<<'{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
  put_json "repos/$PF_REPO/actions/permissions/fork-pr-contributor-approval" \
    <<<'{"approval_policy":"all_external_contributors"}'
}

configure_oidc_subject() {
  log "customising the OIDC subject to numeric IDs and the environment"
  put_json "repos/$PF_REPO/actions/oidc/customization/sub" \
    <<<'{"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","environment"]}'
}

ensure_branch_policy() {
  local env=$1
  if ! gh api "repos/$PF_REPO/environments/$env/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main; then
    gh api -X POST "repos/$PF_REPO/environments/$env/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  fi
}

configure_environments() {
  local uid
  uid=$(gh api user --jq .id)
  log "configuring environments dev and prod (main only; prod needs approval)"
  put_json "repos/$PF_REPO/environments/dev" \
    <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
  jq -nc --argjson uid "$uid" \
    '{deployment_branch_policy:{protected_branches:false,custom_branch_policies:true},reviewers:[{type:"User",id:$uid}],prevent_self_review:false}' \
    | put_json "repos/$PF_REPO/environments/prod"
  ensure_branch_policy dev
  ensure_branch_policy prod
}

ruleset_json() {
  cat <<'JSON'
{"name":"main-protection","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[
  {"type":"deletion"},
  {"type":"non_fast_forward"},
  {"type":"required_linear_history"},
  {"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":false}},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}
 ]}
JSON
}

configure_ruleset() {
  local id
  id=$(gh api "repos/$PF_REPO/rulesets" --jq '.[] | select(.name == "main-protection") | .id')
  if [[ -n "$id" ]]; then
    log "updating ruleset main-protection"
    ruleset_json | gh api -X PUT "repos/$PF_REPO/rulesets/$id" --input - >/dev/null
  else
    log "creating ruleset main-protection"
    ruleset_json | gh api -X POST "repos/$PF_REPO/rulesets" --input - >/dev/null
  fi
}

configure_security() {
  log "enabling secret scanning, push protection, Dependabot alerts, CodeQL for actions"
  gh api -X PATCH "repos/$PF_REPO" --input - >/dev/null \
    <<<'{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'
  gh api -X PUT "repos/$PF_REPO/vulnerability-alerts" >/dev/null
  gh api -X PATCH "repos/$PF_REPO/code-scanning/default-setup" --input - >/dev/null \
    <<<'{"state":"configured","languages":["actions"],"query_suite":"default"}'
}

main() {
  set -euo pipefail
  require_cmd gh git jq
  assert_gh_user
  ensure_repo
  ensure_main_pushed
  configure_actions
  configure_oidc_subject
  configure_environments
  configure_ruleset
  configure_security
  log "GitHub setup complete for $PF_REPO"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
