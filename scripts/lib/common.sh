# shellcheck shell=bash
# shellcheck disable=SC2034  # constants are used by the scripts that source this file
# Shared helpers for platform-foundations scripts. Source this file; it sets no shell options.

PF_REPO="edward-sf/platform-foundations"
PF_GH_USER="edward-sf"
PF_RG="rg-pf-bootstrap"
PF_ROLE_NAME="Terraform State Writer (pf)"
PF_LOCK_NAME="pf-state-lock"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

require_env() {
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || die "missing required environment variable: $v"
  done
}

# Refuses to continue unless az is signed in to the expected subscription and tenant.
assert_az_context() {
  require_cmd az jq
  require_env EXPECTED_SUBSCRIPTION_ID EXPECTED_TENANT_ID
  local ctx sub tenant
  ctx=$(az account show -o json 2>/dev/null) || die "not signed in to Azure; run: az login --tenant \"\$EXPECTED_TENANT_ID\""
  sub=$(jq -r '.id // empty' <<<"$ctx")
  tenant=$(jq -r '.tenantId // empty' <<<"$ctx")
  [[ "$sub" == "$EXPECTED_SUBSCRIPTION_ID" ]] || die "signed-in subscription '$sub' does not match EXPECTED_SUBSCRIPTION_ID"
  [[ "$tenant" == "$EXPECTED_TENANT_ID" ]] || die "signed-in tenant '$tenant' does not match EXPECTED_TENANT_ID"
}

# Refuses to continue unless gh is signed in as the repo owner.
assert_gh_user() {
  require_cmd gh
  local who
  who=$(gh api user --jq .login 2>/dev/null) || die "not signed in to GitHub; run: gh auth login"
  [[ "$who" == "$PF_GH_USER" ]] || die "gh is signed in as '$who', expected $PF_GH_USER"
}

# confirm PROMPT: succeeds only on an explicit y or yes.
confirm() {
  local ans=""
  read -r -p "$1 [y/N] " ans || true
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

# az_absent_ok ARGS...: runs az. A "not found" error prints nothing and succeeds;
# any other error (throttling, expired login, bad flag) dies instead of reading as absent.
az_absent_ok() {
  local out err rc=0 msg
  err=$(mktemp)
  out=$(az "$@" 2>"$err") || rc=$?
  if (( rc != 0 )); then
    if grep -qiE 'not ?found|does not exist|could not be found|\(404\)' "$err"; then
      rm -f "$err"
      return 0
    fi
    msg=$(head -c 500 "$err")
    rm -f "$err"
    die "az $* failed: $msg"
  fi
  rm -f "$err"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; fi
  return 0
}

# Prints the bootstrap storage account name, or nothing if it does not exist.
state_account() {
  az_absent_ok storage account list --resource-group "$PF_RG" \
    --query "[?starts_with(name, 'stpf')].name | [0]" -o tsv
}

# Prints the custom role's resource ID from the bootstrap deployment's outputs,
# or nothing if the bootstrap was never deployed. Subscription-scope deployment
# history outlives the resource group, so teardown can still find the role.
role_definition_id() {
  az_absent_ok deployment sub show --name pf-bootstrap \
    --query properties.outputs.roleDefinitionId.value -o tsv
}

# Prints the custom role's ID if it exists (nothing if absent).
find_role_definition_ids() {
  local id
  id=$(role_definition_id) || return 1
  [[ -n "$id" ]] || return 0
  az_absent_ok rest --method get --url "https://management.azure.com${id}?api-version=2022-04-01" --query id -o tsv
}
