#!/usr/bin/env bash
# Checks that every tool this repo needs is installed, and prints its version.

TOOLS="az bicep terraform tflint pre-commit actionlint zizmor shellcheck gitleaks bats jq gh"

version_of() {
  case "$1" in
    az) az version --query '"azure-cli"' -o tsv 2>/dev/null ;;
    terraform) terraform version 2>/dev/null | head -1 ;;
    gitleaks) gitleaks version 2>/dev/null ;;
    *) "$1" --version 2>&1 | head -1 ;;
  esac
}

main() {
  set -euo pipefail
  local t missing=""
  for t in $TOOLS; do
    if command -v "$t" >/dev/null 2>&1; then
      printf 'ok       %-11s %s\n' "$t" "$(version_of "$t")"
    else
      printf 'MISSING  %s\n' "$t"
      missing="$missing $t"
    fi
  done
  if [[ -n "$missing" ]]; then
    printf '\nmissing:%s. Install with: brew bundle (see the Brewfile comments for bicep and tflint)\n' "$missing"
    exit 1
  fi
}

main "$@"
