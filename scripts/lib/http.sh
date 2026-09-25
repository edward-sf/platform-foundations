# shellcheck shell=bash
# Minimal HTTP helper. Source this file; it sets no shell options.

# http_request METHOD URL BODY_OUT [curl args...]
# Prints the HTTP status code ("000" if no response arrived); writes the body to BODY_OUT.
http_request() {
  local method=$1 url=$2 out=$3 code
  shift 3
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "$@" "$url" 2>/dev/null) || true
  printf '%s\n' "${code:-000}"
}
