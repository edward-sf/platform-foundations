# M1 manages no resources; M2 adds them. The dev identity has no control-plane
# rights yet, so the provider must not try to register resource providers.
provider "azurerm" {
  features {}
  use_oidc                        = true
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}
