# shellcheck shell=bash
#
# common.sh — shared helpers for the scripts/images/* image-mirror toolkit.
#
# This file is *sourced* (not executed) by mirror.sh / build.sh / external.sh /
# sync.sh / render-digests.sh. It centralizes:
#   - repo-root + manifest path resolution
#   - the manifest schema accessors (via yq)
#   - the digest-write helper (writes ${OUT_DIR}/<name>.digest)
#   - the digest-resolve primitive (manifest-list digest of a pushed ref)
#
# Single source of truth: images/manifest.yaml (authored by another worker).
# Schema, one list item per image:
#   images:
#     - name: clickhouse-server          # target = docker.io/rulebricks/<name>
#       kind: mirror                     # mirror | build | external
#       source: dhi.io/clickhouse-server # full source ref WITHOUT tag (mirror/build base)
#       tag: "26.6.1-debian13"
#       auth: dhi                        # dhi | quay | dockerhub | none
#       context: images/hyperdx          # only for kind: build
#       base: dhi.io/node:22             # only for kind: build
#       digest: ""                       # written back by render-digests.sh
#
# Requires: yq (mikefarah/yq v4), docker (with buildx). Installed in CI.

# Target image namespace. Every rulebricks image lives at docker.io/rulebricks/<name>.
TARGET_REGISTRY="${TARGET_REGISTRY:-docker.io}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-rulebricks}"

# Resolve the helm repo root (two levels up from scripts/images/).
_images_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_images_common_dir}/../.." && pwd)}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/images/manifest.yaml}"

# Where per-image <name>.digest fragments are written. CI uploads these as artifacts.
OUT_DIR="${OUT_DIR:-/tmp}"

# Docker Hub can briefly return 5xx responses while a newly pushed manifest and
# its blobs propagate through the registry CDN. Keep digest lookup retries
# bounded and configurable so callers can tune CI without changing the scripts.
DIGEST_RESOLVE_ATTEMPTS="${DIGEST_RESOLVE_ATTEMPTS:-6}"
DIGEST_RETRY_INITIAL_DELAY_SECONDS="${DIGEST_RETRY_INITIAL_DELAY_SECONDS:-5}"
DIGEST_RETRY_MAX_DELAY_SECONDS="${DIGEST_RETRY_MAX_DELAY_SECONDS:-30}"

# Registry authentication and manifest-copy operations are short and
# idempotent, but the public registries occasionally return transport timeouts,
# 429s, or 5xx responses. Retry only those transient failures; permanent
# credentials/authorization errors and build failures must remain fail-fast.
REGISTRY_RETRY_ATTEMPTS="${REGISTRY_RETRY_ATTEMPTS:-4}"
REGISTRY_RETRY_INITIAL_DELAY_SECONDS="${REGISTRY_RETRY_INITIAL_DELAY_SECONDS:-3}"
REGISTRY_RETRY_MAX_DELAY_SECONDS="${REGISTRY_RETRY_MAX_DELAY_SECONDS:-30}"
REGISTRY_RETRY_JITTER_SECONDS="${REGISTRY_RETRY_JITTER_SECONDS:-3}"

# die <message...> — print to stderr and exit non-zero.
die() {
  echo "error: $*" >&2
  exit 1
}

# require_cmd <cmd> — fail with a helpful message if a tool is missing.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found on PATH: $1"
}

# require_manifest — ensure the manifest exists before we read it.
require_manifest() {
  [ -f "${MANIFEST}" ] || die "manifest not found: ${MANIFEST} (set MANIFEST=... to override)"
}

# manifest_has <name> — exit 0 if an entry with this name exists.
manifest_has() {
  local name="$1"
  local found
  found="$(yq -r ".images[] | select(.name == \"${name}\") | .name" "${MANIFEST}")"
  [ -n "${found}" ] && [ "${found}" != "null" ]
}

# manifest_field <name> <field> — print a scalar field of an entry, or empty.
# Returns empty string (not the literal "null") when the field is absent.
manifest_field() {
  local name="$1" field="$2" value
  value="$(yq -r ".images[] | select(.name == \"${name}\") | .${field} // \"\"" "${MANIFEST}")"
  [ "${value}" = "null" ] && value=""
  printf '%s' "${value}"
}

# manifest_names — print every entry name, one per line, in manifest order.
manifest_names() {
  yq -r '.images[].name' "${MANIFEST}"
}

# target_ref <name> <tag> — compose the target ref docker.io/rulebricks/<repo>:<tag>.
# A manifest entry may set an explicit `target:` repo path (namespace + name, e.g.
# `target: rulebricks/postgres`) when several entries share one repo under different
# tags (postgres15/16/17). Otherwise the repo defaults to <namespace>/<name>.
target_ref() {
  local name="$1" tag="$2" repo
  repo="$(manifest_field "${name}" target)"
  [ -n "${repo}" ] || repo="${TARGET_NAMESPACE}/${name}"
  printf '%s/%s:%s' "${TARGET_REGISTRY}" "${repo}" "${tag}"
}

# is_transient_registry_error <output> — recognize errors that are safe to
# retry. Explicit authentication/authorization failures always win, even if a
# registry happens to include another retry-looking phrase in its response.
is_transient_registry_error() {
  local output="$1"

  if printf '%s\n' "${output}" | grep -Eiq \
    '(^|[^[:digit:]])(401|403)([^[:digit:]]|$)|unauthorized|authentication required|requested access to the resource is denied|denied:'; then
    return 1
  fi

  printf '%s\n' "${output}" | grep -Eiq \
    'context deadline exceeded|client\.timeout|i/o timeout|tls handshake timeout|connection (reset|refused|timed out)|net/http: request canceled|temporary failure|no such host|server misbehaving|unexpected eof|(^|[^[:alpha:]])eof([^[:alpha:]]|$)|too many requests|toomanyrequests|unexpected status.*(408|429|5[0-9]{2})|status( code)?[^[:digit:]]*(408|429|5[0-9]{2})|http[^[:digit:]]*(408|429|5[0-9]{2})|service unavailable|bad gateway|gateway timeout|internal server error'
}

# retry_registry <description> <command...> — run an idempotent registry
# operation with bounded exponential backoff and jitter. Command output is
# emitted after every attempt so the final CI log retains the original error.
retry_registry() {
  local description="$1"
  shift
  [ "$#" -gt 0 ] || die "retry_registry requires a command"

  case "${REGISTRY_RETRY_ATTEMPTS}" in
    ''|*[!0-9]*|0) die "REGISTRY_RETRY_ATTEMPTS must be a positive integer" ;;
  esac
  case "${REGISTRY_RETRY_INITIAL_DELAY_SECONDS}" in
    ''|*[!0-9]*) die "REGISTRY_RETRY_INITIAL_DELAY_SECONDS must be a non-negative integer" ;;
  esac
  case "${REGISTRY_RETRY_MAX_DELAY_SECONDS}" in
    ''|*[!0-9]*) die "REGISTRY_RETRY_MAX_DELAY_SECONDS must be a non-negative integer" ;;
  esac
  case "${REGISTRY_RETRY_JITTER_SECONDS}" in
    ''|*[!0-9]*) die "REGISTRY_RETRY_JITTER_SECONDS must be a non-negative integer" ;;
  esac

  local attempt=1 delay="${REGISTRY_RETRY_INITIAL_DELAY_SECONDS}"
  local output status jitter wait
  if [ "${delay}" -gt "${REGISTRY_RETRY_MAX_DELAY_SECONDS}" ]; then
    delay="${REGISTRY_RETRY_MAX_DELAY_SECONDS}"
  fi

  while [ "${attempt}" -le "${REGISTRY_RETRY_ATTEMPTS}" ]; do
    if output="$("$@" 2>&1)"; then
      [ -z "${output}" ] || printf '%s\n' "${output}"
      return 0
    else
      status=$?
    fi
    [ -z "${output}" ] || printf '%s\n' "${output}" >&2

    if [ "${attempt}" -eq "${REGISTRY_RETRY_ATTEMPTS}" ] \
      || ! is_transient_registry_error "${output}"; then
      return "${status}"
    fi

    jitter=0
    if [ "${REGISTRY_RETRY_JITTER_SECONDS}" -gt 0 ]; then
      jitter=$((RANDOM % (REGISTRY_RETRY_JITTER_SECONDS + 1)))
    fi
    wait=$((delay + jitter))
    echo "warning: ${description} failed transiently (attempt ${attempt}/${REGISTRY_RETRY_ATTEMPTS}); retrying in ${wait}s" >&2
    sleep "${wait}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
    if [ "${delay}" -gt "${REGISTRY_RETRY_MAX_DELAY_SECONDS}" ]; then
      delay="${REGISTRY_RETRY_MAX_DELAY_SECONDS}"
    fi
  done
}

_docker_login() {
  local registry="$1" username="$2" password="$3"
  printf '%s' "${password}" | docker login "${registry}" \
    --username "${username}" --password-stdin
}

# docker_login_with_retry <registry> <username> <password>
docker_login_with_retry() {
  local registry="$1" username="$2" password="$3"
  retry_registry "login to ${registry}" \
    _docker_login "${registry}" "${username}" "${password}"
}

# resolve_digest <ref> — print the multi-arch manifest-list digest of a pushed ref.
resolve_digest() {
  local ref="$1" digest=""
  local attempt=1 delay="${DIGEST_RETRY_INITIAL_DELAY_SECONDS}"

  case "${DIGEST_RESOLVE_ATTEMPTS}" in
    ''|*[!0-9]*|0) die "DIGEST_RESOLVE_ATTEMPTS must be a positive integer" ;;
  esac
  case "${DIGEST_RETRY_INITIAL_DELAY_SECONDS}" in
    ''|*[!0-9]*) die "DIGEST_RETRY_INITIAL_DELAY_SECONDS must be a non-negative integer" ;;
  esac
  case "${DIGEST_RETRY_MAX_DELAY_SECONDS}" in
    ''|*[!0-9]*) die "DIGEST_RETRY_MAX_DELAY_SECONDS must be a non-negative integer" ;;
  esac
  if [ "${delay}" -gt "${DIGEST_RETRY_MAX_DELAY_SECONDS}" ]; then
    delay="${DIGEST_RETRY_MAX_DELAY_SECONDS}"
  fi

  while [ "${attempt}" -le "${DIGEST_RESOLVE_ATTEMPTS}" ]; do
    if digest="$(docker buildx imagetools inspect "${ref}" --format '{{.Manifest.Digest}}')" \
      && [ -n "${digest}" ]; then
      case "${digest}" in
        sha256:*) printf '%s' "${digest}"; return 0 ;;
        *) die "resolved digest for ${ref} is not a sha256 ref: ${digest}" ;;
      esac
    fi

    if [ "${attempt}" -eq "${DIGEST_RESOLVE_ATTEMPTS}" ]; then
      break
    fi

    echo "warning: digest lookup for ${ref} failed (attempt ${attempt}/${DIGEST_RESOLVE_ATTEMPTS}); retrying in ${delay}s" >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
    if [ "${delay}" -gt "${DIGEST_RETRY_MAX_DELAY_SECONDS}" ]; then
      delay="${DIGEST_RETRY_MAX_DELAY_SECONDS}"
    fi
  done

  die "could not resolve manifest digest for ${ref} after ${DIGEST_RESOLVE_ATTEMPTS} attempts"
}

# write_digest <name> <digest> — persist the resolved digest fragment + echo it.
write_digest() {
  local name="$1" digest="$2"
  mkdir -p "${OUT_DIR}"
  printf '%s' "${digest}" > "${OUT_DIR}/${name}.digest"
  echo "wrote ${OUT_DIR}/${name}.digest (${digest})"
}
