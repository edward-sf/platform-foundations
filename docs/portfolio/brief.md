# platform-foundations — Portfolio Brief

**Status:** active

## Pitch
A platform where every layer is code and a merged pull request is the only path to prod. Terraform and Bicep manage a small Azure footprint that GitHub Actions reaches through OIDC federation with no stored secrets. Argo CD runs GitOps on local kind clusters for dev and prod.

## Showcases
- Terraform authored end to end: modules, remote state in Azure Storage, promotion from dev to prod
- Bicep (bootstrap of the state backend and the workload identities)
- GitHub Actions → Azure authentication through Entra workload identity federation (OIDC, no stored secrets)
- CI/CD as a platform: reusable GitHub Actions workflows, with GitHub environments as promotion gates
- Kubernetes (kind), Helm, GitOps with Argo CD (app-of-apps)

## Tier
flagship

## Cost Sheet
| Resource | Purpose | Est. monthly cost | Covered by existing plan? | Teardown step | Teardown verification |
|---|---|---|---|---|---|
| Azure pay-as-you-go subscription | Holds the Azure footprint | $0 | no (new, pay-per-use) | Portal → Subscriptions → Cancel subscription (after every row below is gone) | `az account list -o table` shows the subscription `Disabled`, or it's absent |
| Resource group `rg-pf-bootstrap` | Holds the state storage and the workload identities; deployed with Bicep | $0 | n/a | `az group delete -n rg-pf-bootstrap --yes` | `az group exists -n rg-pf-bootstrap` → `false` |
| Storage account (Standard LRS, Blob; versioning and soft delete on) | Terraform remote state and locking (a few KB, a few hundred transactions a month) | ~$0.05 | no | Removed with `rg-pf-bootstrap`; to delete it alone: `az storage account delete -n <name> -g rg-pf-bootstrap --yes` | `az storage account list -o table` has no `<name>` |
| User-assigned managed identity `id-pf-dev` + federated credential (subject `repo:<owner>/platform-foundations:environment:dev`) | Lets the GitHub Actions `dev` environment reach Azure with no secrets | $0 | n/a | Removed with `rg-pf-bootstrap` | `az identity list -g rg-pf-bootstrap -o table` is empty, or the group doesn't exist |
| User-assigned managed identity `id-pf-prod` + federated credential (subject `…:environment:prod`) | Same, for prod; the prod environment requires approval | $0 | n/a | Removed with `rg-pf-bootstrap` | Same as above |
| Azure RBAC role assignments (identity → state container, identity → env resource group) | Least-privilege access for each identity | $0 | n/a | Removed with their scopes; or `az role assignment delete --assignee <principalId>` | `az role assignment list --assignee <principalId> --all -o table` is empty |
| Resource groups `rg-pf-dev`, `rg-pf-prod` (tags, locks, budget) | The Terraform-managed, per-environment footprint that promotion moves from dev to prod | $0 | n/a | `terraform destroy` in each environment root, or `az group delete -n rg-pf-<env> --yes` | `az group exists -n rg-pf-<env>` → `false` |
| Azure Cost Management budget + alert ($2) | FinOps safeguard for the flagship threshold | $0 | n/a | `az consumption budget delete --budget-name pf-budget` | `az consumption budget list -o table` has no `pf-budget` |
| GitHub Actions minutes (public repo) | CI/CD: builds, plans, applies | $0 | yes (free for public repos) | Disable the workflows, or archive or delete the repo | `gh workflow list` shows every workflow disabled |
| GitHub environments `dev`, `prod` (protection rules) | Promotion gates; the OIDC subject claim | $0 | yes | `gh api -X DELETE repos/<owner>/platform-foundations/environments/<env>` | `gh api repos/<owner>/platform-foundations/environments` lists none |
| GHCR container images (public) | Sample service images | $0 | yes (free for public packages) | `gh api -X DELETE /user/packages/container/<image>` | `gh api /user/packages?package_type=container` has no `<image>` |
| kind clusters `pf-dev`, `pf-prod` (with Argo CD, Helm releases) | Local Kubernetes targets for GitOps | $0 (laptop) | yes (local Docker) | `kind delete cluster --name pf-dev && kind delete cluster --name pf-prod` | `kind get clusters` lists neither; `docker ps` shows no `pf-*` containers |

**Total incremental:** ~$0.05/month · **Threshold:** $2/month (flagship) · **Headroom:** ~$1.95/month

## Milestones

### M1: Secret-free bootstrap — Bicep creates the state backend and identities, and GitHub Actions reaches Azure through OIDC — `pending`
**Definition of done:**
- [ ] Repo tooling in place: pre-commit with `terraform fmt`/`validate`, `tflint` and `bicep lint`, and a Makefile (or task runner) with the documented entry points
- [ ] `rg-pf-bootstrap` (storage account, `id-pf-dev`, `id-pf-prod`, federated credentials, role assignments) is deployed from Bicep with one documented command
- [ ] A workflow in the `dev` environment logs in to Azure through OIDC and runs `terraform init` against the remote backend; the repo holds no Azure secrets (only client, tenant and subscription IDs as variables)
- [ ] Negative test: a job outside the allowed environment fails to get a token, and the failure is recorded in the docs
- [ ] The $2 budget alert exists
**Understanding targets:**
- Entra workload identity federation: token exchange, and how the subject claim ties trust to a GitHub environment
- Bicep deployment scopes and why the bootstrap sits outside Terraform (the chicken-and-egg state problem)
- The Terraform azurerm backend with Entra auth (`use_oidc`, `use_azuread_auth`) and blob-lease state locking

### M2: Terraform modules with gated promotion from dev to prod — `pending`
**Definition of done:**
- [ ] Reusable modules (at least environment resource group with tags, lock and least-privilege role assignment) consumed by the `envs/dev` and `envs/prod` roots, each with its own state key
- [ ] A PR that changes a module shows plans for both environments as PR comments
- [ ] Merging applies to dev automatically; prod applies only after an approval on the `prod` environment
- [ ] After apply, `terraform plan` shows no changes in both environments
**Understanding targets:**
- Module interface design (inputs, outputs, versioning) and state layout for each environment
- GitHub environment protection rules as a promotion gate
- Plan/apply separation: saved plan artifacts, and why prod applies the plan that was reviewed

### M3: Local clusters and GitOps — Argo CD syncs a sample service to kind dev and prod — `pending`
**Definition of done:**
- [ ] One command (`make up`) creates `pf-dev` and `pf-prod` from a clean machine with Terraform (local root, remote state) and installs Argo CD with Helm
- [ ] An app-of-apps in Git deploys a sample service's Helm chart to both clusters, with values for each environment; Argo CD shows `Synced`/`Healthy` in both
- [ ] Changing a value in Git redeploys it with no `kubectl apply`; `make down` removes both clusters, verified with `kind get clusters`
**Understanding targets:**
- Kubernetes workload basics and Helm chart authoring (templates, values for each environment)
- Argo CD's reconcile loop and the app-of-apps pattern
- Pull-based GitOps versus push-based CD (why CI never needs cluster credentials)

### M4: CI/CD as a platform — reusable workflows and promoting images by PR — `pending`
**Definition of done:**
- [ ] Reusable workflows (build/test/push to GHCR, Terraform plan/apply) are called by thin caller workflows, with no job logic duplicated
- [ ] A push to `main` builds an image, bumps the dev values to the image digest, and Argo CD syncs dev
- [ ] Promotion to prod is an automated PR that bumps the prod digest; merging it syncs prod
- [ ] A policy gate runs on Terraform plans (tf-prism, or tflint/Conftest if tf-prism isn't ready) and blocks a seeded violation
**Understanding targets:**
- Reusable workflows compared with composite actions: inputs, secrets inheritance, permissions
- Immutable artifacts: promoting by digest instead of by tag
- Policy gates in CI and where they sit in the promotion path

### M5: Delivery — `pending`
**Definition of done:**
- [ ] README, recording, case study, retro complete; teardown verified (standard) or live URL verified (flagship)
- [ ] Live evidence verified: public repo with recent green OIDC runs, and the cost to date in Azure Cost Management is at or under $2/month

## Checkpoint Log
<!-- portfolio-checkpoint appends entries:
### YYYY-MM-DD — M<n>
- **Done evidence:**
- **Understanding:** <target> → pass | gap | skipped
- **Cost to date:**
- **Adjustments:**
-->
