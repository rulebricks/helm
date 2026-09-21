#!/usr/bin/env bash
set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/images/common.sh
. "${_dir}/common.sh"

REGISTRY_RETRY_ATTEMPTS=3
REGISTRY_RETRY_INITIAL_DELAY_SECONDS=0
REGISTRY_RETRY_MAX_DELAY_SECONDS=0
REGISTRY_RETRY_JITTER_SECONDS=0

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

mock="${tmpdir}/mock-registry-command"
cat > "${mock}" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

count=0
[ ! -f "${MOCK_COUNTER}" ] || count="$(cat "${MOCK_COUNTER}")"
count=$((count + 1))
printf '%s' "${count}" > "${MOCK_COUNTER}"

case "${MOCK_MODE}" in
  503)
    [ "${count}" -ge 3 ] && { echo "ok"; exit 0; }
    echo "unexpected status from POST request: 503 Service Unavailable" >&2
    exit 1
    ;;
  timeout)
    [ "${count}" -ge 2 ] && { echo "ok"; exit 0; }
    echo "context deadline exceeded (Client.Timeout exceeded while awaiting headers)" >&2
    exit 1
    ;;
  401)
    echo "unauthorized: authentication required (401)" >&2
    exit 1
    ;;
  compiler)
    echo "main.go:10:2: undefined: missingSymbol" >&2
    exit 1
    ;;
  *)
    echo "unknown mock mode: ${MOCK_MODE}" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "${mock}"

assert_attempts() {
  local expected="$1" actual
  actual="$(cat "${MOCK_COUNTER}")"
  [ "${actual}" = "${expected}" ] \
    || die "mock mode ${MOCK_MODE}: expected ${expected} attempt(s), got ${actual}"
}

run_success_case() {
  local mode="$1" expected="$2"
  export MOCK_MODE="${mode}"
  export MOCK_COUNTER="${tmpdir}/${mode}.count"
  retry_registry "mock ${mode}" "${mock}" >/dev/null
  assert_attempts "${expected}"
}

run_failure_case() {
  local mode="$1"
  export MOCK_MODE="${mode}"
  export MOCK_COUNTER="${tmpdir}/${mode}.count"
  if retry_registry "mock ${mode}" "${mock}" >/dev/null 2>&1; then
    die "mock mode ${mode}: expected command to fail"
  fi
  assert_attempts 1
}

run_success_case 503 3
run_success_case timeout 2
run_failure_case 401
run_failure_case compiler

echo "OK: registry retry policy handles transient and permanent failures."
