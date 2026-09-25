# Shared bats helpers. Load with: load helpers
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_ROOT

# Puts a stub directory first on PATH and starts an empty call log.
setup_stubs() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  STUB_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STUB_BIN" "$STUB_STATE"
  : > "$STUB_LOG"
  export PATH="$STUB_BIN:$PATH" STUB_LOG STUB_STATE
}

# stub NAME BODY: creates an executable NAME that appends "NAME args" (and its
# stdin, when called with "--input -") to $STUB_LOG, then runs BODY.
stub() {
  local name=$1 body=$2
  cat > "$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$name" "\$*" >> "\$STUB_LOG"
if [[ " \$* " == *" --input - "* ]]; then cat >> "\$STUB_LOG"; printf '\n' >> "\$STUB_LOG"; fi
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

# line_of PATTERN: first line number in $STUB_LOG containing PATTERN (empty if none).
line_of() { grep -n -m1 -F -- "$1" "$STUB_LOG" | cut -d: -f1; }
