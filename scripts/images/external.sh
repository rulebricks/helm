#!/usr/bin/env bash
set -euo pipefail
#
# external.sh <name>
#
# For a `kind: external` image: the image is built and published by a *different*
# repo (e.g. the app / hps build pipelines), so this script does NOT mirror or
# build anything. It simply resolves the digest of the already-published
# docker.io/rulebricks/<name>:<tag> and records it (write-back / audit) into
# ${OUT_DIR:-/tmp}/<name>.digest so the pin step can pin it like everything else.
#
# Env:
#   MANIFEST   path to images/manifest.yaml (default: <repo>/images/manifest.yaml)
#   OUT_DIR    where to write <name>.digest (default: /tmp)
#
# Requires: yq, docker (buildx). Read access to the target ref (CI login).

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/images/common.sh
. "${_dir}/common.sh"

usage() {
  cat >&2 <<EOF
usage: ${0##*/} <name>

Resolve the digest of the already-published docker.io/rulebricks/<name>:<tag>
(manifest entry <name>, kind: external — built by another repo) and write it to
\${OUT_DIR:-/tmp}/<name>.digest. Does not mirror or build.
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

  local kind tag
  kind="$(manifest_field "${name}" kind)"
  tag="$(manifest_field "${name}" tag)"

  [ "${kind}" = "external" ] || die "entry '${name}' has kind='${kind}', expected 'external' (use ${kind}.sh)"
  [ -n "${tag}" ] || die "entry '${name}' is missing required field: tag"

  local target
  target="$(target_ref "${name}" "${tag}")"

  echo "==> external ${name}: resolving published digest for ${target}"
  local digest
  digest="$(resolve_digest "${target}")"
  write_digest "${name}" "${digest}"
  echo "${digest}"
}

main "$@"
