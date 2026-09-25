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
