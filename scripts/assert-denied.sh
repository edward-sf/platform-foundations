#!/usr/bin/env bash
# Passes only when a request was denied with the expected status and error code.
# Usage: assert-denied.sh --status CODE --body-file FILE --expect-error TEXT [--expect-status CODE]

usage() {
  echo "usage: assert-denied.sh --status CODE --body-file FILE --expect-error TEXT [--expect-status CODE]" >&2
  exit 2
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

main() {
  set -euo pipefail
  local status="" body_file="" expect_error="" expect_status=""
  while (( $# )); do
    case "$1" in
      --status) status=${2:-}; shift 2 || usage ;;
      --body-file) body_file=${2:-}; shift 2 || usage ;;
      --expect-error) expect_error=${2:-}; shift 2 || usage ;;
      --expect-status) expect_status=${2:-}; shift 2 || usage ;;
      *) usage ;;
    esac
  done
  [[ -n "$status" && -n "$body_file" && -n "$expect_error" ]] || usage

  [[ "$status" =~ ^[0-9]{3}$ ]] || fail "no HTTP status recorded (got '$status')"
  [[ "$status" != "000" ]] || fail "no response (transport failure)"
  [[ "$status" != 2* ]] || fail "expected a denial, but the request succeeded with HTTP $status"
  if [[ -n "$expect_status" && "$status" != "$expect_status" ]]; then
    fail "expected HTTP $expect_status, got HTTP $status"
  fi
  [[ -f "$body_file" ]] || fail "body file not found: $body_file"
  grep -qF -- "$expect_error" "$body_file" \
    || fail "HTTP $status, but the body lacks '$expect_error': $(head -c 300 "$body_file")"
  printf 'PASS: denied with HTTP %s and %s\n' "$status" "$expect_error"
}

main "$@"
