#!/usr/bin/env bash
# Dispatches oidc-proof.yml on main and watches that exact run, never an older one.
# Optional env: PF_PROOF_POLL_TRIES (default 30), PF_PROOF_POLL_SECONDS (default 2)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

latest_run_id() {
  gh run list --repo "$PF_REPO" --workflow oidc-proof.yml --event workflow_dispatch \
    --limit 1 --json databaseId --jq '.[0].databaseId // empty'
}

main() {
  set -euo pipefail
  require_cmd gh
  local before id="" i
  before=$(latest_run_id)
  gh workflow run oidc-proof.yml --repo "$PF_REPO" --ref main
  for (( i = 0; i < ${PF_PROOF_POLL_TRIES:-30}; i++ )); do
    id=$(latest_run_id)
    if [[ -n "$id" && "$id" != "$before" ]]; then break; fi
    sleep "${PF_PROOF_POLL_SECONDS:-2}"
  done
  [[ -n "$id" && "$id" != "$before" ]] || die "the new oidc-proof run did not appear; nothing watched"
  log "watching oidc-proof run $id"
  gh run watch "$id" --repo "$PF_REPO" --exit-status
}

main "$@"
