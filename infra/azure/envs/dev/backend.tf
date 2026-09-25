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
