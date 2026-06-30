#!/usr/bin/env bash
set -euo pipefail
#
# build.sh <name>
#
# Build a `kind: build` image from its local Docker build context and push it to
# docker.io/rulebricks/<name>:<tag> as a multi-arch manifest list, then resolve
# and print the pushed manifest-list digest (written to
# ${OUT_DIR:-/tmp}/<name>.digest).
#
# Env:
#   MANIFEST   path to images/manifest.yaml (default: <repo>/images/manifest.yaml)
#   OUT_DIR    where to write <name>.digest (default: /tmp)
#   PLATFORMS  build platforms (default: linux/amd64,linux/arm64)
#
# Requires: yq, docker (buildx). Registry logins handled by the caller (CI).

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/images/common.sh
. "${_dir}/common.sh"

PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

usage() {
  cat >&2 <<EOF
usage: ${0##*/} <name>

Build the manifest entry <name> (kind: build) from its 'context' and push to
docker.io/rulebricks/<name>:<tag> for platforms ${PLATFORMS}. Writes the resolved
digest to \${OUT_DIR:-/tmp}/<name>.digest.
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

  local kind tag context base
  kind="$(manifest_field "${name}" kind)"
  tag="$(manifest_field "${name}" tag)"
  context="$(manifest_field "${name}" context)"
  base="$(manifest_field "${name}" base)"

  [ "${kind}" = "build" ] || die "entry '${name}' has kind='${kind}', expected 'build' (use ${kind}.sh)"
  [ -n "${tag}" ] || die "entry '${name}' is missing required field: tag"
  [ -n "${context}" ] || die "entry '${name}' (kind: build) is missing required field: context"

  # Resolve context relative to repo root when not absolute.
  case "${context}" in
    /*) : ;;
    *) context="${REPO_ROOT}/${context}" ;;
  esac
  [ -d "${context}" ] || die "build context directory does not exist: ${context}"

  local target build_args=()
  target="$(target_ref "${name}" "${tag}")"
  # 'base' (DHI base image) is optional; pass it as a build-arg so the Dockerfile
  # can do `ARG BASE_IMAGE` / `FROM ${BASE_IMAGE}` if it wants to.
  [ -n "${base}" ] && build_args+=(--build-arg "BASE_IMAGE=${base}")

  echo "==> build ${name}: context=${context} -> ${target} (${PLATFORMS})"
  docker buildx build \
    --platform "${PLATFORMS}" \
    --push \
    -t "${target}" \
    "${build_args[@]}" \
    "${context}"

  local digest
  digest="$(resolve_digest "${target}")"
  write_digest "${name}" "${digest}"
  echo "${digest}"
}

main "$@"
