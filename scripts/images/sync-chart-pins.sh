#!/usr/bin/env bash
set -euo pipefail
#
# sync-chart-pins.sh [--check]
#
# Sync every chart values pin listed in a manifest entry's `chartRefs` to that
# entry's `tag`. chartRefs is a space-separated list of <file>:<yaml.path>
# targets relative to the repo root. A target path may point at a bare tag
# value (updated to the entry tag) or a full image ref value like
# "docker.io/rulebricks/kafka-proxy:0.4.3-r1" (its tag part is updated).
#
# Edits are line-surgical (locate via yq, rewrite just the value) so file
# formatting, comments, and blank lines are untouched. Idempotent.
#
# --check: report drift without writing (exit 1 when out of sync).
#
# Requires: yq (mikefarah/yq v4).

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/images/common.sh
. "${_dir}/common.sh"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

require_cmd yq
require_manifest

drift=0 updated=0

sync_target() {
  local name="$1" tag="$2" file="$3" ypath="$4"
  local abs="${REPO_ROOT}/${file}"
  [ -f "${abs}" ] || die "${name}: chartRefs file not found: ${file}"

  local lineno current
  lineno="$(yq ".${ypath} | line" "${abs}")"
  current="$(yq -r ".${ypath} // \"\"" "${abs}")"
  { [ -n "${lineno}" ] && [ "${lineno}" != "0" ] && [ -n "${current}" ]; } \
    || die "${name}: chartRefs path not found: ${file}:${ypath}"

  # Full image refs keep their repo; only the tag part moves.
  local desired="${tag}"
  case "${current}" in
    */*:*) desired="${current%:*}:${tag}" ;;
  esac
  [ "${current}" = "${desired}" ] && return 0

  if [ "${CHECK}" = "1" ]; then
    echo "drift: ${file}:${ypath} = ${current} (manifest ${name} -> ${desired})"
    drift=1
    return 0
  fi

  local old_line new_line
  old_line="$(sed -n "${lineno}p" "${abs}")"
  # NB: replacement must be unquoted (macOS bash 3.2 keeps literal quotes).
  new_line=${old_line/"${current}"/${desired}}
  [ "${new_line}" != "${old_line}" ] || die "${name}: could not rewrite ${file}:${lineno} (${ypath})"
  awk -v n="${lineno}" -v repl="${new_line}" 'NR==n{print repl; next}{print}' "${abs}" > "${abs}.tmp" \
    && mv "${abs}.tmp" "${abs}"
  echo "synced ${file}:${ypath} -> ${desired}"
  updated=$((updated + 1))
}

for name in $(manifest_names); do
  refs="$(manifest_field "${name}" chartRefs)"
  [ -n "${refs}" ] || continue
  tag="$(manifest_field "${name}" tag)"
  [ -n "${tag}" ] || die "entry '${name}' has chartRefs but no tag"
  for target in ${refs}; do
    sync_target "${name}" "${tag}" "${target%%:*}" "${target#*:}"
  done
done

if [ "${CHECK}" = "1" ]; then
  [ "${drift}" = "0" ] && echo "OK: all chart pins match the manifest."
  exit "${drift}"
fi
echo "done (${updated} pin(s) updated)."
