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
#       tag: "25.8.28-debian13"
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
# tags (postgres15/postgres16). Otherwise the repo defaults to <namespace>/<name>.
target_ref() {
  local name="$1" tag="$2" repo
  repo="$(manifest_field "${name}" target)"
  [ -n "${repo}" ] || repo="${TARGET_NAMESPACE}/${name}"
  printf '%s/%s:%s' "${TARGET_REGISTRY}" "${repo}" "${tag}"
}

# resolve_digest <ref> — print the multi-arch manifest-list digest of a pushed ref.
resolve_digest() {
  local ref="$1" digest
  digest="$(docker buildx imagetools inspect "${ref}" --format '{{.Manifest.Digest}}')"
  [ -n "${digest}" ] || die "could not resolve manifest digest for ${ref}"
  case "${digest}" in
    sha256:*) : ;;
    *) die "resolved digest for ${ref} is not a sha256 ref: ${digest}" ;;
  esac
  printf '%s' "${digest}"
}

# write_digest <name> <digest> — persist the resolved digest fragment + echo it.
write_digest() {
  local name="$1" digest="$2"
  mkdir -p "${OUT_DIR}"
  printf '%s' "${digest}" > "${OUT_DIR}/${name}.digest"
  echo "wrote ${OUT_DIR}/${name}.digest (${digest})"
}
