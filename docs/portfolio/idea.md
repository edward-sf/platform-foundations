# Idea: platform-foundations

**Pitch:** A platform where every layer is code and a merged pull request is the only path to prod. Terraform and Bicep manage a small Azure footprint that GitHub Actions reaches through OIDC federation with no stored secrets. Argo CD runs GitOps on local kind clusters for dev and prod.

**Showcases:** Terraform authored end to end (modules, remote state in Azure Storage, promotion from dev to prod); Bicep; GitHub Actions → Azure authentication through Entra workload identity federation (OIDC, no stored secrets); reusable GitHub Actions workflows (CI/CD as a platform); Kubernetes (kind), Helm, GitOps with Argo CD (app-of-apps).

**Rationale:** Covers step 1 of the roadmap (platform foundations) in one project with one story. OIDC federation is the highest-signal item for cloud/platform roles and needs a real cloud, so a personal Azure subscription is used only for Entra federated credentials and state storage. That costs a few cents a month, within the flagship threshold. Compute stays local on kind to keep costs near zero. Azure and Entra match the user's work stack, and the Terraform modules can target AKS later, when a sandbox is available. tf-prism can serve as a plan gate in the pipeline, which gets that parked project working again.

## Scores
| Candidate | Showcase value | Cost fit | Demo-ability | Scope risk | Total |
|---|---|---|---|---|---|
| Hybrid Azure OIDC + local K8s | 3 | 2 (flagship-eligible, needs a personal subscription) | 3 | 2 | 10 |

## Rejected candidates
- Local platform (kind + Argo CD + R2 state) — scored highest, but can't prove OIDC federation; C is a superset of it now that a few cents a month of Azure is acceptable.
- Cloudflare as the cloud — no Kubernetes or GitOps, no OIDC, and it repeats much of what episent.ai shows.
- Agones game-server platform — the Terraform part is thin and scope risk is high; better as a later chapter for the game studio.
- Wildcard: carbon-aware batch platform — weaker proof of Terraform and CI/CD than the hybrid.
