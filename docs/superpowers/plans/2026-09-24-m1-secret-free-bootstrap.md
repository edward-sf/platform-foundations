# M1: Secret-free Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Actions reaches Azure with no stored secrets: Bicep creates the Terraform state backend and one workload identity per environment, a `dev` job runs `terraform init`/`plan` over OIDC, and five lockdown tests prove every other path is refused.

**Architecture:** A subscription-scope Bicep deployment (run once by the operator) creates `rg-pf-bootstrap` with a keyless storage account, two user-assigned managed identities with federated credentials bound to the repo's numeric IDs and a GitHub environment, a narrow custom role scoped per container, and a $2 budget. Bash scripts (tested with bats and stubbed CLIs) drive setup, verification, teardown and the OIDC proofs; two workflows (`ci.yml`, `oidc-proof.yml`) run lint/tests/PSRule and the live proofs.

**Tech Stack:** Bicep 0.47.16, Azure CLI, Terraform 1.16 (azurerm backend + provider ~> 5.7), GitHub Actions, bash (3.2-compatible), bats-core 1.14.0, jq, curl, PSRule for Azure, tflint, actionlint, zizmor, shellcheck, gitleaks, pre-commit.

**Spec:** [docs/superpowers/specs/2026-09-24-m1-secret-free-bootstrap-design.md](../specs/2026-09-24-m1-secret-free-bootstrap-design.md)

## Global Constraints

- Repo: `edward-sf/platform-foundations`, public. Work continues on branch `P0-planning-and-tooling`; it reaches `main` by PR (Task 14).
- Azure names: resource group `rg-pf-bootstrap`; storage account `stpf<uniqueString(subscription().id)>`; containers `tfstate-dev`, `tfstate-prod`; identities `id-pf-dev`, `id-pf-prod`; custom role `Terraform State Writer (pf)`; lock `pf-state-lock`; budget `pf-budget` ($2, monthly).
- Federated credential subject: `repository_owner_id:<owner id>:repository_id:<repo id>:environment:<env>`; issuer `https://token.actions.githubusercontent.com`; audience `api://AzureADTokenExchange`.
- Custom role data actions, exactly: `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read`, `.../blobs/write`, `.../blobs/add/action`. No `actions`.
- Nothing personal or secret is committed. Deploy-time values come from environment variables prefixed `PF_` (`PF_LOCATION`, `PF_BUDGET_EMAIL`, `PF_DEPLOY_BUDGET`, `PF_GITHUB_OWNER_ID`, `PF_GITHUB_REPO_ID`, `PF_BUDGET_START_DATE`). Operator guards use `EXPECTED_SUBSCRIPTION_ID` and `EXPECTED_TENANT_ID`.
- Pinned actions (full SHA, tag in a trailing comment): `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`, `hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e # v4.0.1`, `microsoft/ps-rule@46451b8f5258c41beb5ae69ed7190ccbba84112c # v2.9.0`.
- Terraform: `required_version = ">= 1.16.0, < 1.17.0"`; CI installs `1.16.4`; provider `hashicorp/azurerm ~> 5.7`.
- Runners: `ubuntu-24.04`.
- Scripts run on bash 3.2 (macOS) and bash 5 (Ubuntu): no `mapfile`, no `${var,,}`, no expansion of possibly-empty arrays under `set -u`. Entry scripts call `set -euo pipefail` inside `main`; files under `scripts/lib/` never set shell options.
- No script prints a token. Tokens are captured into variables and passed to `mask` immediately; functions that return tokens never call `mask` inside a command substitution.
- Workflows: `oidc-proof.yml` has `permissions: {}` at the top and each job grants itself `contents: read` and `id-token: write`; `ci.yml` has `contents: read` only. Every `actions/checkout` sets `persist-credentials: false`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A broken or wrong token makes a lockdown test pass vacuously.** Expected: every denial job first proves the same token lists `tfstate-dev` (HTTP 200) and fails before attempting the denial otherwise. Test: Task 4, "a failing positive control fails the job before any denial is attempted".
2. **A token leaks into logs** (claims logging, unexpected-success bodies, error messages). Expected: raw tokens appear only in `::add-mask::` lines; `assert-denied.sh` never prints a body from a 2xx response. Tests: Task 4, "tokens appear only in add-mask lines"; Task 3, "fails on unexpected success and never prints the body".
3. **Re-running the bootstrap changes the budget's start date** and the deployment fails or resets the budget. Expected: an existing budget's start date is reused. Test: Task 7, "reuses the existing budget start date".
4. **Re-running teardown after a partial teardown** (group already gone). Expected: completes, skips what's gone, still verifies. Test: Task 9, "is safe to re-run after everything is gone".
5. **A security property Azure reports as missing (`null`) is read as "off".** Expected: `null` fails the check; only an explicit `false`/`true` passes. Test: Task 8, "a missing property fails instead of passing".

---

## File Structure

| Path | Responsibility |
|---|---|
| `Brewfile` | Local toolchain |
| `Makefile` | Operator entry points |
| `.gitignore`, `.editorconfig` | Repo hygiene |
| `.pre-commit-config.yaml` | Local lint suite (system hooks + gitleaks) |
| `.tflint.hcl` | tflint config |
| `ps-rule.yaml`, `.ps-rule/pf-suppressions.Rule.yaml` | PSRule options and accepted-risk suppressions |
| `.github/workflows/ci.yml` | Lint, tests, PSRule; aggregate `ci` check |
| `.github/workflows/oidc-proof.yml` | Live OIDC proof and lockdown tests |
| `.github/dependabot.yml` | Action SHA updates |
| `infra/bootstrap/main.bicep` | Subscription-scope bootstrap |
| `infra/bootstrap/main.bicepparam` | Params from `PF_*` env vars |
| `infra/bootstrap/bicepconfig.json` | Linter rules as errors |
| `infra/bootstrap/modules/{storage,identity,role,state-access,budget}.bicep` | One resource concern each |
| `infra/azure/envs/dev/{versions,backend,providers}.tf` | Empty dev root with remote backend |
| `scripts/lib/common.sh` | Constants, logging, guards, confirm, shared az lookups |
| `scripts/lib/http.sh` | `http_request` curl wrapper |
| `scripts/lib/token.sh` | GitHub OIDC token, Entra exchange, claims, mask |
| `scripts/assert-denied.sh` | Exact-code denial assertion |
| `scripts/proof.sh` | The six proof cases |
| `scripts/doctor.sh`, `bootstrap.sh`, `verify-bootstrap.sh`, `teardown.sh`, `github-setup.sh` | Operator scripts |
| `scripts/ci/install-tools.sh` | Checksum-verified CI tool installs |
| `tests/helpers.bash`, `tests/*.bats` | bats tests with stubbed CLIs |
| `docs/security/threat-model.md`, `docs/runbooks/*.md`, `docs/evidence/m1/` | Docs and evidence |

---

### Task 1: Tooling foundation and shared shell library

**Files:**
- Create: `Brewfile`, `.gitignore`, `.editorconfig`, `Makefile`, `scripts/lib/common.sh`, `scripts/doctor.sh`, `tests/helpers.bash`, `tests/common.bats`, `tests/doctor.bats`

**Interfaces:**
- Produces (`scripts/lib/common.sh`): constants `PF_REPO`, `PF_GH_USER`, `PF_RG`, `PF_ROLE_NAME`, `PF_LOCK_NAME`; functions `log MSG`, `die MSG` (exit 1), `require_cmd CMD...`, `require_env VAR...`, `assert_az_context`, `assert_gh_user`, `confirm PROMPT` (0 on `y`/`yes`), `state_account` (prints the `stpf*` account name or nothing), `find_role_definition_ids` (prints IDs of the custom role, one per line).
- Produces (`tests/helpers.bash`): `REPO_ROOT`, `setup_stubs`, `stub NAME BODY`, `line_of PATTERN`, env `STUB_LOG`, `STUB_STATE`.

- [ ] **Step 1: Install the toolchain**

Create `Brewfile`:

```ruby
# Local toolchain for platform-foundations. Install with: brew bundle
# Terraform comes from hashicorp/tap (already installed); CI pins 1.16.4.
tap "azure/bicep"
brew "azure-cli"
brew "azure/bicep/bicep"
brew "tflint"
brew "pre-commit"
brew "actionlint"
brew "zizmor"
brew "shellcheck"
brew "gitleaks"
brew "bats-core"
brew "jq"
brew "gh"
```

Run: `brew bundle`
Expected: ends with `Homebrew Bundle complete!`

- [ ] **Step 2: Add repo hygiene files**

`.gitignore`:

```gitignore
.DS_Store
.env
.env.*
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
crash.log
infra/bootstrap/*.json
reports/
```

`.editorconfig`:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[Makefile]
indent_style = tab
```

- [ ] **Step 3: Write the test helpers**

`tests/helpers.bash`:

```bash
# Shared bats helpers. Load with: load helpers
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_ROOT

# Puts a stub directory first on PATH and starts an empty call log.
setup_stubs() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  STUB_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STUB_BIN" "$STUB_STATE"
  : > "$STUB_LOG"
  export PATH="$STUB_BIN:$PATH" STUB_LOG STUB_STATE
}

# stub NAME BODY: creates an executable NAME that appends "NAME args" (and its
# stdin, when called with "--input -") to $STUB_LOG, then runs BODY.
stub() {
  local name=$1 body=$2
  cat > "$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$name" "\$*" >> "\$STUB_LOG"
if [[ " \$* " == *" --input - "* ]]; then cat >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"; fi
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

# line_of PATTERN: first line number in $STUB_LOG containing PATTERN (empty if none).
line_of() { grep -n -m1 -F -- "$1" "$STUB_LOG" | cut -d: -f1; }
```

- [ ] **Step 4: Write the failing tests for `common.sh`**

`tests/common.bats`:

```bash
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
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `bats tests/common.bats`
Expected: FAIL — `common.sh: No such file or directory`.

- [ ] **Step 6: Implement `scripts/lib/common.sh`**

```bash
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

# Prints the bootstrap storage account name, or nothing if it does not exist.
state_account() {
  az storage account list --resource-group "$PF_RG" \
    --query "[?starts_with(name, 'stpf')].name | [0]" -o tsv 2>/dev/null || true
}

# Prints the IDs of the custom state role, one per line (nothing if absent).
find_role_definition_ids() {
  az role definition list --custom-role-only true --name "$PF_ROLE_NAME" --query '[].id' -o tsv 2>/dev/null || true
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bats tests/common.bats`
Expected: `12 tests, 0 failures`

- [ ] **Step 8: Write the failing test for `doctor.sh`**

`tests/doctor.bats`:

```bash
setup() {
  load helpers
  setup_stubs
}

@test "doctor lists a missing tool and fails" {
  local t
  for t in az bicep terraform tflint pre-commit actionlint shellcheck gitleaks bats jq gh; do
    stub "$t" 'echo "stub 1.0"'
  done
  PATH="$STUB_BIN:/usr/bin:/bin" run "$REPO_ROOT/scripts/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING  zizmor"* ]]
  [[ "$output" == *"brew bundle"* ]]
}

@test "doctor passes when every tool is present" {
  local t
  for t in az bicep terraform tflint pre-commit actionlint zizmor shellcheck gitleaks bats jq gh; do
    stub "$t" 'echo "stub 1.0"'
  done
  PATH="$STUB_BIN:/usr/bin:/bin" run "$REPO_ROOT/scripts/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok       zizmor"* ]]
}
```

- [ ] **Step 9: Run it to verify it fails**

Run: `bats tests/doctor.bats`
Expected: FAIL — `doctor.sh` not found (status 127).

- [ ] **Step 10: Implement `scripts/doctor.sh`**

```bash
#!/usr/bin/env bash
# Checks that every tool this repo needs is installed, and prints its version.

TOOLS="az bicep terraform tflint pre-commit actionlint zizmor shellcheck gitleaks bats jq gh"

version_of() {
  case "$1" in
    az) az version --query '"azure-cli"' -o tsv 2>/dev/null ;;
    terraform) terraform version 2>/dev/null | head -1 ;;
    gitleaks) gitleaks version 2>/dev/null ;;
    *) "$1" --version 2>&1 | head -1 ;;
  esac
}

main() {
  set -euo pipefail
  local t missing=""
  for t in $TOOLS; do
    if command -v "$t" >/dev/null 2>&1; then
      printf 'ok       %-11s %s\n' "$t" "$(version_of "$t")"
    else
      printf 'MISSING  %s\n' "$t"
      missing="$missing $t"
    fi
  done
  if [[ -n "$missing" ]]; then
    printf '\nmissing:%s. Install with: brew bundle\n' "$missing"
    exit 1
  fi
}

main "$@"
```

Run: `chmod +x scripts/doctor.sh`

- [ ] **Step 11: Run the doctor tests to verify they pass**

Run: `bats tests/doctor.bats`
Expected: `2 tests, 0 failures`

- [ ] **Step 12: Add the Makefile**

```make
# Operator entry points for platform-foundations. Run `make` for the list.
REPO := edward-sf/platform-foundations

.DEFAULT_GOAL := help
.PHONY: help doctor lint test github-setup bootstrap verify-bootstrap proof teardown

help: ## List targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check the local toolchain
	@scripts/doctor.sh

lint: ## Run the local lint suite (mirrors ci.yml except PSRule)
	pre-commit run --all-files

test: ## Run the bats tests
	bats tests

github-setup: ## Create and harden the GitHub repo (idempotent)
	scripts/github-setup.sh

bootstrap: ## Deploy the Bicep bootstrap (what-if, then confirm)
	scripts/bootstrap.sh

verify-bootstrap: ## Check the deployed bootstrap against the spec
	scripts/verify-bootstrap.sh

proof: ## Run oidc-proof.yml on main and wait for the result
	gh workflow run oidc-proof.yml --repo $(REPO) --ref main
	sleep 5
	gh run watch --repo $(REPO) --exit-status $$(gh run list --repo $(REPO) --workflow oidc-proof.yml --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')

teardown: ## Delete every bootstrap resource and verify it is gone
	scripts/teardown.sh
```

Run: `make` then `make doctor`
Expected: `make` lists nine targets; `make doctor` prints `ok` for every tool and exits 0.

- [ ] **Step 13: Commit**

```bash
git add Brewfile .gitignore .editorconfig Makefile scripts/lib/common.sh scripts/doctor.sh tests/helpers.bash tests/common.bats tests/doctor.bats
git commit -m "Add toolchain, Makefile and shared shell library

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: HTTP and token library

**Files:**
- Create: `scripts/lib/http.sh`, `scripts/lib/token.sh`, `tests/token.bats`

**Interfaces:**
- Consumes: `require_env`, `die` from `scripts/lib/common.sh`.
- Produces (`http.sh`): `http_request METHOD URL BODY_OUT [curl args...]` → prints the HTTP status (`000` on transport failure); body written to `BODY_OUT`.
- Produces (`token.sh`): constants `GH_OIDC_AUDIENCE`, `STORAGE_SCOPE`; `mask VALUE` (prints `::add-mask::VALUE` only when `GITHUB_ACTIONS=true`); `gh_oidc_token` → prints the GitHub JWT; `entra_token_request CLIENT_ID ASSERTION OUT` → prints HTTP status, response JSON in `OUT`; `jwt_claims JWT` → prints compact JSON `{sub,aud,iss,environment,repository_id,repository_owner_id}`.

- [ ] **Step 1: Write the failing tests**

`tests/token.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/token.bats`
Expected: FAIL — `http.sh: No such file or directory`.

- [ ] **Step 3: Implement `scripts/lib/http.sh`**

```bash
# shellcheck shell=bash
# Minimal HTTP helper. Source this file; it sets no shell options.

# http_request METHOD URL BODY_OUT [curl args...]
# Prints the HTTP status code ("000" if no response arrived); writes the body to BODY_OUT.
http_request() {
  local method=$1 url=$2 out=$3 code
  shift 3
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "$@" "$url" 2>/dev/null) || true
  printf '%s\n' "${code:-000}"
}
```

- [ ] **Step 4: Implement `scripts/lib/token.sh`**

```bash
# shellcheck shell=bash
# GitHub OIDC and Entra token helpers. Source after common.sh and http.sh.
# Functions that return tokens print them; callers capture and mask them at once.

GH_OIDC_AUDIENCE="api://AzureADTokenExchange"
STORAGE_SCOPE="https://storage.azure.com/.default"

# mask VALUE: hides VALUE in GitHub Actions logs. No-op elsewhere.
mask() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::add-mask::%s\n' "$1"
  fi
  return 0
}

# Prints this job's GitHub OIDC token (audience api://AzureADTokenExchange).
gh_oidc_token() {
  require_env ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN
  local out code
  out=$(mktemp)
  code=$(http_request GET "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${GH_OIDC_AUDIENCE}" "$out" \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}")
  if [[ "$code" != "200" ]]; then
    rm -f "$out"
    die "GitHub OIDC token request failed (HTTP $code); does the job grant id-token: write?"
  fi
  jq -r '.value' "$out"
  rm -f "$out"
}

# entra_token_request CLIENT_ID ASSERTION OUT
# Exchanges a GitHub token for a storage access token. Prints the HTTP status; JSON goes to OUT.
entra_token_request() {
  require_env AZURE_TENANT_ID
  http_request POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" "$3" \
    --data-urlencode "client_id=$1" \
    --data-urlencode "scope=${STORAGE_SCOPE}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=$2"
}

# jwt_claims JWT: prints the identifying claims of a JWT as compact JSON. Never prints the token.
jwt_claims() {
  local payload
  payload=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  while (( ${#payload} % 4 )); do payload="${payload}="; done
  printf '%s' "$payload" | base64 -d 2>/dev/null \
    | jq -c '{sub, aud, iss, environment, repository_id, repository_owner_id}'
}
```

The stubbed `http_request` in the entra test receives the curl args separately, so each `--data-urlencode` value appears on its own line.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/token.bats`
Expected: `9 tests, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/http.sh scripts/lib/token.sh tests/token.bats
git commit -m "Add HTTP and OIDC token helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Exact-code denial assertion

**Files:**
- Create: `scripts/assert-denied.sh`, `tests/assert-denied.bats`

**Interfaces:**
- Produces: `scripts/assert-denied.sh --status CODE --body-file FILE --expect-error TEXT [--expect-status CODE]`. Exit 0 with `PASS: ...` only when `CODE` is a non-2xx, non-000 status, equals `--expect-status` if given, and `FILE` contains `TEXT`. Exit 1 with `FAIL: ...` otherwise. Exit 2 on usage errors. Never prints the body of a 2xx response.

- [ ] **Step 1: Write the failing tests**

`tests/assert-denied.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/assert-denied.bats`
Expected: FAIL — status 127, script not found.

- [ ] **Step 3: Implement `scripts/assert-denied.sh`**

```bash
#!/usr/bin/env bash
# Passes only when a request was denied with the expected status and error code.
# Usage: assert-denied.sh --status CODE --body-file FILE --expect-error TEXT [--expect-status CODE]

usage() {
  echo "usage: assert-denied.sh --status CODE --body-file FILE --expect-error TEXT [--expect-status CODE]" >&2
  exit 2
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

main() {
  set -euo pipefail
  local status="" body_file="" expect_error="" expect_status=""
  while (( $# )); do
    case "$1" in
      --status) status=${2:-}; shift 2 || usage ;;
      --body-file) body_file=${2:-}; shift 2 || usage ;;
      --expect-error) expect_error=${2:-}; shift 2 || usage ;;
      --expect-status) expect_status=${2:-}; shift 2 || usage ;;
      *) usage ;;
    esac
  done
  [[ -n "$status" && -n "$body_file" && -n "$expect_error" ]] || usage

  [[ "$status" =~ ^[0-9]{3}$ ]] || fail "no HTTP status recorded (got '$status')"
  [[ "$status" != "000" ]] || fail "no response (transport failure)"
  [[ "$status" != 2* ]] || fail "expected a denial, but the request succeeded with HTTP $status"
  if [[ -n "$expect_status" && "$status" != "$expect_status" ]]; then
    fail "expected HTTP $expect_status, got HTTP $status"
  fi
  [[ -f "$body_file" ]] || fail "body file not found: $body_file"
  grep -qF -- "$expect_error" "$body_file" \
    || fail "HTTP $status, but the body lacks '$expect_error': $(head -c 300 "$body_file")"
  printf 'PASS: denied with HTTP %s and %s\n' "$status" "$expect_error"
}

main "$@"
```

Run: `chmod +x scripts/assert-denied.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/assert-denied.bats`
Expected: `8 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/assert-denied.sh tests/assert-denied.bats
git commit -m "Add exact-code denial assertion

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: OIDC proof cases

**Files:**
- Create: `scripts/proof.sh`, `tests/proof.bats`

**Interfaces:**
- Consumes: `common.sh` (`log`, `die`, `require_env`), `http.sh` (`http_request`), `token.sh` (`mask`, `gh_oidc_token`, `entra_token_request`, `jwt_claims`), `scripts/assert-denied.sh`.
- Produces: `scripts/proof.sh <claims|no-environment|cross-identity|cross-env-state|delegation-key|container-delete>`. Reads env `AZURE_TENANT_ID`, `AZURE_CLIENT_ID_DEV`, `AZURE_CLIENT_ID_PROD`, `TF_STATE_ACCOUNT`, and the GitHub `ACTIONS_ID_TOKEN_REQUEST_*` variables. Internal functions (overridable in tests): `storage_request METHOD PATH TOKEN OUT [curl args...]`, `github_token`, `storage_token_for CLIENT_ID`, `dev_session`, `case_*`, `main`.

- [ ] **Step 1: Write the failing tests**

`tests/proof.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/proof.bats`
Expected: FAIL — `proof.sh: No such file or directory`.

- [ ] **Step 3: Implement `scripts/proof.sh`**

```bash
#!/usr/bin/env bash
# Runs one OIDC lockdown proof case. Called by .github/workflows/oidc-proof.yml.
# Usage: scripts/proof.sh <claims|no-environment|cross-identity|cross-env-state|delegation-key|container-delete>
# Never prints a token: each token is masked the moment it is captured.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "$HERE/lib/http.sh"
# shellcheck source=scripts/lib/token.sh
source "$HERE/lib/token.sh"

STORAGE_API_VERSION="2023-11-03"
STORAGE_DENIED="AuthorizationPermissionMismatch"
ENTRA_DENIED="AADSTS700213"
JWT=""
ACCESS_TOKEN=""

# storage_request METHOD PATH TOKEN OUT [curl args...] -> HTTP status
storage_request() {
  local method=$1 path=$2 token=$3 out=$4
  shift 4
  http_request "$method" "https://${TF_STATE_ACCOUNT}.blob.core.windows.net${path}" "$out" \
    -H "Authorization: Bearer ${token}" \
    -H "x-ms-version: ${STORAGE_API_VERSION}" \
    -H "x-ms-date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
    "$@"
}

# iso_utc_in SECONDS: ISO-8601 UTC timestamp SECONDS from now (GNU or BSD date).
iso_utc_in() {
  local t=$(( $(date +%s) + $1 ))
  date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ
}

# Fetches this job's GitHub token into JWT, masks it, and logs its claims.
github_token() {
  JWT=$(gh_oidc_token)
  mask "$JWT"
  log "token claims: $(jwt_claims "$JWT")"
}

# storage_token_for CLIENT_ID: exchanges JWT for a storage token into ACCESS_TOKEN.
# A failed exchange means the proof itself is broken, so the job fails.
storage_token_for() {
  local client_id=$1 out="$WORK/token.json" code
  code=$(entra_token_request "$client_id" "$JWT" "$out")
  if [[ "$code" != "200" ]]; then
    die "positive control failed: token exchange for $client_id returned HTTP $code ($(jq -r '.error_description // "no description"' "$out" 2>/dev/null | head -c 300))"
  fi
  ACCESS_TOKEN=$(jq -r '.access_token' "$out")
  rm -f "$out"
  mask "$ACCESS_TOKEN"
}

# A dev token must list tfstate-dev before any denial counts.
dev_session() {
  require_env AZURE_CLIENT_ID_DEV TF_STATE_ACCOUNT
  github_token
  storage_token_for "$AZURE_CLIENT_ID_DEV"
  local code
  code=$(storage_request GET "/tfstate-dev?restype=container&comp=list" "$ACCESS_TOKEN" "$WORK/control.xml")
  [[ "$code" == "200" ]] || die "positive control failed: listing tfstate-dev returned HTTP $code"
  log "positive control: the dev token listed tfstate-dev (HTTP 200)"
}

assert_denied() { "$HERE/assert-denied.sh" "$@"; }

case_claims() {
  github_token
}

case_no_environment() {
  require_env AZURE_CLIENT_ID_DEV
  github_token
  local code
  code=$(entra_token_request "$AZURE_CLIENT_ID_DEV" "$JWT" "$WORK/deny.json")
  assert_denied --status "$code" --body-file "$WORK/deny.json" --expect-error "$ENTRA_DENIED"
}

case_cross_identity() {
  require_env AZURE_CLIENT_ID_PROD
  dev_session
  local code
  code=$(entra_token_request "$AZURE_CLIENT_ID_PROD" "$JWT" "$WORK/deny.json")
  assert_denied --status "$code" --body-file "$WORK/deny.json" --expect-error "$ENTRA_DENIED"
}

case_cross_env_state() {
  dev_session
  local code
  code=$(storage_request GET "/tfstate-prod?restype=container&comp=list" "$ACCESS_TOKEN" "$WORK/deny.xml")
  assert_denied --status "$code" --body-file "$WORK/deny.xml" --expect-status 403 --expect-error "$STORAGE_DENIED"
}

case_delegation_key() {
  dev_session
  local body code
  body="<?xml version=\"1.0\" encoding=\"utf-8\"?><KeyInfo><Start>$(iso_utc_in 0)</Start><Expiry>$(iso_utc_in 3600)</Expiry></KeyInfo>"
  code=$(storage_request POST "/?restype=service&comp=userdelegationkey" "$ACCESS_TOKEN" "$WORK/deny.xml" \
    -H "Content-Type: application/xml" --data "$body")
  assert_denied --status "$code" --body-file "$WORK/deny.xml" --expect-status 403 --expect-error "$STORAGE_DENIED"
}

case_container_delete() {
  dev_session
  local code
  code=$(storage_request DELETE "/tfstate-dev?restype=container" "$ACCESS_TOKEN" "$WORK/deny.xml")
  assert_denied --status "$code" --body-file "$WORK/deny.xml" --expect-status 403 --expect-error "$STORAGE_DENIED"
}

main() {
  set -euo pipefail
  [[ $# -eq 1 ]] || die "usage: proof.sh <claims|no-environment|cross-identity|cross-env-state|delegation-key|container-delete>"
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  case "$1" in
    claims) case_claims ;;
    no-environment) case_no_environment ;;
    cross-identity) case_cross_identity ;;
    cross-env-state) case_cross_env_state ;;
    delegation-key) case_delegation_key ;;
    container-delete) case_container_delete ;;
    *) die "unknown case: $1" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

Run: `chmod +x scripts/proof.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/proof.bats`
Expected: `11 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/proof.sh tests/proof.bats
git commit -m "Add OIDC lockdown proof cases with positive controls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Bicep bootstrap

**Files:**
- Create: `infra/bootstrap/bicepconfig.json`, `infra/bootstrap/main.bicep`, `infra/bootstrap/main.bicepparam`, `infra/bootstrap/modules/storage.bicep`, `infra/bootstrap/modules/identity.bicep`, `infra/bootstrap/modules/role.bicep`, `infra/bootstrap/modules/state-access.bicep`, `infra/bootstrap/modules/budget.bicep`, `tests/bicep.bats`

**Interfaces:**
- Produces: deployment outputs `tenantId`, `subscriptionId`, `storageAccountName`, `devClientId`, `prodClientId` (each read as `.properties.outputs.<name>.value`). Param file reads `PF_LOCATION`, `PF_GITHUB_OWNER_ID`, `PF_GITHUB_REPO_ID`, `PF_BUDGET_EMAIL`, `PF_BUDGET_START_DATE` (required) and `PF_DEPLOY_BUDGET` (default `true`).
- `modules/state-access.bicep` is an addition to the spec's module list: a container-scoped role assignment must be declared from a resource-group-scoped module. Task 13 records it in the spec changelog.

- [ ] **Step 1: Write the failing tests**

`tests/bicep.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/bicep.bats`
Expected: FAIL in `setup_file` — `main.bicep` does not exist.

- [ ] **Step 3: Add `infra/bootstrap/bicepconfig.json`**

```json
{
  "analyzers": {
    "core": {
      "enabled": true,
      "rules": {
        "outputs-should-not-contain-secrets": { "level": "error" },
        "use-secure-value-for-secure-inputs": { "level": "error" },
        "secure-parameter-default": { "level": "error" },
        "no-hardcoded-location": { "level": "error" },
        "no-unused-params": { "level": "error" },
        "no-unused-vars": { "level": "error" },
        "use-recent-api-versions": { "level": "warning" }
      }
    }
  }
}
```

- [ ] **Step 4: Add `infra/bootstrap/modules/storage.bicep`**

```bicep
// Terraform state storage: Entra-only access, versioned, soft-deleted, delete-locked.

@description('Globally unique storage account name.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Blob containers to create, one per environment.')
param containerNames array

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [
  for containerName in containerNames: {
    parent: blobService
    name: containerName
    properties: {
      publicAccess: 'None'
    }
  }
]

resource deleteLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'pf-state-lock'
  scope: account
  properties: {
    level: 'CanNotDelete'
    notes: 'Protects Terraform state. Remove only through scripts/teardown.sh.'
  }
}

output name string = account.name
```

- [ ] **Step 5: Add `infra/bootstrap/modules/identity.bicep`**

```bicep
// A user-assigned managed identity trusted by exactly one GitHub OIDC subject.

@description('Identity name, e.g. id-pf-dev.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Federated credential name.')
param credentialName string

@description('Exact GitHub OIDC subject this identity trusts.')
param subject string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

resource credential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: identity
  name: credentialName
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: subject
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
```

- [ ] **Step 6: Add `infra/bootstrap/modules/role.bicep`**

```bicep
// Custom role: read and write Terraform state blobs, nothing more.

@description('Role name shown in the portal; teardown deletes it by this name.')
param roleName string = 'Terraform State Writer (pf)'

resource role 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'pf-terraform-state-writer')
  properties: {
    roleName: roleName
    description: 'Read and write Terraform state blobs. No blob delete, no container management, no user-delegation keys.'
    type: 'customRole'
    permissions: [
      {
        actions: []
        notActions: []
        dataActions: [
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'
        ]
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

output roleDefinitionId string = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.name)
```

- [ ] **Step 7: Add `infra/bootstrap/modules/state-access.bicep`**

```bicep
// Grants one identity the state role on one container, and nowhere else.

@description('Storage account holding the container.')
param storageAccountName string

@description('Container to grant access to.')
param containerName string

@description('Principal ID of the identity.')
param principalId string

@description('Subscription-level resource ID of the role definition.')
param roleDefinitionId string

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: account
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: blobService
  name: containerName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, principalId, roleDefinitionId)
  scope: container
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
```

- [ ] **Step 8: Add `infra/bootstrap/modules/budget.bicep`**

```bicep
// Monthly cost budget with email alerts for the flagship threshold.
targetScope = 'subscription'

@description('Monthly budget in the billing currency.')
param amount int

@description('First day of the budget period, e.g. 2026-09-01T00:00:00Z.')
param startDate string

@description('Alert recipients.')
param contactEmails array

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'pf-budget'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      actual50: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      actual100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      forecast100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
      }
    }
  }
}
```

- [ ] **Step 9: Add `infra/bootstrap/main.bicep`**

```bicep
// Secret-free bootstrap: Terraform state storage, one workload identity per
// environment, a narrow custom role, and a budget. Run once by the operator.
targetScope = 'subscription'

@description('Azure region for all resources.')
param location string

@description('Numeric GitHub owner ID (gh api repos/edward-sf/platform-foundations --jq .owner.id).')
param githubOwnerId string

@description('Numeric GitHub repository ID (gh api repos/edward-sf/platform-foundations --jq .id).')
param githubRepoId string

@description('Budget alert email. Supplied at deploy time; never committed.')
param budgetEmail string

@description('Deploy the budget (false if the subscription offer rejects budgets).')
param deployBudget bool = true

@description('Budget start date; reused from an existing budget on redeploy.')
param budgetStartDate string

@description('Monthly budget amount.')
param budgetAmount int = 2

var tags = {
  project: 'platform-foundations'
  'managed-by': 'bicep'
  env: 'shared'
}
var environments = [
  'dev'
  'prod'
]

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-pf-bootstrap'
  location: location
  tags: tags
}

module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'pf-storage'
  params: {
    name: 'stpf${uniqueString(subscription().id)}'
    location: location
    tags: tags
    containerNames: [for env in environments: 'tfstate-${env}']
  }
}

module role 'modules/role.bicep' = {
  scope: rg
  name: 'pf-role'
}

module identities 'modules/identity.bicep' = [
  for env in environments: {
    scope: rg
    name: 'pf-identity-${env}'
    params: {
      name: 'id-pf-${env}'
      location: location
      tags: tags
      credentialName: 'github-${env}'
      subject: 'repository_owner_id:${githubOwnerId}:repository_id:${githubRepoId}:environment:${env}'
    }
  }
]

module stateAccess 'modules/state-access.bicep' = [
  for (env, i) in environments: {
    scope: rg
    name: 'pf-state-access-${env}'
    params: {
      storageAccountName: storage.outputs.name
      containerName: 'tfstate-${env}'
      principalId: identities[i].outputs.principalId
      roleDefinitionId: role.outputs.roleDefinitionId
    }
  }
]

module budget 'modules/budget.bicep' = if (deployBudget) {
  name: 'pf-budget'
  params: {
    amount: budgetAmount
    startDate: budgetStartDate
    contactEmails: [
      budgetEmail
    ]
  }
}

output tenantId string = tenant().tenantId
output subscriptionId string = subscription().subscriptionId
output storageAccountName string = storage.outputs.name
output devClientId string = identities[0].outputs.clientId
output prodClientId string = identities[1].outputs.clientId
```

- [ ] **Step 10: Add `infra/bootstrap/main.bicepparam`**

```bicep
using './main.bicep'

// Every value comes from the environment so nothing personal is committed.
// scripts/bootstrap.sh sets the PF_GITHUB_* and PF_BUDGET_START_DATE values.
param location = readEnvironmentVariable('PF_LOCATION')
param githubOwnerId = readEnvironmentVariable('PF_GITHUB_OWNER_ID')
param githubRepoId = readEnvironmentVariable('PF_GITHUB_REPO_ID')
param budgetEmail = readEnvironmentVariable('PF_BUDGET_EMAIL')
param budgetStartDate = readEnvironmentVariable('PF_BUDGET_START_DATE')
param deployBudget = bool(readEnvironmentVariable('PF_DEPLOY_BUDGET', 'true'))
```

- [ ] **Step 11: Lint, then run the tests**

Run: `bicep lint infra/bootstrap/main.bicep && bats tests/bicep.bats`
Expected: lint prints no errors (warnings allowed only for `use-recent-api-versions`); `9 tests, 0 failures`.

If `bicep lint` reports an error, fix the template rather than lowering the rule's level.

- [ ] **Step 12: Commit**

```bash
git add infra/bootstrap tests/bicep.bats
git commit -m "Add Bicep bootstrap: keyless state storage, federated identities, narrow role, budget

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Terraform dev root

**Files:**
- Create: `infra/azure/envs/dev/versions.tf`, `infra/azure/envs/dev/backend.tf`, `infra/azure/envs/dev/providers.tf`, `infra/azure/envs/dev/.terraform.lock.hcl` (generated), `.tflint.hcl`, `tests/terraform.bats`

**Interfaces:**
- Produces: a root that `terraform init -backend-config="storage_account_name=<account>"` connects to `tfstate-dev/dev.tfstate` over OIDC with Entra auth, using env `ARM_USE_OIDC`, `ARM_USE_AZUREAD`, `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID`.

- [ ] **Step 1: Write the failing test**

`tests/terraform.bats`:

```bash
setup() {
  load helpers
  BACKEND="$REPO_ROOT/infra/azure/envs/dev/backend.tf"
  PROVIDERS="$REPO_ROOT/infra/azure/envs/dev/providers.tf"
}

@test "backend authenticates with OIDC and Entra, never with keys or SAS" {
  grep -Eq '^\s*use_oidc\s*=\s*true' "$BACKEND"
  grep -Eq '^\s*use_azuread_auth\s*=\s*true' "$BACKEND"
  grep -Eq '^\s*container_name\s*=\s*"tfstate-dev"' "$BACKEND"
  ! grep -Eq 'access_key|sas_token|client_secret' "$BACKEND"
}

@test "provider never registers resource providers (the identity has no ARM rights in M1)" {
  grep -Eq '^\s*resource_provider_registrations\s*=\s*"none"' "$PROVIDERS"
}

@test "the lock file covers Linux CI and macOS" {
  lock="$REPO_ROOT/infra/azure/envs/dev/.terraform.lock.hcl"
  grep -q 'registry.terraform.io/hashicorp/azurerm' "$lock"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats tests/terraform.bats`
Expected: FAIL — `backend.tf` not found.

- [ ] **Step 3: Write the Terraform files**

`infra/azure/envs/dev/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.16.0, < 1.17.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
  }
}
```

`infra/azure/envs/dev/backend.tf`:

```hcl
# Remote state in the bootstrap storage account. Auth is OIDC exchanged for an
# Entra token; the account has shared keys disabled, so no key path exists.
# storage_account_name is supplied at init: -backend-config="storage_account_name=..."
terraform {
  backend "azurerm" {
    container_name   = "tfstate-dev"
    key              = "dev.tfstate"
    use_oidc         = true
    use_azuread_auth = true
  }
}
```

`infra/azure/envs/dev/providers.tf`:

```hcl
# M1 manages no resources; M2 adds them. The dev identity has no control-plane
# rights yet, so the provider must not try to register resource providers.
provider "azurerm" {
  features {}
  use_oidc                        = true
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}
```

`.tflint.hcl`:

```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
```

- [ ] **Step 4: Generate the lock file and validate**

Run:

```bash
terraform -chdir=infra/azure/envs/dev init -backend=false -input=false
terraform -chdir=infra/azure/envs/dev providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
terraform fmt -check -recursive infra
terraform -chdir=infra/azure/envs/dev validate
tflint --recursive --config "$PWD/.tflint.hcl"
```

Expected: `Success! The configuration is valid.`; `fmt` and `tflint` print nothing and exit 0.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/terraform.bats`
Expected: `3 tests, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add infra/azure/envs/dev/versions.tf infra/azure/envs/dev/backend.tf infra/azure/envs/dev/providers.tf infra/azure/envs/dev/.terraform.lock.hcl .tflint.hcl tests/terraform.bats
git commit -m "Add Terraform dev root with OIDC and Entra-auth backend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Bootstrap operator script

**Files:**
- Create: `scripts/bootstrap.sh`, `tests/bootstrap.bats`

**Interfaces:**
- Consumes: `common.sh` (`assert_az_context`, `assert_gh_user`, `confirm`, `require_env`, `PF_REPO`); `infra/bootstrap/main.bicepparam` and its outputs from Task 5.
- Produces: `scripts/bootstrap.sh` (via `make bootstrap`); functions `budget_start_date`, `set_github_variables OUTPUTS_JSON`. Writes repo variables `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_DEV`, `AZURE_CLIENT_ID_PROD`, `TF_STATE_ACCOUNT`.

- [ ] **Step 1: Write the failing tests**

`tests/bootstrap.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/bootstrap.bats`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement `scripts/bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Deploys the Bicep bootstrap and writes its outputs to GitHub repo variables.
# Run once, as subscription Owner, from the operator's laptop.
# Required env: EXPECTED_SUBSCRIPTION_ID, EXPECTED_TENANT_ID, PF_LOCATION, PF_BUDGET_EMAIL
# Optional env: PF_DEPLOY_BUDGET (default true; set false if the offer rejects budgets)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

PARAMS_FILE="$HERE/../infra/bootstrap/main.bicepparam"
DEPLOYMENT_NAME="pf-bootstrap"

# Keeps an existing budget's start date so redeploys don't try to move it.
budget_start_date() {
  local existing
  existing=$(az consumption budget show --budget-name pf-budget --query timePeriod.startDate -o tsv 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    printf '%s\n' "$existing"
  else
    date -u +%Y-%m-01T00:00:00Z
  fi
}

# set_github_variables OUTPUTS_JSON: writes deployment outputs to repo variables.
set_github_variables() {
  local outputs=$1 pair name key value
  for pair in AZURE_TENANT_ID:tenantId AZURE_SUBSCRIPTION_ID:subscriptionId \
      AZURE_CLIENT_ID_DEV:devClientId AZURE_CLIENT_ID_PROD:prodClientId TF_STATE_ACCOUNT:storageAccountName; do
    name=${pair%%:*}
    key=${pair#*:}
    value=$(jq -r --arg k "$key" '.[$k].value // empty' <<<"$outputs")
    [[ -n "$value" ]] || die "missing deployment output: $key"
    gh variable set "$name" --repo "$PF_REPO" --body "$value"
  done
}

main() {
  set -euo pipefail
  require_cmd az gh jq
  require_env PF_LOCATION PF_BUDGET_EMAIL
  assert_az_context
  assert_gh_user

  PF_GITHUB_OWNER_ID=$(gh api "repos/$PF_REPO" --jq .owner.id)
  PF_GITHUB_REPO_ID=$(gh api "repos/$PF_REPO" --jq .id)
  PF_DEPLOY_BUDGET=${PF_DEPLOY_BUDGET:-true}
  PF_BUDGET_START_DATE=$(budget_start_date)
  export PF_GITHUB_OWNER_ID PF_GITHUB_REPO_ID PF_DEPLOY_BUDGET PF_BUDGET_START_DATE

  local ns
  for ns in Microsoft.Storage Microsoft.ManagedIdentity; do
    log "registering resource provider $ns"
    az provider register --namespace "$ns" --wait
  done

  local args=(--name "$DEPLOYMENT_NAME" --location "$PF_LOCATION" --parameters "$PARAMS_FILE")
  log "what-if against subscription $EXPECTED_SUBSCRIPTION_ID"
  az deployment sub what-if "${args[@]}"
  confirm "Deploy these changes?" || die "aborted; nothing deployed"

  local outputs
  outputs=$(az deployment sub create "${args[@]}" --query properties.outputs -o json)
  set_github_variables "$outputs"
  log "bootstrap deployed. Next: make verify-bootstrap"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

Run: `chmod +x scripts/bootstrap.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/bootstrap.bats`
Expected: `7 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/bootstrap.sh tests/bootstrap.bats
git commit -m "Add guarded bootstrap script with what-if and confirmation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Post-deploy verification

**Files:**
- Create: `scripts/verify-bootstrap.sh`, `tests/verify-bootstrap.bats`

**Interfaces:**
- Consumes: `common.sh` (`assert_az_context`, `assert_gh_user`, `state_account`, `find_role_definition_ids`, `PF_RG`, `PF_REPO`, `PF_ROLE_NAME`).
- Produces: `scripts/verify-bootstrap.sh`; pure check functions (each prints `ok: DESC` or `FAIL: DESC`, returns 1 on failure): `check_storage JSON`, `check_blob_service JSON`, `check_lock JSON`, `check_role_assignments JSON ENV`, `check_federated_credentials JSON SUBJECT`, `check_role_definition IDS`; `expected_subject OWNER_ID REPO_ID ENV`.

- [ ] **Step 1: Write the failing tests**

`tests/verify-bootstrap.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/verify-bootstrap.bats`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement `scripts/verify-bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Checks the deployed bootstrap against the M1 spec. Exits 1 if any check fails.
# Required env: EXPECTED_SUBSCRIPTION_ID, EXPECTED_TENANT_ID

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

# check DESC FILTER JSON [jq args...]: FILTER must evaluate to true.
check() {
  local desc=$1 filter=$2 json=$3
  shift 3
  if jq -e "$@" "$filter" >/dev/null 2>&1 <<<"$json"; then
    printf 'ok: %s\n' "$desc"
  else
    printf 'FAIL: %s\n' "$desc"
    return 1
  fi
}

check_storage() {
  local j=$1 rc=0
  check "shared-key access disabled" '.allowSharedKeyAccess == false' "$j" || rc=1
  check "Entra auth is the default" '.defaultToOAuthAuthentication == true' "$j" || rc=1
  check "cross-tenant replication disabled" '.allowCrossTenantReplication == false' "$j" || rc=1
  check "anonymous blob access disabled" '.allowBlobPublicAccess == false' "$j" || rc=1
  check "minimum TLS 1.2" '.minimumTlsVersion == "TLS1_2"' "$j" || rc=1
  check "HTTPS only" '.enableHttpsTrafficOnly == true' "$j" || rc=1
  return "$rc"
}

check_blob_service() {
  local j=$1 rc=0
  check "blob versioning on" '.isVersioningEnabled == true' "$j" || rc=1
  check "blob soft delete, 7 days" '.deleteRetentionPolicy.enabled == true and .deleteRetentionPolicy.days == 7' "$j" || rc=1
  check "container soft delete, 7 days" '.containerDeleteRetentionPolicy.enabled == true and .containerDeleteRetentionPolicy.days == 7' "$j" || rc=1
  return "$rc"
}

check_lock() {
  check "CanNotDelete lock on the state account" 'any(.[]; .level == "CanNotDelete")' "$1"
}

# check_role_assignments JSON ENV: exactly one assignment, on tfstate-ENV, with the custom role.
check_role_assignments() {
  check "id-pf-$2 holds only the state role on tfstate-$2" \
    'length == 1 and (.[0].scope | endswith("/blobServices/default/containers/tfstate-" + $env)) and .[0].roleDefinitionName == $role' \
    "$1" --arg env "$2" --arg role "$PF_ROLE_NAME"
}

# check_federated_credentials JSON SUBJECT: exactly one credential, trusting SUBJECT only.
check_federated_credentials() {
  check "federated credential trusts only $2" \
    'length == 1 and .[0].subject == $s and .[0].issuer == "https://token.actions.githubusercontent.com" and .[0].audiences == ["api://AzureADTokenExchange"]' \
    "$1" --arg s "$2"
}

# check_role_definition IDS: the custom role is visible to the same lookup teardown uses.
check_role_definition() {
  if [[ -n "$1" ]]; then
    printf 'ok: custom role %s exists\n' "$PF_ROLE_NAME"
  else
    printf 'FAIL: custom role %s exists\n' "$PF_ROLE_NAME"
    return 1
  fi
}

expected_subject() { printf 'repository_owner_id:%s:repository_id:%s:environment:%s\n' "$1" "$2" "$3"; }

main() {
  set -euo pipefail
  require_cmd az gh jq
  assert_az_context
  assert_gh_user

  local owner_id repo_id acct env pid rc=0
  owner_id=$(gh api "repos/$PF_REPO" --jq .owner.id)
  repo_id=$(gh api "repos/$PF_REPO" --jq .id)
  acct=$(state_account)
  [[ -n "$acct" ]] || die "no stpf* storage account in $PF_RG; run make bootstrap first"

  check_storage "$(az storage account show --name "$acct" --resource-group "$PF_RG" -o json)" || rc=1
  check_blob_service "$(az storage account blob-service-properties show --account-name "$acct" --resource-group "$PF_RG" -o json)" || rc=1
  check_lock "$(az lock list --resource-group "$PF_RG" --resource-name "$acct" --resource-type Microsoft.Storage/storageAccounts -o json)" || rc=1
  check_role_definition "$(find_role_definition_ids)" || rc=1
  for env in dev prod; do
    pid=$(az identity show --name "id-pf-$env" --resource-group "$PF_RG" --query principalId -o tsv)
    check_role_assignments "$(az role assignment list --assignee "$pid" --all -o json)" "$env" || rc=1
    check_federated_credentials "$(az identity federated-credential list --identity-name "id-pf-$env" --resource-group "$PF_RG" -o json)" \
      "$(expected_subject "$owner_id" "$repo_id" "$env")" || rc=1
  done

  if (( rc == 0 )); then
    log "bootstrap verified"
  else
    die "bootstrap verification failed"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

Run: `chmod +x scripts/verify-bootstrap.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/verify-bootstrap.bats`
Expected: `11 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-bootstrap.sh tests/verify-bootstrap.bats
git commit -m "Add post-deploy verification of the bootstrap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Teardown

**Files:**
- Create: `scripts/teardown.sh`, `tests/teardown.bats`

**Interfaces:**
- Consumes: `common.sh` (`assert_az_context`, `confirm`, `state_account`, `find_role_definition_ids`, `PF_RG`, `PF_ROLE_NAME`, `PF_LOCK_NAME`).
- Produces: `scripts/teardown.sh`. Order: lock → role assignments → role definition → resource group → budget → verification. Adds the custom role definition and its assignments to teardown, which the brief's cost sheet lacks; Task 13 records this for the checkpoint.

- [ ] **Step 1: Write the failing tests**

`tests/teardown.bats`:

```bash
setup() {
  load helpers
  setup_stubs
  export EXPECTED_SUBSCRIPTION_ID=sub-1 EXPECTED_TENANT_ID=ten-1
  stub az '
case "$*" in
  "account show"*) echo "{\"id\":\"sub-1\",\"tenantId\":\"ten-1\"}" ;;
  "group exists"*) if [[ -f "$STUB_STATE/group-deleted" ]]; then echo false; else echo true; fi ;;
  "storage account list"*) if [[ ! -f "$STUB_STATE/group-deleted" ]]; then echo stpfabc; fi ;;
  "identity show"*) echo pid-1 ;;
  "role assignment list"*) echo /ra/1 ;;
  "role definition list"*) if [[ ! -f "$STUB_STATE/role-deleted" ]]; then echo /rd/1; fi ;;
  "role definition delete"*) touch "$STUB_STATE/role-deleted" ;;
  "group delete"*) if [[ -z "${GROUP_DELETE_NOOP:-}" ]]; then touch "$STUB_STATE/group-deleted"; fi ;;
  "consumption budget show"*) if [[ -f "$STUB_STATE/budget-deleted" ]]; then exit 1; else echo "{}"; fi ;;
  "consumption budget delete"*) touch "$STUB_STATE/budget-deleted" ;;
esac'
}

run_teardown() { run bash -c "printf '%s\n' '$1' | '$REPO_ROOT/scripts/teardown.sh'"; }

@test "deletes lock, assignments, role, group, then budget, in that order" {
  run_teardown y
  [ "$status" -eq 0 ]
  [ "$(line_of 'az lock delete')" -lt "$(line_of 'az role assignment delete')" ]
  [ "$(line_of 'az role assignment delete')" -lt "$(line_of 'az role definition delete')" ]
  [ "$(line_of 'az role definition delete')" -lt "$(line_of 'az group delete')" ]
  [ "$(line_of 'az group delete')" -lt "$(line_of 'az consumption budget delete')" ]
  [[ "$output" == *"teardown verified"* ]]
}

@test "answering no deletes nothing" {
  run_teardown n
  [ "$status" -eq 1 ]
  ! grep -q ' delete' "$STUB_LOG"
}

@test "refuses to run against another subscription" {
  export EXPECTED_SUBSCRIPTION_ID=other-sub
  run_teardown y
  [ "$status" -eq 1 ]
  ! grep -q ' delete' "$STUB_LOG"
}

@test "is safe to re-run after everything is gone" {
  touch "$STUB_STATE/group-deleted" "$STUB_STATE/role-deleted" "$STUB_STATE/budget-deleted"
  run_teardown y
  [ "$status" -eq 0 ]
  [ -z "$(line_of 'az group delete')" ]
  [[ "$output" == *"teardown verified"* ]]
}

@test "fails when the group survives deletion" {
  export GROUP_DELETE_NOOP=1
  run_teardown y
  [ "$status" -eq 1 ]
  [[ "$output" == *"teardown incomplete"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/teardown.bats`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement `scripts/teardown.sh`**

```bash
#!/usr/bin/env bash
# Deletes every bootstrap resource and verifies each one is gone. Safe to re-run.
# Required env: EXPECTED_SUBSCRIPTION_ID, EXPECTED_TENANT_ID

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

delete_lock() {
  local acct
  acct=$(state_account)
  [[ -n "$acct" ]] || return 0
  log "deleting lock $PF_LOCK_NAME"
  az lock delete --name "$PF_LOCK_NAME" --resource-group "$PF_RG" \
    --resource-name "$acct" --resource-type Microsoft.Storage/storageAccounts || log "lock already gone"
}

delete_role_assignments() {
  local env pid ids id
  for env in dev prod; do
    pid=$(az identity show --name "id-pf-$env" --resource-group "$PF_RG" --query principalId -o tsv 2>/dev/null || true)
    [[ -n "$pid" ]] || continue
    ids=$(az role assignment list --assignee "$pid" --all --query '[].id' -o tsv)
    for id in $ids; do
      log "deleting role assignment $id"
      az role assignment delete --ids "$id"
    done
  done
}

delete_role_definition() {
  [[ -n "$(find_role_definition_ids)" ]] || return 0
  log "deleting custom role $PF_ROLE_NAME"
  az role definition delete --name "$PF_ROLE_NAME" --custom-role-only true \
    --scope "/subscriptions/$EXPECTED_SUBSCRIPTION_ID/resourceGroups/$PF_RG"
}

delete_budget() {
  if az consumption budget show --budget-name pf-budget >/dev/null 2>&1; then
    log "deleting budget pf-budget"
    az consumption budget delete --budget-name pf-budget
  fi
}

verify_gone() {
  local rc=0
  if [[ "$(az group exists --name "$PF_RG")" == "false" ]]; then log "ok: $PF_RG gone"; else log "FAIL: $PF_RG still exists"; rc=1; fi
  if [[ -z "$(find_role_definition_ids)" ]]; then log "ok: custom role gone"; else log "FAIL: custom role still exists"; rc=1; fi
  if ! az consumption budget show --budget-name pf-budget >/dev/null 2>&1; then log "ok: pf-budget gone"; else log "FAIL: pf-budget still exists"; rc=1; fi
  (( rc == 0 )) || die "teardown incomplete; see FAIL lines above"
  log "teardown verified"
}

main() {
  set -euo pipefail
  require_cmd az jq
  assert_az_context
  confirm "Delete every platform-foundations bootstrap resource in subscription $EXPECTED_SUBSCRIPTION_ID? Terraform state will be lost." \
    || die "aborted; nothing deleted"

  if [[ "$(az group exists --name "$PF_RG")" == "true" ]]; then
    delete_lock
    delete_role_assignments
    delete_role_definition
    log "deleting resource group $PF_RG (takes a few minutes)"
    az group delete --name "$PF_RG" --yes
  else
    log "resource group $PF_RG already gone"
    delete_role_definition
  fi
  delete_budget
  verify_gone
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

Run: `chmod +x scripts/teardown.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/teardown.bats`
Expected: `5 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/teardown.sh tests/teardown.bats
git commit -m "Add ordered, verified, re-runnable teardown

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: GitHub repo setup

**Files:**
- Create: `scripts/github-setup.sh`, `tests/github-setup.bats`

**Interfaces:**
- Consumes: `common.sh` (`assert_gh_user`, `log`, `require_cmd`, `PF_REPO`).
- Produces: `scripts/github-setup.sh` (via `make github-setup`); functions `ensure_repo`, `ensure_main_pushed`, `configure_actions`, `configure_oidc_subject`, `configure_environments`, `ensure_branch_policy ENV`, `configure_ruleset`, `ruleset_json`, `configure_security`. The ruleset requires a status check named `ci` (Task 11's aggregate job).

- [ ] **Step 1: Write the failing tests**

`tests/github-setup.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/github-setup.bats`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement `scripts/github-setup.sh`**

```bash
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
```

Run: `chmod +x scripts/github-setup.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/github-setup.bats`
Expected: `8 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add scripts/github-setup.sh tests/github-setup.bats
git commit -m "Add idempotent GitHub repo hardening script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: CI pipeline, PSRule, Dependabot and pre-commit

**Files:**
- Create: `scripts/ci/install-tools.sh`, `.github/workflows/ci.yml`, `ps-rule.yaml`, `.ps-rule/pf-suppressions.Rule.yaml`, `.github/dependabot.yml`, `.pre-commit-config.yaml`

**Interfaces:**
- Consumes: all scripts and tests from Tasks 1–10; `.tflint.hcl`; `infra/bootstrap/main.bicepparam`.
- Produces: `scripts/ci/install-tools.sh TOOL...` (installs into `$RUNNER_TEMP/pf/bin` and appends it to `$GITHUB_PATH`); a workflow whose aggregate job is named `ci` (the required check from Task 10).

- [ ] **Step 1: Write `scripts/ci/install-tools.sh`**

```bash
#!/usr/bin/env bash
# Installs pinned CI tools into $RUNNER_TEMP/pf/bin, verifying each download's SHA-256.
# Usage: scripts/ci/install-tools.sh TOOL...   (tflint actionlint zizmor shellcheck bats bicep)

PREFIX="${RUNNER_TEMP:-/tmp}/pf"
BIN="$PREFIX/bin"

fetch() {
  local url=$1 sha=$2 out=$3
  curl -fsSL -o "$out" "$url"
  echo "$sha  $out" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $url" >&2; exit 1; }
}

install_one() {
  local tmp
  tmp=$(mktemp -d)
  case "$1" in
    tflint)
      fetch https://github.com/terraform-linters/tflint/releases/download/v0.64.0/tflint_linux_amd64.zip \
        cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537 "$tmp/tflint.zip"
      unzip -q -o "$tmp/tflint.zip" -d "$BIN" ;;
    actionlint)
      fetch https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz \
        8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 "$tmp/actionlint.tgz"
      tar -xzf "$tmp/actionlint.tgz" -C "$BIN" actionlint ;;
    zizmor)
      fetch https://github.com/zizmorcore/zizmor/releases/download/v1.30.1/zizmor-x86_64-unknown-linux-gnu.tar.gz \
        e65324f4430c2717591937edcec90ccbefaf14c174f8ec9415e03ca875b46e1a "$tmp/zizmor.tgz"
      tar -xzf "$tmp/zizmor.tgz" -C "$BIN" zizmor ;;
    shellcheck)
      fetch https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz \
        8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 "$tmp/shellcheck.txz"
      tar -xJf "$tmp/shellcheck.txz" -C "$tmp"
      mv "$tmp/shellcheck-v0.11.0/shellcheck" "$BIN/" ;;
    bats)
      fetch https://github.com/bats-core/bats-core/archive/refs/tags/v1.14.0.tar.gz \
        bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177 "$tmp/bats.tgz"
      tar -xzf "$tmp/bats.tgz" -C "$tmp"
      "$tmp/bats-core-1.14.0/install.sh" "$PREFIX" >/dev/null ;;
    bicep)
      fetch https://github.com/Azure/bicep/releases/download/v0.47.16/bicep-linux-x64 \
        64c345a58e0c3e48b1bc98a4e62d6b3adb1d238281297de3400aeafb2697aa5a "$BIN/bicep"
      chmod +x "$BIN/bicep" ;;
    *)
      echo "unknown tool: $1" >&2
      exit 2 ;;
  esac
  rm -rf "$tmp"
}

main() {
  set -euo pipefail
  mkdir -p "$BIN"
  local t
  for t in "$@"; do
    install_one "$t"
  done
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$BIN" >> "$GITHUB_PATH"
  fi
}

main "$@"
```

Run: `chmod +x scripts/ci/install-tools.sh`

- [ ] **Step 2: Write `.github/workflows/ci.yml`**

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  terraform:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e # v4.0.1
        with:
          terraform_version: 1.16.4
          terraform_wrapper: false
      - run: scripts/ci/install-tools.sh tflint
      - run: terraform fmt -check -recursive infra
      - run: terraform -chdir=infra/azure/envs/dev init -backend=false -input=false
      - run: terraform -chdir=infra/azure/envs/dev validate
      - run: tflint --recursive --config "$GITHUB_WORKSPACE/.tflint.hcl"

  bicep:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: scripts/ci/install-tools.sh bicep
      - run: bicep lint infra/bootstrap/main.bicep
      - run: bicep build infra/bootstrap/main.bicep --stdout > /dev/null

  workflows:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: scripts/ci/install-tools.sh actionlint zizmor
      - run: actionlint
      - run: zizmor --offline .github/workflows

  shell:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: scripts/ci/install-tools.sh shellcheck bats bicep
      - run: shellcheck -x scripts/*.sh scripts/lib/*.sh scripts/ci/*.sh tests/helpers.bash
      - run: bats tests

  psrule:
    runs-on: ubuntu-24.04
    env:
      PF_LOCATION: eastus2
      PF_GITHUB_OWNER_ID: "0"
      PF_GITHUB_REPO_ID: "0"
      PF_BUDGET_EMAIL: ci@example.invalid
      PF_BUDGET_START_DATE: "2026-01-01T00:00:00Z"
      PF_DEPLOY_BUDGET: "true"
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: scripts/ci/install-tools.sh bicep
      - uses: microsoft/ps-rule@46451b8f5258c41beb5ae69ed7190ccbba84112c # v2.9.0
        env:
          PSRULE_AZURE_BICEP_PATH: ${{ runner.temp }}/pf/bin/bicep
        with:
          modules: PSRule.Rules.Azure
          option: ps-rule.yaml

  ci:
    if: always()
    needs: [terraform, bicep, workflows, shell, psrule]
    runs-on: ubuntu-24.04
    steps:
      - name: All checks passed
        env:
          RESULTS: ${{ join(needs.*.result, ' ') }}
        run: |
          echo "job results: $RESULTS"
          for r in $RESULTS; do
            [[ "$r" == "success" ]] || exit 1
          done
```

- [ ] **Step 3: Write the PSRule configuration**

`ps-rule.yaml`:

```yaml
# PSRule for Azure checks the expanded Bicep bootstrap in CI (ci.yml, job psrule).
# Accepted risks are suppressed in .ps-rule/pf-suppressions.Rule.yaml, each linked to the threat model.
requires:
  PSRule.Rules.Azure: '>=1.47.0'

include:
  module:
    - PSRule.Rules.Azure

configuration:
  AZURE_BICEP_PARAMS_FILE_EXPANSION: true
  AZURE_BICEP_FILE_EXPANSION: false
  AZURE_BICEP_CHECK_TOOL: true
  AZURE_BICEP_MINIMUM_VERSION: '0.47.16'

input:
  pathIgnore:
    - '**'
    - '!infra/bootstrap/main.bicepparam'

output:
  culture:
    - en-US
```

`.ps-rule/pf-suppressions.Rule.yaml`:

```yaml
# Accepted risks. Each group maps to one entry in docs/security/threat-model.md.
# Add a group only for a risk the threat model accepts; fix everything else.
---
# Threat model: "Public storage endpoint" (docs/security/threat-model.md#public-storage-endpoint)
apiVersion: github.com/microsoft/PSRule/v1
kind: SuppressionGroup
metadata:
  name: PF.PublicStorageEndpoint
spec:
  rule:
    - Azure.Storage.Firewall
  if:
    type: '.'
    equals: Microsoft.Storage/storageAccounts
---
# Threat model: "No Defender for Storage" (docs/security/threat-model.md#no-defender-for-storage)
apiVersion: github.com/microsoft/PSRule/v1
kind: SuppressionGroup
metadata:
  name: PF.NoDefenderForStorage
spec:
  rule:
    - Azure.Storage.DefenderCloud
  if:
    type: '.'
    equals: Microsoft.Storage/storageAccounts
---
# Threat model: "Single-region state storage" (docs/security/threat-model.md#single-region-state-storage)
apiVersion: github.com/microsoft/PSRule/v1
kind: SuppressionGroup
metadata:
  name: PF.SingleRegionState
spec:
  rule:
    - Azure.Storage.UseReplication
  if:
    type: '.'
    equals: Microsoft.Storage/storageAccounts
```

- [ ] **Step 4: Write `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
```

- [ ] **Step 5: Write `.pre-commit-config.yaml`**

Local hooks call the Brewfile tools, so no hook code is downloaded besides the pinned `pre-commit-hooks`.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: 3e8a8703264a2f4a69428a0aa4dcb512790b2c8c  # frozen: v6.0.0
    hooks:
      - id: check-yaml
        args: [--allow-multiple-documents]
      - id: check-json
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-merge-conflict
      - id: check-added-large-files

  - repo: local
    hooks:
      - id: terraform-fmt
        name: terraform fmt
        entry: terraform fmt -check -recursive infra
        language: system
        pass_filenames: false
        files: \.tf$
      - id: terraform-validate
        name: terraform validate
        entry: bash -c 'terraform -chdir=infra/azure/envs/dev init -backend=false -input=false >/dev/null && terraform -chdir=infra/azure/envs/dev validate'
        language: system
        pass_filenames: false
        files: \.tf$
      - id: tflint
        name: tflint
        entry: bash -c 'tflint --recursive --config "$PWD/.tflint.hcl"'
        language: system
        pass_filenames: false
        files: \.tf$
      - id: bicep-lint
        name: bicep lint
        entry: bicep lint infra/bootstrap/main.bicep
        language: system
        pass_filenames: false
        files: \.(bicep|bicepparam)$
      - id: actionlint
        name: actionlint
        entry: actionlint
        language: system
        pass_filenames: false
        files: ^\.github/workflows/
      - id: zizmor
        name: zizmor
        entry: zizmor --offline .github/workflows
        language: system
        pass_filenames: false
        files: ^\.github/
      - id: shellcheck
        name: shellcheck
        entry: shellcheck -x
        language: system
        types: [shell]
      - id: gitleaks
        name: gitleaks
        entry: gitleaks git --pre-commit --staged --redact --no-banner
        language: system
        pass_filenames: false
```

- [ ] **Step 6: Run the local suite**

Run:

```bash
chmod +x scripts/ci/install-tools.sh
pre-commit install
make lint
make test
```

Expected: every `make lint` hook reports `Passed` (or `Skipped` for hooks with no matching files); `make test` ends with `0 failures`.

If `zizmor` or `actionlint` flags a workflow, fix the workflow. If `shellcheck` flags a script, fix the script. Do not add ignore comments unless the finding is a false positive, and then say why in the comment.

- [ ] **Step 7: Commit**

```bash
git add scripts/ci/install-tools.sh .github/workflows/ci.yml ps-rule.yaml .ps-rule/pf-suppressions.Rule.yaml .github/dependabot.yml .pre-commit-config.yaml
git commit -m "Add CI pipeline, PSRule, Dependabot and pre-commit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: OIDC proof workflow

**Files:**
- Create: `.github/workflows/oidc-proof.yml`

**Interfaces:**
- Consumes: `scripts/proof.sh` cases (Task 4); `infra/azure/envs/dev` (Task 6); repo variables from Task 7; environments from Task 10.
- Produces: six jobs: `dev-state`, `denied-no-environment`, `denied-cross-identity`, `denied-cross-env-state`, `denied-delegation-key`, `denied-container-delete`.

- [ ] **Step 1: Write the workflow**

```yaml
name: oidc-proof

on:
  push:
    branches: [main]
  schedule:
    - cron: "17 6 * * 1"
  workflow_dispatch:

permissions: {}

concurrency:
  group: oidc-proof
  cancel-in-progress: false

env:
  AZURE_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  AZURE_CLIENT_ID_DEV: ${{ vars.AZURE_CLIENT_ID_DEV }}
  AZURE_CLIENT_ID_PROD: ${{ vars.AZURE_CLIENT_ID_PROD }}
  TF_STATE_ACCOUNT: ${{ vars.TF_STATE_ACCOUNT }}

jobs:
  dev-state:
    runs-on: ubuntu-24.04
    environment: dev
    permissions:
      contents: read
      id-token: write
    env:
      ARM_USE_OIDC: "true"
      ARM_USE_AZUREAD: "true"
      ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
      ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID_DEV }}
      ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e # v4.0.1
        with:
          terraform_version: 1.16.4
          terraform_wrapper: false
      - name: Show token claims
        run: scripts/proof.sh claims
      - name: terraform init (remote state over OIDC)
        run: terraform -chdir=infra/azure/envs/dev init -input=false -backend-config="storage_account_name=${TF_STATE_ACCOUNT}"
      - name: terraform plan (takes a blob lease)
        run: terraform -chdir=infra/azure/envs/dev plan -input=false -lock-timeout=60s

  denied-no-environment:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: A token from a job with no environment is refused
        run: scripts/proof.sh no-environment

  denied-cross-identity:
    runs-on: ubuntu-24.04
    environment: dev
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: A dev token is refused by the prod identity
        run: scripts/proof.sh cross-identity

  denied-cross-env-state:
    runs-on: ubuntu-24.04
    environment: dev
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: A dev token cannot read prod state
        run: scripts/proof.sh cross-env-state

  denied-delegation-key:
    runs-on: ubuntu-24.04
    environment: dev
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: A dev token cannot mint a user-delegation key
        run: scripts/proof.sh delegation-key

  denied-container-delete:
    runs-on: ubuntu-24.04
    environment: dev
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: A dev token cannot delete its own container
        run: scripts/proof.sh container-delete
```

- [ ] **Step 2: Lint it**

Run: `actionlint && zizmor --offline .github/workflows`
Expected: no findings. Fix any finding in the workflow itself.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/oidc-proof.yml
git commit -m "Add OIDC proof workflow with five lockdown tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Threat model, runbooks and spec changelog

**Files:**
- Create: `docs/security/threat-model.md`, `docs/runbooks/bootstrap.md`, `docs/runbooks/restore-state.md`, `docs/runbooks/teardown.md`
- Modify: `docs/superpowers/specs/2026-09-24-m1-secret-free-bootstrap-design.md` (append a changelog)

**Interfaces:**
- Produces: heading anchors `#public-storage-endpoint`, `#no-defender-for-storage`, `#single-region-state-storage` (linked from `.ps-rule/pf-suppressions.Rule.yaml`).

- [ ] **Step 1: Write `docs/security/threat-model.md`**

```markdown
# Threat model — M1 secret-free bootstrap

## What we protect

- **Terraform state** in `tfstate-dev` and `tfstate-prod`. From M2 on, state describes and changes real infrastructure.
- **The ability to get an Azure token** for `id-pf-dev` or `id-pf-prod`.

## Trust chain

1. A GitHub Actions job with `id-token: write` requests an OIDC token.
2. The repo's custom subject template makes the subject `repository_owner_id:<n>:repository_id:<n>:environment:<env>`.
3. Entra accepts the token only if a federated credential on the identity matches that subject exactly.
4. The identity holds `Terraform State Writer (pf)` on its own container, and nothing else.

## Mitigations

| Risk | Mitigation | Proof |
|---|---|---|
| Compromised action steals a token | `permissions: {}` by default; `id-token: write` per job; SHA-pinned actions enforced by repo policy; no third-party action handles tokens; `persist-credentials: false` | `zizmor`, `actionlint`, CodeQL on every PR |
| Unauthorised job gets an environment token | Environments deploy from `main` only; `prod` needs approval; PR required to reach `main`; no `pull_request_target`; fork PRs get no OIDC token | `denied-no-environment` |
| Repo rename or deletion lets someone claim the name | Subject uses numeric owner and repo IDs | `make verify-bootstrap` checks each subject |
| A stolen token does too much | Custom role: blob read, write, add only; per-container scope | `denied-cross-env-state`, `denied-container-delete`, `denied-cross-identity` |
| A stolen token outlives its hour | Container-scoped role cannot generate user-delegation keys; shared keys are off, so no account SAS | `denied-delegation-key` |
| Operator credentials on the laptop | MFA via security defaults; bootstrap is the only Owner action; `az logout` afterwards; subscription and tenant guards | `tests/common.bats` |
| Other ways into storage | `allowSharedKeyAccess: false`, `defaultToOAuthAuthentication: true`, `allowCrossTenantReplication: false`, no anonymous access, TLS 1.2 | `make verify-bootstrap`, `tests/bicep.bats`, PSRule |

## Accepted risks

### Public storage endpoint

GitHub-hosted runners have no fixed IPs, so the account accepts traffic from the internet. Every request still needs an Entra token for an identity with a role on the container; shared keys are off. PSRule rule `Azure.Storage.Firewall` is suppressed for this reason.

### Public identifiers

Tenant, subscription and client IDs are public in repo variables and logs. They identify; they do not authenticate. No secret exists to pair them with.

### Token lifetime of about an hour

An exfiltrated access token works until it expires. Nothing free shortens it; the mitigations above narrow what it can reach.

### No just-in-time Owner access

Privileged Identity Management needs Entra ID P2. The Owner role is used once, for the bootstrap, behind MFA.

### No blob access logging

Storage diagnostic logs need Log Analytics, which costs money. The Activity Log (control plane, 90 days) and Entra sign-in logs (7 days) provide the audit trail.

### No Defender for Storage

Defender for Storage is paid. Shared keys are off, roles are narrow and versioning allows recovery. PSRule rule `Azure.Storage.DefenderCloud` is suppressed for this reason.

### Single-region state storage

The account uses LRS. State is small, versioned and soft-deleted; a regional outage delays Terraform runs but loses no history beyond the outage. PSRule rule `Azure.Storage.UseReplication` is suppressed for this reason.

## Deferred

- Pin the subject to `job_workflow_ref` once M4's reusable workflows exist.
- Deployment Stacks with deny settings in the security-and-identity roadmap step.
```

- [ ] **Step 2: Write `docs/runbooks/bootstrap.md`**

````markdown
# Runbook: bootstrap

Deploys the state backend and workload identities. Run from a laptop, once, as subscription Owner.

## Prerequisites

1. Tenant security defaults on (Entra admin center → Overview → Properties → Manage security defaults). New tenants have them on.
2. `make doctor` passes.
3. `make github-setup` has run (the repo exists and its OIDC subject is customised).

## Steps

```bash
az login --tenant "<tenant id>"
export EXPECTED_TENANT_ID="<tenant id>"
export EXPECTED_SUBSCRIPTION_ID="<subscription id>"
export PF_LOCATION="<region, e.g. westus2>"
export PF_BUDGET_EMAIL="<alert address>"   # never committed
# export PF_DEPLOY_BUDGET=false            # only if the subscription rejects budgets
make bootstrap          # shows what-if, asks to confirm, deploys, writes repo variables
make verify-bootstrap   # every line must read "ok:"
make proof              # runs oidc-proof.yml on main
az logout
```

## If something fails

- **Guard refuses to run:** `az account show` is on another subscription or tenant. Run `az account set --subscription "$EXPECTED_SUBSCRIPTION_ID"`.
- **Budget deployment fails on a free trial:** set `PF_DEPLOY_BUDGET=false`, rerun, and record it; deploy the budget after the pay-as-you-go upgrade.
- **Role assignment fails with "principal not found":** Entra replication lag after creating the identity. Rerun `make bootstrap`; the deployment is idempotent.
````

- [ ] **Step 3: Write `docs/runbooks/restore-state.md`**

````markdown
# Runbook: restore Terraform state

The Owner account has no data-plane role on the state account, by design. Restoring needs a temporary role, which the Activity Log records.

## 1. Grant yourself temporary access

```bash
ACCT=$(az storage account list -g rg-pf-bootstrap --query "[?starts_with(name,'stpf')].name | [0]" -o tsv)
SCOPE=$(az storage account show -n "$ACCT" -g rg-pf-bootstrap --query id -o tsv)
ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee "$ME" --role "Storage Blob Data Contributor" --scope "$SCOPE"
```

## 2a. Restore a deleted container (within 7 days)

```bash
az storage container list --account-name "$ACCT" --include-deleted --auth-mode login \
  --query "[?deleted].{name:name, version:version}" -o table
az storage container restore --account-name "$ACCT" --name tfstate-dev \
  --deleted-version "<version>" --auth-mode login
```

## 2b. Restore an overwritten state file

```bash
az storage blob list --account-name "$ACCT" --container-name tfstate-dev --include v \
  --auth-mode login --query "[].{name:name, version:versionId, current:isCurrentVersion}" -o table
az storage blob copy start --account-name "$ACCT" --auth-mode login \
  --destination-container tfstate-dev --destination-blob dev.tfstate \
  --source-uri "https://$ACCT.blob.core.windows.net/tfstate-dev/dev.tfstate?versionid=<version>"
```

## 3. Remove the temporary access

```bash
az role assignment delete --assignee "$ME" --role "Storage Blob Data Contributor" --scope "$SCOPE"
az role assignment list --assignee "$ME" --scope "$SCOPE" -o table   # expect no rows
```
````

- [ ] **Step 4: Write `docs/runbooks/teardown.md`**

````markdown
# Runbook: teardown

`make teardown` deletes the bootstrap in this order and verifies each step:

1. `pf-state-lock` (the lock blocks everything below it)
2. Role assignments for `id-pf-dev` and `id-pf-prod`
3. Custom role `Terraform State Writer (pf)`
4. Resource group `rg-pf-bootstrap` (storage account, identities, federated credentials)
5. Budget `pf-budget`

```bash
export EXPECTED_TENANT_ID="<tenant id>" EXPECTED_SUBSCRIPTION_ID="<subscription id>"
make teardown   # asks to confirm; ends with "teardown verified"
```

It is safe to rerun after a partial failure.

## Manual fallback

```bash
ACCT=$(az storage account list -g rg-pf-bootstrap --query "[?starts_with(name,'stpf')].name | [0]" -o tsv)
az lock delete --name pf-state-lock -g rg-pf-bootstrap --resource-name "$ACCT" --resource-type Microsoft.Storage/storageAccounts
for env in dev prod; do
  PID=$(az identity show -n "id-pf-$env" -g rg-pf-bootstrap --query principalId -o tsv)
  for id in $(az role assignment list --assignee "$PID" --all --query '[].id' -o tsv); do az role assignment delete --ids "$id"; done
done
az role definition delete --name "Terraform State Writer (pf)" --custom-role-only true \
  --scope "/subscriptions/$EXPECTED_SUBSCRIPTION_ID/resourceGroups/rg-pf-bootstrap"
az group delete -n rg-pf-bootstrap --yes
az consumption budget delete --budget-name pf-budget
```

## Verification

```bash
az group exists -n rg-pf-bootstrap                                              # false
az role definition list --custom-role-only true --name "Terraform State Writer (pf)" -o tsv   # empty
az consumption budget list -o table                                            # no pf-budget
```

Cancelling the subscription (portal → Subscriptions → Cancel) comes last, and only if the project is retired.
````

- [ ] **Step 5: Append the changelog to the spec**

Append to `docs/superpowers/specs/2026-09-24-m1-secret-free-bootstrap-design.md`:

```markdown

## 12. Changelog

Deviations and additions made while planning implementation (2026-09-24):

- **`modules/state-access.bicep` added.** A container-scoped role assignment must be declared in a resource-group-scoped module, not directly in `main.bicep`.
- **`scripts/lib/http.sh`, `scripts/proof.sh`, `scripts/doctor.sh`, `scripts/ci/install-tools.sh` added.** Workflow jobs call `proof.sh <case>`, so the proof logic is unit-tested.
- **Deploy-time environment variables use the `PF_` prefix** (`PF_BUDGET_EMAIL` replaces `BUDGET_EMAIL`). The param file reads them with `readEnvironmentVariable`; Actions reserves `GITHUB_*`.
- **PSRule suppressions live in `.ps-rule/pf-suppressions.Rule.yaml`** as SuppressionGroups, one per threat-model entry, instead of in `ps-rule.yaml`.
- **Threat model adds "Single-region state storage" (LRS)** as an accepted risk.
- **Teardown also deletes the role assignments and the custom role definition.** Role definitions outlive their resource group. The brief's cost sheet lacks this row; record it at the M1 checkpoint with the lock-before-group ordering.
- **The dev root declares the `azurerm` provider** with `resource_provider_registrations = "none"`, so the lock file exists and the provider never needs control-plane rights in M1.
- **Dependabot uses a 7-day cooldown**; pre-commit uses local system hooks from the Brewfile.
- **Entra and Storage error codes** (`AADSTS700213`, `AuthorizationPermissionMismatch`) are confirmed against real responses in Task 15; corrections are recorded here.
```

- [ ] **Step 6: Commit**

```bash
git add docs/security docs/runbooks docs/superpowers/specs/2026-09-24-m1-secret-free-bootstrap-design.md
git commit -m "Add threat model, runbooks and spec changelog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Live — GitHub setup and a green PR (operator-assisted)

**Files:**
- Modify only if CI finds problems: `.ps-rule/pf-suppressions.Rule.yaml`, `docs/security/threat-model.md`, workflow or script files.

**Interfaces:**
- Consumes: `make github-setup` (Task 10), `ci.yml` (Task 11).
- Produces: a public repo with the Task 10 settings, and an open PR from `P0-planning-and-tooling` to `main` with a green `ci` check. **Do not merge yet** (Task 15 merges after the bootstrap).

- [ ] **Step 1: Run GitHub setup**

Run: `make github-setup`
Expected: ends with `GitHub setup complete for edward-sf/platform-foundations`.

Check: `gh api repos/edward-sf/platform-foundations/actions/oidc/customization/sub`
Expected: `{"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","environment"]}`

If any API call fails (for example, a setting this account's plan doesn't offer), stop and report the exact error to the operator rather than removing the setting.

- [ ] **Step 2: Push the branch and open the PR**

```bash
git push -u origin P0-planning-and-tooling
gh pr create --repo edward-sf/platform-foundations --base main --head P0-planning-and-tooling \
  --title "M1: secret-free bootstrap" \
  --body "Implements docs/superpowers/specs/2026-09-24-m1-secret-free-bootstrap-design.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 3: Get `ci` green**

Run: `gh pr checks --repo edward-sf/platform-foundations --watch`
Expected: `ci`, `terraform`, `bicep`, `workflows`, `shell`, `psrule` and CodeQL all pass.

For each PSRule failure:
- If the rule maps to an accepted risk already in the threat model, confirm the rule name in the suppression file matches the reported name exactly.
- Otherwise fix the Bicep.
- If neither applies, stop and ask the operator before adding a new accepted risk.

Commit each fix with a message naming the rule, push, and re-watch.

---

### Task 15: Live — bootstrap and first proof (operator-assisted)

**Files:**
- Modify only if a real response differs from the plan: `scripts/proof.sh` (error constants), `infra/bootstrap/modules/role.bicep` (data actions), `infra/bootstrap/main.bicep` (subject format); plus the matching tests and the spec changelog.

**Interfaces:**
- Consumes: `make bootstrap`, `make verify-bootstrap`, `make proof` and the Task 14 PR.
- Produces: deployed bootstrap; repo variables set; merged PR; green `oidc-proof` run on `main`.

- [ ] **Step 1: Operator signs in (MFA) and sets the guard variables**

The operator runs, in their own terminal:

```bash
az login --tenant "<tenant id>"
export EXPECTED_TENANT_ID="<tenant id>" EXPECTED_SUBSCRIPTION_ID="<subscription id>"
export PF_LOCATION="<region>" PF_BUDGET_EMAIL="<alert address>"
```

- [ ] **Step 2: Deploy**

Run: `make bootstrap`
Expected: what-if lists the resource group, storage account, 2 containers, lock, role definition, 2 identities, 2 federated credentials, 2 role assignments and the budget; after `y`, the deployment succeeds and five `gh variable set` lines follow.

If the budget fails on a free-trial offer: rerun with `PF_DEPLOY_BUDGET=false` and note it for the checkpoint.

- [ ] **Step 3: Verify**

Run: `make verify-bootstrap`
Expected: every line starts with `ok:` and the last line is `==> bootstrap verified`.

If `custom role ... exists` fails while the portal shows the role, the listing does not see resource-group-scoped roles: change `find_role_definition_ids` in `scripts/lib/common.sh` to pass `--scope "/subscriptions/$EXPECTED_SUBSCRIPTION_ID/resourceGroups/$PF_RG"`, rerun, and record it in the spec changelog.

- [ ] **Step 4: Merge the PR**

```bash
gh pr merge --repo edward-sf/platform-foundations --squash --delete-branch=false
```

The push to `main` starts `oidc-proof`.

- [ ] **Step 5: Watch the first proof run**

```bash
gh run watch --repo edward-sf/platform-foundations --exit-status \
  "$(gh run list --repo edward-sf/platform-foundations --workflow oidc-proof.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Expected: all six jobs green.

- [ ] **Step 6: Confirm every observed value against the plan**

For each job, read its log (`gh run view <id> --log --job <job id>`) and check:

| Check | Expected | If different |
|---|---|---|
| `dev-state` claims `sub` | `repository_owner_id:<n>:repository_id:<n>:environment:dev` | Fix the subject in `main.bicep`, `verify-bootstrap.sh` and tests; redeploy |
| `denied-no-environment` / `denied-cross-identity` | `PASS: denied ... AADSTS700213` | If Entra returns `AADSTS70021`, update `ENTRA_DENIED` in `proof.sh` and the tests |
| Three storage denials | `PASS: denied with HTTP 403 and AuthorizationPermissionMismatch` | Update `STORAGE_DENIED`/the expected status only after reading the real error body; a 2xx is a security finding, not a test fix: stop and report |
| `terraform init` / `plan` | Success with no permission error | If a data action is missing, add the single smallest one to `role.bicep`, update `tests/bicep.bats`, redeploy |

Each correction goes through a PR (the ruleset requires one), and each is recorded in the spec changelog. Rerun `make proof` until all six jobs are green with the confirmed values.

---

### Task 16: Live — evidence (operator-assisted)

**Files:**
- Create: `docs/evidence/m1/README.md`, `docs/evidence/m1/oidc-proof-<run id>.log`, `docs/evidence/m1/activity-log.json`, `docs/evidence/m1/entra-sign-ins.png`

**Interfaces:**
- Consumes: a green `oidc-proof` run from Task 15.

- [ ] **Step 1: Save the run log and check it for leaked tokens**

```bash
RUN=$(gh run list --repo edward-sf/platform-foundations --workflow oidc-proof.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId')
mkdir -p docs/evidence/m1
gh run view "$RUN" --repo edward-sf/platform-foundations --log > "docs/evidence/m1/oidc-proof-$RUN.log"
grep -Ec 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' "docs/evidence/m1/oidc-proof-$RUN.log"
```

Expected: the count is `0`. Any other number means a token leaked: delete the file, stop, and report.

- [ ] **Step 2: Export the Activity Log without caller identities**

```bash
az monitor activity-log list --resource-group rg-pf-bootstrap --offset 7d -o json \
  | jq '[.[] | {time: .eventTimestamp, operation: .operationName.value, status: .status.value, resource: .resourceId}]' \
  > docs/evidence/m1/activity-log.json
```

- [ ] **Step 3: Operator captures the sign-in logs**

In the Entra admin center: Monitoring → Sign-in logs → *Service principal sign-ins* (and *Managed identity sign-ins*), filtered to the last 24 hours. The screenshot must show at least one success for `id-pf-dev` and the `AADSTS700213` failures. Save it as `docs/evidence/m1/entra-sign-ins.png`.

- [ ] **Step 4: Write `docs/evidence/m1/README.md`**

```markdown
# M1 evidence

| File | Shows |
|---|---|
| `oidc-proof-<run id>.log` | A green run: token claims, `terraform init`/`plan` over OIDC, and five `PASS: denied` lines with exact codes. Contains no tokens (checked with a JWT pattern search). |
| `activity-log.json` | Control-plane changes in `rg-pf-bootstrap`, caller identities removed. |
| `entra-sign-ins.png` | Entra's view of the same run: `id-pf-dev` succeeding, and the refused exchanges (`AADSTS700213`). |

Repository settings (OIDC subject template, environments, ruleset, Actions policy) are reproducible with `make github-setup`.
```

Replace `<run id>` in the table with the real run ID.

- [ ] **Step 5: Commit via PR**

```bash
git fetch origin
git switch -c m1-evidence origin/main
git add docs/evidence/m1
git commit -m "Add M1 evidence: proof run, activity log, sign-in logs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin m1-evidence
gh pr create --repo edward-sf/platform-foundations --base main --head m1-evidence --title "M1 evidence" \
  --body "Evidence for M1's definition of done.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
gh pr checks --repo edward-sf/platform-foundations --watch
gh pr merge --repo edward-sf/platform-foundations --squash
```

---

### Task 17: Live — lifecycle test and sign-out (operator-assisted)

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-m1-secret-free-bootstrap-design.md` (changelog: lifecycle result)

**Interfaces:**
- Consumes: `make teardown`, `make bootstrap`, `make verify-bootstrap`, `make proof`.

- [ ] **Step 1: Tear down**

Run: `make teardown` and answer `y`.
Expected: `==> teardown verified`.

- [ ] **Step 2: Rebuild from nothing**

Run: `make bootstrap`, answer `y`, then `make verify-bootstrap`.
Expected: `==> bootstrap verified`. New identities get new client IDs; `bootstrap.sh` rewrites the repo variables.

If the storage account name is briefly unavailable after deletion, wait 10 minutes and rerun; record the delay in the changelog.

- [ ] **Step 3: Prove again**

Run: `make proof`
Expected: all six jobs green.

- [ ] **Step 4: Sign out**

Run: `az logout && az account show`
Expected: `az account show` reports that you are not logged in.

- [ ] **Step 5: Record the result and the checkpoint adjustments**

Append to the spec changelog:

```markdown
- **Lifecycle test (YYYY-MM-DD):** teardown verified → bootstrap → verify → proof green. Brief adjustments for the M1 checkpoint: the `rg-pf-bootstrap` teardown step becomes "`make teardown` (lock, role assignments, custom role, group, budget)"; add a cost-sheet row for the custom role definition ($0; `az role definition delete`; verified by `az role definition list --custom-role-only true --name "Terraform State Writer (pf)"` returning nothing).
```

Replace `YYYY-MM-DD` with the date of the run. Commit through a PR as in Task 16, Step 5 (branch `m1-lifecycle`).

- [ ] **Step 6: Hand off**

M1 is complete when every item in the spec's section 11 is checked. Next: run `portfolio-checkpoint` for M1.
