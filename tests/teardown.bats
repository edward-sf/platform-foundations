setup() {
  load helpers
  setup_stubs
  export EXPECTED_SUBSCRIPTION_ID=sub-1 EXPECTED_TENANT_ID=ten-1
  stub az '
case "$*" in
  "account show"*) echo "{\"id\":\"sub-1\",\"tenantId\":\"ten-1\"}" ;;
  "group exists"*) if [[ -f "$STUB_STATE/group-deleted" ]]; then echo false; else echo true; fi ;;
  "storage account list"*) if [[ ! -f "$STUB_STATE/group-deleted" ]]; then echo stpfabc; fi ;;
  "identity show"*) echo pid-1 ;;
  "role assignment list"*) echo /ra/1 ;;
  "role definition list"*) if [[ ! -f "$STUB_STATE/role-deleted" ]]; then echo /rd/1; fi ;;
  "role definition delete"*) touch "$STUB_STATE/role-deleted" ;;
  "group delete"*) if [[ -z "${GROUP_DELETE_NOOP:-}" ]]; then touch "$STUB_STATE/group-deleted"; fi ;;
  "consumption budget show"*) if [[ -f "$STUB_STATE/budget-deleted" ]]; then exit 1; else echo "{}"; fi ;;
  "consumption budget delete"*) touch "$STUB_STATE/budget-deleted" ;;
esac'
}

run_teardown() { run bash -c "printf '%s\n' '$1' | '$REPO_ROOT/scripts/teardown.sh'"; }

@test "deletes lock, assignments, role, group, then budget, in that order" {
  run_teardown y
  [ "$status" -eq 0 ]
  [ "$(line_of 'az lock delete')" -lt "$(line_of 'az role assignment delete')" ]
  [ "$(line_of 'az role assignment delete')" -lt "$(line_of 'az role definition delete')" ]
  [ "$(line_of 'az role definition delete')" -lt "$(line_of 'az group delete')" ]
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

@test "fails when the group survives deletion" {
  export GROUP_DELETE_NOOP=1
  run_teardown y
  [ "$status" -eq 1 ]
  [[ "$output" == *"teardown incomplete"* ]]
}
