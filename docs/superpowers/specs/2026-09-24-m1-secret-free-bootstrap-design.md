# M1: Secret-free bootstrap — Design

**Milestone:** M1 of [docs/portfolio/brief.md](../../portfolio/brief.md)
**Date:** 2026-09-24
**Status:** approved in conversation, pending written-spec review

## 1. Intent

GitHub Actions reaches Azure with no stored secrets. Bicep creates the Terraform state backend and one workload identity per environment. A `dev` job authenticates through OIDC and runs `terraform init` and `plan` against remote state. Five lockdown tests show that tokens obtained any other way are refused or can do nothing outside their own container.

**Success, seen by a recruiter:** a public repo with green runs that authenticated to Azure with no secrets configured, the token claims those runs used, and a written explanation of why each lockdown test was refused.

### Fixed constraints (from the brief)

- Flagship tier; about $0.05 a month against a $2 threshold.
- Public repo `edward-sf/platform-foundations`.
- Terraform modules and promotion belong to M2; Kubernetes to M3; reusable workflows to M4.
- Understanding targets: workload identity federation; Bicep deployment scopes and the bootstrap's place outside Terraform; the azurerm backend with Entra auth and blob-lease locking.

### Confirmed assumptions

1. The operator runs the bootstrap once, from a laptop, as subscription Owner. Everything afterwards runs through CI.
2. Dev and prod state live in separate containers; each identity reaches only its own.
3. The storage account disables shared-key access.
4. The personal Azure account and its Entra tenant are entirely separate from the work tenant.
5. The repo is `edward-sf/platform-foundations`, public.

### Prerequisites

- An Azure subscription. The free trial suffices for M1; upgrade to pay-as-you-go before the trial ends to keep the flagship live. If the trial rejects Cost Management budgets, record that and deploy the budget after the upgrade.
- Security defaults enabled on the new tenant (MFA for the operator).
- The public GitHub repo, created by `scripts/github-setup.sh`.

## 2. Approach

A plain subscription-scope Bicep deployment (`az deployment sub create`) with a `CanNotDelete` lock on the storage account.

**Rejected:** Azure Deployment Stacks with deny settings. They add one-command teardown and deny writes from every principal but the operator, at the cost of a fourth new concept and a changed teardown path. **Deferred** to the security-and-identity roadmap step, where guarding the platform's own foundation is the headline.

## 3. Azure resources and trust

### Order of operations

1. Create the repo.
2. Customise its OIDC subject template to include numeric IDs.
3. Run the bootstrap with those IDs as parameters.

### Resources (`infra/bootstrap/main.bicep`, subscription scope)

| Module | Creates | Settings |
|---|---|---|
| `main.bicep` | `rg-pf-bootstrap` | Location is a parameter. Tags: `project=platform-foundations`, `managed-by=bicep`, `env=shared`. |
| `modules/storage.bicep` | Storage account `stpf<uniqueString(subscription().id)>`; containers `tfstate-dev`, `tfstate-prod` | StorageV2, Standard_LRS. `allowSharedKeyAccess: false`, `defaultToOAuthAuthentication: true`, `allowCrossTenantReplication: false`, `allowBlobPublicAccess: false`, `minimumTlsVersion: TLS1_2`, `supportsHttpsTrafficOnly: true`. Blob versioning on; blob and container soft delete, 7 days. `CanNotDelete` lock on the account. |
| `modules/identity.bicep` (called for `dev` and `prod`) | `id-pf-<env>` with one federated identity credential | Issuer `https://token.actions.githubusercontent.com`; audience `api://AzureADTokenExchange`; subject built from `repository_owner_id`, `repository_id` and `environment` (for example `repository_owner_id:<n>:repository_id:<n>:environment:dev`). M1 confirms the exact format by decoding a real token. |
| `modules/role.bicep` | Custom role `Terraform State Writer (pf)`, assignable only within `rg-pf-bootstrap` | Data actions only: `…/containers/blobs/read`, `…/containers/blobs/write`, `…/containers/blobs/add/action`. No blob delete, no container actions, no user-delegation key. If `terraform init` needs more, add the smallest missing action and record why in the spec's changelog. |
| (assignments in `main.bicep`) | `id-pf-dev` → role on `tfstate-dev`; `id-pf-prod` → role on `tfstate-prod` | No role at subscription or resource-group scope in M1. |
| `modules/budget.bicep` | `pf-budget`, $2 monthly, subscription scope | Alerts at 50% and 100% actual and 100% forecast. The contact email comes from the `BUDGET_EMAIL` environment variable at deploy time and is never committed. |

### Why user-assigned managed identities

No one can add a client secret or certificate to a managed identity. An app registration would allow a later secret to reintroduce what this project removes. Deleting the resource group also deletes the identities.

### Who can obtain a token

- **GitHub:** both environments deploy from `main` only; `prod` also requires the operator's approval. A ruleset requires a PR to reach `main`. No workflow uses `pull_request_target`. Fork PRs receive no OIDC token.
- **Azure:** a token is accepted only if its subject matches the repo's numeric owner ID, repo ID and environment exactly. A same-named repo created after a rename or deletion cannot match.

### What a stolen token can do

For about an hour, read or overwrite blobs in one container. It cannot delete the container, mint long-lived SAS, or reach the other environment. Versioning and soft delete recover an overwrite.

### Operator safety

- `make bootstrap` refuses to run unless the signed-in subscription and tenant equal `EXPECTED_SUBSCRIPTION_ID` and `EXPECTED_TENANT_ID`.
- It runs what-if, shows the diff and asks for confirmation before deploying.
- The operator runs `az logout` afterwards.
- The Owner account holds no data-plane role on the state account. Restoring a blob requires a temporary role assignment, which the Activity Log records.

### Audit trail (free tier only)

- Azure Activity Log: control-plane changes, 90 days.
- Entra sign-in logs: each identity's token exchanges, 7 days.
- M1 exports both as evidence into `docs/evidence/m1/`.

## 4. GitHub setup and workflows

### `scripts/github-setup.sh` (idempotent, runs with the operator's `gh` login)

| Setting | Value |
|---|---|
| Visibility | Public |
| Default `GITHUB_TOKEN` permissions | Read-only; Actions may not approve PRs |
| Allowed actions | GitHub-owned, plus `hashicorp/setup-terraform` and `microsoft/ps-rule`; the "require full-length commit SHA" policy on |
| Fork PR workflows | Approval required for all outside contributors |
| OIDC subject template | `include_claim_keys: [repository_owner_id, repository_id, environment]` |
| Ruleset on `main` | PR required (0 approvals, solo maintainer); required status check `ci`; no force push or deletion; linear history |
| Environment `dev` | Deployment branches: `main` only |
| Environment `prod` | Deployment branches: `main` only; required reviewer `edward-sf` |
| Repo variables (not secrets) | `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_DEV`, `AZURE_CLIENT_ID_PROD`, `TF_STATE_ACCOUNT` (written by `make bootstrap`) |
| Security features | Secret scanning with push protection; Dependabot alerts; Dependabot version updates for `github-actions`, weekly; CodeQL default setup for the `actions` language |

Client IDs sit at repo level, not environment level, so lockdown tests can present them from the wrong context.

### `.github/workflows/ci.yml`

Triggers: `pull_request`, `push` to `main`. Permissions: `contents: read`. No OIDC.

Jobs: Terraform `fmt -check`, `validate`, `tflint`; `bicep lint` and `bicep build`; `actionlint`; `zizmor`; `shellcheck`; `bats` tests; PSRule for Azure (`Azure.GA` baseline) against the expanded Bicep. An aggregate job named `ci` depends on all of them and is the required status check.

**Tool installation in CI:** `actions/checkout`, `hashicorp/setup-terraform` and `microsoft/ps-rule` are the only actions. Other tools (`tflint`, `actionlint`, `zizmor`, `shellcheck`, `bats`, Bicep via `az bicep install --version`) install at pinned versions, with release downloads verified against published checksums.

**PSRule suppressions** live in `ps-rule.yaml`. Each accepted risk that PSRule flags (for example, the public network endpoint) gets a suppression whose comment links to its entry in `docs/security/threat-model.md`. PSRule is a guardrail in M1, not an understanding target.

### `.github/workflows/oidc-proof.yml`

Triggers: `push` to `main`, weekly `schedule`, `workflow_dispatch` (from `main`). Workflow-level `permissions: {}`; each job grants itself `id-token: write` and `contents: read` only.

Token handling: `scripts/lib/token.sh` requests the GitHub OIDC token and exchanges it at the Entra token endpoint using `curl` and `jq`. No third-party action touches a token. Each access token is masked with `::add-mask::` as soon as it exists. Scripts print token claims (`sub`, `aud`, `iss`), never tokens.

| Job | Environment | Action | Expected |
|---|---|---|---|
| `dev-state` | `dev` | `terraform init` and `terraform plan` in `infra/azure/envs/dev` (backend only; `use_oidc = true`, `use_azuread_auth = true`). `plan` takes a blob lease, proving locking. Prints claims. | Success |
| `denied-no-environment` | none | Exchange the job's token for `id-pf-dev` | Entra error `AADSTS700213` |
| `denied-cross-identity` | `dev` | Exchange a `dev` token for `id-pf-prod` | Entra error `AADSTS700213` |
| `denied-cross-env-state` | `dev` | List blobs in `tfstate-prod` | HTTP 403, `AuthorizationPermissionMismatch` |
| `denied-delegation-key` | `dev` | Request a user-delegation key | HTTP 403 |
| `denied-container-delete` | `dev` | Delete container `tfstate-dev` | HTTP 403 |

Implementation confirms each exact error code against a real response before hard-coding it (Entra may return the older `AADSTS70021` instead of `AADSTS700213`); the spec changelog records any correction.

**Test integrity rules**

1. **Positive control first.** Each denial job in `dev` lists blobs in `tfstate-dev` with the same token and requires HTTP 200 before running its denial. A broken token therefore fails the job instead of passing it.
2. **Exact codes.** `scripts/assert-denied.sh` passes only on the expected status and error code. An unexpected success, a different code or no response fails the job.

**Known risk:** if `denied-container-delete` ever succeeded, it would delete `tfstate-dev`. Container soft delete keeps it recoverable for 7 days; `docs/runbooks/restore-state.md` gives the restore command.

**Note:** GitHub disables scheduled workflows in public repos after 60 days without commits. The Delivery milestone addresses keeping the weekly run alive.

## 5. Repo layout

```
.github/
  workflows/ci.yml, oidc-proof.yml
  dependabot.yml
infra/
  bootstrap/            main.bicep, main.bicepparam, bicepconfig.json
    modules/            storage.bicep, identity.bicep, role.bicep, budget.bicep
  azure/envs/dev/       versions.tf, backend.tf
scripts/
  lib/common.sh         strict mode, logging, preflight guards
  lib/token.sh          GitHub OIDC → Entra exchange, masked
  assert-denied.sh
  github-setup.sh, bootstrap.sh, verify-bootstrap.sh, teardown.sh
tests/                  bats tests for scripts
docs/
  security/threat-model.md
  runbooks/bootstrap.md, restore-state.md, teardown.md
  evidence/m1/
Brewfile, Makefile, ps-rule.yaml, .pre-commit-config.yaml, .tflint.hcl, .gitignore, .editorconfig
```

## 6. Tooling

- **`Brewfile`:** `azure-cli`, `bicep`, `tflint`, `pre-commit`, `actionlint`, `zizmor`, `shellcheck`, `gitleaks`, `bats-core`. Terraform is pinned through `required_version`; CI installs the same version.
- **pre-commit:** mirrors the `ci.yml` checks (except PSRule, which runs in CI only) and adds `gitleaks`. Hook revisions pinned to commit SHAs (`pre-commit autoupdate --freeze`).
- **`bicepconfig.json`:** `outputs-should-not-contain-secrets`, `use-secure-value-for-secure-inputs`, `secure-parameter-default`, `no-hardcoded-location` and `no-unused-params` set to `error`.
- **`.terraform.lock.hcl`** committed, so provider downloads are hash-checked. `infra/azure/envs/dev/versions.tf` declares `required_version` and the `azurerm` provider, so the lock file exists from M1.

### Make targets

| Target | Does |
|---|---|
| `make doctor` | Checks each tool exists and prints its version |
| `make lint` | Runs the `ci.yml` checks locally (except PSRule) |
| `make test` | Runs the bats tests |
| `make github-setup` | Runs `scripts/github-setup.sh` after checking `gh` is signed in as `edward-sf` |
| `make bootstrap` | Subscription and tenant guard → what-if → confirm → deploy → write GitHub variables from deployment outputs |
| `make verify-bootstrap` | Asserts deployed state with `az` and `jq`: shared-key access off, lock present, each identity has exactly one role assignment at container scope and none at subscription scope, federated credential subjects correct |
| `make proof` | `gh workflow run oidc-proof.yml` and watches it to completion |
| `make teardown` | Deletes the lock, then `rg-pf-bootstrap`, then `pf-budget`; runs each verification from the brief's cost sheet |

## 7. Testing

1. **Static:** pre-commit locally; `ci.yml` on every PR (Terraform, Bicep, workflow, shell and bats checks, PSRule); CodeQL default setup on every PR, outside `ci.yml`.
2. **Unit (bats, test-first):** `assert-denied.sh` passes on the expected code and fails on unexpected success, a wrong code and no response; `common.sh` refuses a mismatched subscription or tenant.
3. **Pre-deploy:** what-if review inside `make bootstrap`.
4. **Post-deploy:** `make verify-bootstrap`.
5. **Integration:** `oidc-proof.yml` — one success path and five lockdown tests.
6. **Lifecycle, once:** bootstrap → proof → teardown → verify gone → bootstrap → proof green. This proves the teardown path and the rebuild, and confirms the lock-before-group teardown order.

### Error handling

Every script runs in strict mode (`set -euo pipefail`), fails with a clear message when a tool, login or variable is missing, and checks the target subscription and GitHub account before acting. No script prints a token.

## 8. Accepted risks

Recorded in `docs/security/threat-model.md` with mitigations:

| Risk | Why accepted | Mitigation |
|---|---|---|
| Public storage endpoint | GitHub-hosted runners have no fixed IPs | Entra token plus a container-scoped role required; shared keys off |
| Tenant, subscription and client IDs public | Identifiers, not credentials | No secrets exist to pair them with |
| A stolen token lives about an hour | No free way to shorten it | SHA pinning, minimal permissions and steps, single-container scope |
| No just-in-time Owner access | PIM needs Entra P2 | MFA; bootstrap is the only Owner action; `az logout` afterwards |
| No blob access logging | Log Analytics costs money | Activity Log and Entra sign-in logs |
| No Defender for Storage | Paid | Keys off, narrow roles, versioning |

## 9. Deferred

- Pin the OIDC subject to `job_workflow_ref` — M4, once reusable workflows exist.
- Deployment Stacks with deny settings — security-and-identity roadmap step.

## 10. Brief adjustment for the M1 checkpoint

The cost sheet's `rg-pf-bootstrap` teardown (`az group delete`) fails while the `CanNotDelete` lock exists. The checkpoint should record the corrected order: `az lock delete`, then `az group delete`. The lifecycle test confirms it.

## 11. Definition of done (maps to the brief)

- [ ] Repo tooling: `Brewfile`, pre-commit, `tflint`, `bicep lint`, `Makefile`; `make doctor`, `make lint` and `make test` pass.
- [ ] `make bootstrap` deploys `rg-pf-bootstrap` from Bicep; `make verify-bootstrap` passes.
- [ ] `oidc-proof.yml` `dev-state` job green; the repo holds no Azure secrets.
- [ ] All five lockdown tests green (each denial observed with its exact code); evidence in `docs/evidence/m1/`.
- [ ] `pf-budget` exists (or its deferral to the pay-as-you-go upgrade is recorded).
- [ ] CodeQL and PSRule run on PRs; PSRule suppressions link to the threat model.
- [ ] Lifecycle test completed once.
- [ ] `docs/security/threat-model.md` and the three runbooks written.

## 12. Changelog

Deviations and additions made while planning and building (2026-09-24):

- **`modules/state-access.bicep` added.** A container-scoped role assignment must be declared in a resource-group-scoped module, not directly in `main.bicep`.
- **`scripts/lib/http.sh`, `scripts/proof.sh`, `scripts/doctor.sh`, `scripts/ci/install-tools.sh` added.** Workflow jobs call `proof.sh <case>`, so the proof logic is unit-tested.
- **Deploy-time environment variables use the `PF_` prefix** (`PF_BUDGET_EMAIL` replaces `BUDGET_EMAIL`). The param file reads them with `readEnvironmentVariable`; Actions reserves `GITHUB_*`.
- **PSRule suppressions live in `.ps-rule/pf-suppressions.Rule.yaml`** as SuppressionGroups, one per threat-model entry, instead of in `ps-rule.yaml`.
- **Threat model adds "Single-region state storage" (LRS)** as an accepted risk.
- **Teardown also deletes the role assignments and the custom role definition.** Role definitions outlive their resource group. The brief's cost sheet lacks this row; record it at the M1 checkpoint with the lock-before-group ordering.
- **The dev root declares the `azurerm` provider** with `resource_provider_registrations = "none"`, so the lock file exists and the provider never needs control-plane rights in M1.
- **Dependabot uses a 7-day cooldown**; pre-commit uses local system hooks from the Brewfile, and its shellcheck hook skips `*.bats` to match CI.
- **Bicep and tflint are not installed from Homebrew.** Homebrew refuses the untrusted `azure/bicep` tap and no longer ships `tflint`; both are installed at CI's pinned versions (`az bicep install`, checksum-verified tflint release) as the Brewfile comments describe.
- **Bicep API versions moved to current GA** (storage 2025-06-01, managed identity 2024-11-30, resource groups 2025-04-01, budgets 2026-06-01) so the linter is warning-free.
- **Entra and Storage error codes** (`AADSTS700213`, `AuthorizationPermissionMismatch`) are confirmed against real responses in plan Task 15; corrections are recorded here.
- **Final review fixes.** Lookups now tell "not found" apart from real errors (`az_absent_ok`), so a throttled or expired call fails loudly instead of reading as "absent" in teardown, verification or the budget start date. The deployment outputs `roleDefinitionId`; teardown and verification find the custom role by that ID, which works after the resource group is gone. `make proof` watches the run it dispatched (`scripts/run-proof.sh`), never an older one.
