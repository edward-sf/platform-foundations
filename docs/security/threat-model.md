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
