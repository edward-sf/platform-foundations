setup() {
  load helpers
  setup_stubs
  export EXPECTED_SUBSCRIPTION_ID=sub-1 EXPECTED_TENANT_ID=ten-1
  stub az '
notfound() { echo "ERROR: ($1) $2" >&2; exit 1; }
case "$*" in
  "account show"*) echo "{\"id\":\"sub-1\",\"tenantId\":\"ten-1\"}" ;;
  "group exists"*) if [[ -f "$STUB_STATE/group-deleted" ]]; then echo false; else echo true; fi ;;
  "storage account list"*) if [[ -f "$STUB_STATE/group-deleted" ]]; then notfound ResourceGroupNotFound "Resource group could not be found."; else echo stpfabc; fi ;;
  "lock delete"*) if [[ -n "${LOCK_ERROR:-}" ]]; then echo "ERROR: (AuthorizationFailed) denied" >&2; exit 1; fi ;;
  "identity show"*) if [[ -f "$STUB_STATE/group-deleted" ]]; then notfound ResourceGroupNotFound "Resource group could not be found."; else echo pid-1; fi ;;
  "role assignment list"*) echo /ra/1 ;;
  "deployment sub show"*) echo /subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/abc ;;
  "rest --method get"*) if [[ -f "$STUB_STATE/role-deleted" ]]; then notfound RoleDefinitionDoesNotExist "The role definition does not exist."; else echo /subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/abc; fi ;;
  "rest --method delete"*) touch "$STUB_STATE/role-deleted" ;;
  "group delete"*) if [[ -z "${GROUP_DELETE_NOOP:-}" ]]; then touch "$STUB_STATE/group-deleted"; fi ;;
  "consumption budget show"*)
    if [[ -n "${BUDGET_ERROR:-}" ]]; then echo "ERROR: (TooManyRequests) throttled" >&2; exit 1
    elif [[ -f "$STUB_STATE/budget-deleted" ]]; then notfound 404 "Budget not found."
    else echo pf-budget; fi ;;
  "consumption budget delete"*) touch "$STUB_STATE/budget-deleted" ;;
esac'
}

run_teardown() { run bash -c "printf '%s\n' '$1' | '$REPO_ROOT/scripts/teardown.sh'"; }

@test "deletes lock, assignments, role, group, then budget, in that order" {
  run_teardown y
  [ "$status" -eq 0 ]
  [ "$(line_of 'az lock delete')" -lt "$(line_of 'az role assignment delete')" ]
  [ "$(line_of 'az role assignment delete')" -lt "$(line_of 'az rest --method delete')" ]
  [ "$(line_of 'az rest --method delete')" -lt "$(line_of 'az group delete')" ]
  [ "$(line_of 'az group delete')" -lt "$(line_of 'az consumption budget delete')" ]
  [[ "$output" == *"teardown verified"* ]]
}

@test "answering no deletes nothing" {
  run_teardown n
  [ "$status" -eq 1 ]
  ! grep -q ' delete' "$STUB_LOG"
}

@test "refuses to run against another subscription" {
  export EXPECTED_SUBSCRIPTION_ID=other-sub
  run_teardown y
  [ "$status" -eq 1 ]
  ! grep -q ' delete' "$STUB_LOG"
}

@test "is safe to re-run after everything is gone" {
  touch "$STUB_STATE/group-deleted" "$STUB_STATE/role-deleted" "$STUB_STATE/budget-deleted"
  run_teardown y
  [ "$status" -eq 0 ]
  [ -z "$(line_of 'az group delete')" ]
  [[ "$output" == *"teardown verified"* ]]
}

@test "deletes the custom role even when the group is already gone" {
  touch "$STUB_STATE/group-deleted"
  run_teardown y
  [ "$status" -eq 0 ]
  [ -n "$(line_of 'az rest --method delete')" ]
  [[ "$output" == *"ok: custom role gone"* ]]
}

@test "fails when the group survives deletion" {
  export GROUP_DELETE_NOOP=1
  run_teardown y
  [ "$status" -eq 1 ]
  [[ "$output" == *"teardown incomplete"* ]]
}

@test "a budget lookup error fails instead of reading as gone" {
  export BUDGET_ERROR=1
  run_teardown y
  [ "$status" -eq 1 ]
  [[ "$output" == *"TooManyRequests"* ]]
  [[ "$output" != *"ok: pf-budget gone"* ]]
}

@test "a real lock-delete error stops teardown before the group is deleted" {
  export LOCK_ERROR=1
  run_teardown y
  [ "$status" -eq 1 ]
  [[ "$output" == *"AuthorizationFailed"* ]]
  [ -z "$(line_of 'az group delete')" ]
}
