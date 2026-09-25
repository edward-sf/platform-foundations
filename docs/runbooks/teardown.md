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
