#!/usr/bin/env bash
set -euo pipefail
#
# sync.sh
#
# Iterate every entry in images/manifest.yaml, dispatch to mirror.sh / build.sh /
# external.sh by its `kind`, then collect all per-image <name>.digest fragments
# into images/digests.json — a flat { "<name>": "sha256:..." } object with
# deterministic (sorted) key order, suitable for committing and consuming by
# render-digests.sh.
#
# This is primarily a *local / one-shot* convenience (run everything in one
# process). In CI the matrixed mirror-images.yml runs mirror/build/external per
# entry in parallel and the `pin` job assembles digests.json from the uploaded
# artifacts via render-digests.sh — so sync.sh's collection step mirrors that
# assembly logic and both produce identical output.
#
# Env:
#   MANIFEST       path to images/manifest.yaml (default: <repo>/images/manifest.yaml)
#   OUT_DIR        where per-image <name>.digest land (default: /tmp)
#   DIGESTS_JSON   output path (default: <repo>/images/digests.json)
#
# Requires: yq, jq, docker (buildx).

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/images/common.sh
. "${_dir}/common.sh"

DIGESTS_JSON="${DIGESTS_JSON:-${REPO_ROOT}/images/digests.json}"

usage() {
  cat >&2 <<EOF
usage: ${0##*/}

Process every entry in ${MANIFEST}: dispatch mirror/build/external by kind, then
collect all \${OUT_DIR:-/tmp}/<name>.digest fragments into ${DIGESTS_JSON}
(deterministic key order).
EOF
}

# dispatch <name> — run the right sub-script for an entry's kind.
dispatch() {
  local name="$1" kind
  kind="$(manifest_field "${name}" kind)"
  case "${kind}" in
    mirror)   "${_dir}/mirror.sh" "${name}" ;;
    build)    "${_dir}/build.sh" "${name}" ;;
    external) "${_dir}/external.sh" "${name}" ;;
    "")       die "entry '${name}' is missing required field: kind" ;;
    *)        die "entry '${name}' has unknown kind '${kind}' (expected mirror|build|external)" ;;
  esac
}

# collect_digests — assemble images/digests.json from OUT_DIR/<name>.digest files.
# Deterministic: builds a {name,digest} stream then reduces to a sorted-key object.
# Names may contain hyphens, so we pass them as jq DATA (--arg), never as jq
# variable identifiers.
collect_digests() {
  local name digest
  local stream=""

  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    local frag="${OUT_DIR}/${name}.digest"
    [ -f "${frag}" ] || die "missing digest fragment for '${name}': ${frag}"
    digest="$(cat "${frag}")"
    [ -n "${digest}" ] || die "empty digest fragment for '${name}': ${frag}"
    case "${digest}" in
      sha256:*) : ;;
      *) die "digest fragment for '${name}' is not a sha256 ref: ${digest}" ;;
    esac
    # One compact JSON object per line; jq -s reduces them below.
    stream+="$(jq -cn --arg n "${name}" --arg d "${digest}" '{name:$n,digest:$d}')"$'\n'
  done < <(manifest_names)

  mkdir -p "$(dirname "${DIGESTS_JSON}")"
  # reduce the stream into a single object; --sort-keys -> deterministic order.
  printf '%s' "${stream}" \
    | jq -s --sort-keys 'reduce .[] as $e ({}; .[$e.name] = $e.digest)' \
    > "${DIGESTS_JSON}"
  echo "wrote ${DIGESTS_JSON}"
}

main() {
  if [ "$#" -gt 0 ]; then
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) usage; die "unexpected argument: $1" ;;
    esac
  fi

  require_cmd yq
  require_cmd jq
  require_cmd docker
  require_manifest

  local name
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    echo "=== sync ${name} ==="
    dispatch "${name}"
  done < <(manifest_names)

  collect_digests
}

main "$@"
