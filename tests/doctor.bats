setup() {
  load helpers
  setup_stubs
}

@test "doctor lists a missing tool and fails" {
  local t
  for t in az bicep terraform tflint pre-commit actionlint shellcheck gitleaks bats jq gh; do
    stub "$t" 'echo "stub 1.0"'
  done
  PATH="$STUB_BIN:/usr/bin:/bin" run "$REPO_ROOT/scripts/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING  zizmor"* ]]
  [[ "$output" == *"brew bundle"* ]]
}

@test "doctor passes when every tool is present" {
  local t
  for t in az bicep terraform tflint pre-commit actionlint zizmor shellcheck gitleaks bats jq gh; do
    stub "$t" 'echo "stub 1.0"'
  done
  PATH="$STUB_BIN:/usr/bin:/bin" run "$REPO_ROOT/scripts/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok       zizmor"* ]]
}
