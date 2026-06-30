#!/usr/bin/env bash
set -euo pipefail
#
# mirror.sh <name>
#
# Mirror a `kind: mirror` image from its upstream source to
# docker.io/rulebricks/<name>:<tag>, preserving the multi-arch manifest list and
# the upstream digests (no rebuild). Generalizes the proven `publish_image`
# primitive from scripts/publish-clickstack-images.sh.
#
# Looks the entry up in images/manifest.yaml, runs a digest-preserving copy via
# `docker buildx imagetools create`, then resolves and prints the pushed
# manifest-list digest and writes it to ${OUT_DIR:-/tmp}/<name>.digest.
#
# Env:
#   MANIFEST   path to images/manifest.yaml (default: <repo>/images/manifest.yaml)
#   OUT_DIR    where to write <name>.digest (default: /tmp)
#
# Requires: yq, docker (buildx). Registry logins are handled by the caller (CI).

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/images/common.sh
. "${_dir}/common.sh"

usage() {
  cat >&2 <<EOF
usage: ${0##*/} <name>

Mirror the manifest entry <name> (kind: mirror) to docker.io/rulebricks/<name>:<tag>,
preserving the multi-arch manifest list and digest. Writes the resolved digest to
\${OUT_DIR:-/tmp}/<name>.digest.
EOF
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  [ "$#" -eq 1 ] || { usage; die "exactly one argument (<name>) is required"; }

  local name="$1"
  require_cmd yq
  require_cmd docker
  require_manifest
  manifest_has "${name}" || die "no manifest entry named '${name}' in ${MANIFEST}"

  local kind tag source
  kind="$(manifest_field "${name}" kind)"
  tag="$(manifest_field "${name}" tag)"
  source="$(manifest_field "${name}" source)"

  [ "${kind}" = "mirror" ] || die "entry '${name}' has kind='${kind}', expected 'mirror' (use ${kind}.sh)"
  [ -n "${tag}" ] || die "entry '${name}' is missing required field: tag"
  [ -n "${source}" ] || die "entry '${name}' is missing required field: source"

  local source_ref target
  source_ref="${source}:${tag}"
  target="$(target_ref "${name}" "${tag}")"

  echo "==> mirror ${name}: ${source_ref} -> ${target}"
  docker buildx imagetools create -t "${target}" "${source_ref}"

  local digest
  digest="$(resolve_digest "${target}")"
  write_digest "${name}" "${digest}"
  echo "${digest}"
}

main "$@"
