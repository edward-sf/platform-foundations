# shellcheck shell=bash
# GitHub OIDC and Entra token helpers. Source after common.sh and http.sh.
# Functions that return tokens print them; callers capture and mask them at once.

GH_OIDC_AUDIENCE="api://AzureADTokenExchange"
STORAGE_SCOPE="https://storage.azure.com/.default"

# mask VALUE: hides VALUE in GitHub Actions logs. No-op elsewhere.
mask() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::add-mask::%s\n' "$1"
  fi
  return 0
}

# Prints this job's GitHub OIDC token (audience api://AzureADTokenExchange).
gh_oidc_token() {
  require_env ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN
  local out code
  out=$(mktemp)
  code=$(http_request GET "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${GH_OIDC_AUDIENCE}" "$out" \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}")
  if [[ "$code" != "200" ]]; then
    rm -f "$out"
    die "GitHub OIDC token request failed (HTTP $code); does the job grant id-token: write?"
  fi
  jq -r '.value' "$out"
  rm -f "$out"
}

# entra_token_request CLIENT_ID ASSERTION OUT
# Exchanges a GitHub token for a storage access token. Prints the HTTP status; JSON goes to OUT.
entra_token_request() {
  require_env AZURE_TENANT_ID
  http_request POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" "$3" \
    --data-urlencode "client_id=$1" \
    --data-urlencode "scope=${STORAGE_SCOPE}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=$2"
}

# jwt_claims JWT: prints the identifying claims of a JWT as compact JSON. Never prints the token.
jwt_claims() {
  local payload
  payload=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  while (( ${#payload} % 4 )); do payload="${payload}="; done
  printf '%s' "$payload" | base64 -d 2>/dev/null \
    | jq -c '{sub, aud, iss, environment, repository_id, repository_owner_id}'
}
