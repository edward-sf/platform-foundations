#!/usr/bin/env bash
# Installs pinned CI tools into $RUNNER_TEMP/pf/bin, verifying each download's SHA-256.
# Usage: scripts/ci/install-tools.sh TOOL...   (tflint actionlint zizmor shellcheck bats bicep)

PREFIX="${RUNNER_TEMP:-/tmp}/pf"
BIN="$PREFIX/bin"

fetch() {
  local url=$1 sha=$2 out=$3
  curl -fsSL -o "$out" "$url"
  echo "$sha  $out" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $url" >&2; exit 1; }
}

install_one() {
  local tmp
  tmp=$(mktemp -d)
  case "$1" in
    tflint)
      fetch https://github.com/terraform-linters/tflint/releases/download/v0.64.0/tflint_linux_amd64.zip \
        cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537 "$tmp/tflint.zip"
      unzip -q -o "$tmp/tflint.zip" -d "$BIN" ;;
    actionlint)
      fetch https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz \
        8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 "$tmp/actionlint.tgz"
      tar -xzf "$tmp/actionlint.tgz" -C "$BIN" actionlint ;;
    zizmor)
      fetch https://github.com/zizmorcore/zizmor/releases/download/v1.30.1/zizmor-x86_64-unknown-linux-gnu.tar.gz \
        e65324f4430c2717591937edcec90ccbefaf14c174f8ec9415e03ca875b46e1a "$tmp/zizmor.tgz"
      tar -xzf "$tmp/zizmor.tgz" -C "$BIN" zizmor ;;
    shellcheck)
      fetch https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz \
        8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 "$tmp/shellcheck.txz"
      tar -xJf "$tmp/shellcheck.txz" -C "$tmp"
      mv "$tmp/shellcheck-v0.11.0/shellcheck" "$BIN/" ;;
    bats)
      fetch https://github.com/bats-core/bats-core/archive/refs/tags/v1.14.0.tar.gz \
        bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177 "$tmp/bats.tgz"
      tar -xzf "$tmp/bats.tgz" -C "$tmp"
      "$tmp/bats-core-1.14.0/install.sh" "$PREFIX" >/dev/null ;;
    bicep)
      fetch https://github.com/Azure/bicep/releases/download/v0.47.16/bicep-linux-x64 \
        64c345a58e0c3e48b1bc98a4e62d6b3adb1d238281297de3400aeafb2697aa5a "$BIN/bicep"
      chmod +x "$BIN/bicep" ;;
    *)
      echo "unknown tool: $1" >&2
      exit 2 ;;
  esac
  rm -rf "$tmp"
}

main() {
  set -euo pipefail
  mkdir -p "$BIN"
  local t
  for t in "$@"; do
    install_one "$t"
  done
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$BIN" >> "$GITHUB_PATH"
  fi
}

main "$@"
