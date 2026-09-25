#!/usr/bin/env bash
# Runs one OIDC lockdown proof case. Called by .github/workflows/oidc-proof.yml.
# Usage: scripts/proof.sh <claims|no-environment|cross-identity|cross-env-state|delegation-key|container-delete>
# Never prints a token: each token is masked the moment it is captured.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "$HERE/lib/http.sh"
# shellcheck source=scripts/lib/token.sh
source "$HERE/lib/token.sh"

STORAGE_API_VERSION="2023-11-03"
STORAGE_DENIED="AuthorizationPermissionMismatch"
ENTRA_DENIED="AADSTS700213"
JWT=""
ACCESS_TOKEN=""

# storage_request METHOD PATH TOKEN OUT [curl args...] -> HTTP status
storage_request() {
  local method=$1 path=$2 token=$3 out=$4
  shift 4
  http_request "$method" "https://${TF_STATE_ACCOUNT}.blob.core.windows.net${path}" "$out" \
    -H "Authorization: Bearer ${token}" \
    -H "x-ms-version: ${STORAGE_API_VERSION}" \
    -H "x-ms-date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
    "$@"
}

# iso_utc_in SECONDS: ISO-8601 UTC timestamp SECONDS from now (GNU or BSD date).
iso_utc_in() {
  local t=$(( $(date +%s) + $1 ))
  date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ
}

# Fetches this job's GitHub token into JWT, masks it, and logs its claims.
github_token() {
  JWT=$(gh_oidc_token)
  mask "$JWT"
  log "token claims: $(jwt_claims "$JWT")"
}

# storage_token_for CLIENT_ID: exchanges JWT for a storage token into ACCESS_TOKEN.
# A failed exchange means the proof itself is broken, so the job fails.
storage_token_for() {
  local client_id=$1 out="$WORK/token.json" code
  code=$(entra_token_request "$client_id" "$JWT" "$out")
  if [[ "$code" != "200" ]]; then
    die "positive control failed: token exchange for $client_id returned HTTP $code ($(jq -r '.error_description // "no description"' "$out" 2>/dev/null | head -c 300))"
  fi
  ACCESS_TOKEN=$(jq -r '.access_token' "$out")
  rm -f "$out"
  mask "$ACCESS_TOKEN"
}

# A dev token must list tfstate-dev before any denial counts.
dev_session() {
  require_env AZURE_CLIENT_ID_DEV TF_STATE_ACCOUNT
  github_token
  storage_token_for "$AZURE_CLIENT_ID_DEV"
  local code
  code=$(storage_request GET "/tfstate-dev?restype=container&comp=list" "$ACCESS_TOKEN" "$WORK/control.xml")
  [[ "$code" == "200" ]] || die "positive control failed: listing tfstate-dev returned HTTP $code"
  log "positive control: the dev token listed tfstate-dev (HTTP 200)"
}

assert_denied() { "$HERE/assert-denied.sh" "$@"; }

case_claims() {
  github_token
}

case_no_environment() {
  require_env AZURE_CLIENT_ID_DEV
  github_token
  local code
  code=$(entra_token_request "$AZURE_CLIENT_ID_DEV" "$JWT" "$WORK/deny.json")
  assert_denied --status "$code" --body-file "$WORK/deny.json" --expect-error "$ENTRA_DENIED"
}

case_cross_identity() {
  require_env AZURE_CLIENT_ID_PROD
  dev_session
  local code
  code=$(entra_token_request "$AZURE_CLIENT_ID_PROD" "$JWT" "$WORK/deny.json")
  assert_denied --status "$code" --body-file "$WORK/deny.json" --expect-error "$ENTRA_DENIED"
}

case_cross_env_state() {
  dev_session
  local code
  code=$(storage_request GET "/tfstate-prod?restype=container&comp=list" "$ACCESS_TOKEN" "$WORK/deny.xml")
  assert_denied --status "$code" --body-file "$WORK/deny.xml" --expect-status 403 --expect-error "$STORAGE_DENIED"
}

case_delegation_key() {
  dev_session
  local body code
  body="<?xml version=\"1.0\" encoding=\"utf-8\"?><KeyInfo><Start>$(iso_utc_in 0)</Start><Expiry>$(iso_utc_in 3600)</Expiry></KeyInfo>"
  code=$(storage_request POST "/?restype=service&comp=userdelegationkey" "$ACCESS_TOKEN" "$WORK/deny.xml" \
    -H "Content-Type: application/xml" --data "$body")
  assert_denied --status "$code" --body-file "$WORK/deny.xml" --expect-status 403 --expect-error "$STORAGE_DENIED"
}

case_container_delete() {
  dev_session
  local code
  code=$(storage_request DELETE "/tfstate-dev?restype=container" "$ACCESS_TOKEN" "$WORK/deny.xml")
  assert_denied --status "$code" --body-file "$WORK/deny.xml" --expect-status 403 --expect-error "$STORAGE_DENIED"
}

main() {
  set -euo pipefail
  [[ $# -eq 1 ]] || die "usage: proof.sh <claims|no-environment|cross-identity|cross-env-state|delegation-key|container-delete>"
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  case "$1" in
    claims) case_claims ;;
    no-environment) case_no_environment ;;
    cross-identity) case_cross_identity ;;
    cross-env-state) case_cross_env_state ;;
    delegation-key) case_delegation_key ;;
    container-delete) case_container_delete ;;
    *) die "unknown case: $1" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
