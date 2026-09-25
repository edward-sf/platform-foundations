setup() {
  load helpers
  setup_stubs
  export PF_PROOF_POLL_TRIES=3 PF_PROOF_POLL_SECONDS=0
  stub gh '
case "$*" in
  "workflow run"*) touch "$STUB_STATE/dispatched" ;;
  "run list"*)
    if [[ -f "$STUB_STATE/dispatched" && -z "${NEW_RUN_NEVER_APPEARS:-}" ]]; then echo 101; else echo 100; fi ;;
  "run watch"*) exit 0 ;;
esac'
}

@test "watches the new run, not the previous one" {
  run "$REPO_ROOT/scripts/run-proof.sh"
  [ "$status" -eq 0 ]
  [ "$(line_of 'gh workflow run')" -lt "$(line_of 'gh run watch 101')" ]
  ! grep -q 'gh run watch 100' "$STUB_LOG"
}

@test "fails without watching anything when no new run appears" {
  export NEW_RUN_NEVER_APPEARS=1
  run "$REPO_ROOT/scripts/run-proof.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not appear"* ]]
  ! grep -q 'gh run watch' "$STUB_LOG"
}
