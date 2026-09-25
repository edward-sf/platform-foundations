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
