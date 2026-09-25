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
