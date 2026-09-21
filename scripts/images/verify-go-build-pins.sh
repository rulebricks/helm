#!/usr/bin/env bash
set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${_dir}/../.." && pwd)"

failed=0
for dockerfile in "${repo_root}"/images/*/Dockerfile; do
  [ -f "${dockerfile}" ] || continue
  grep -Eq 'go (get|install)' "${dockerfile}" || continue

  matches="$(grep -n '@latest' "${dockerfile}" || true)"
  [ -z "${matches}" ] && continue

  echo "error: unpinned Go dependency in ${dockerfile#${repo_root}/}:" >&2
  printf '%s\n' "${matches}" >&2
  failed=1
done

if [ "${failed}" -ne 0 ]; then
  echo "error: Go image builds must use reviewed, exact module versions" >&2
  exit 1
fi

echo "OK: Go image builds contain no @latest dependency resolutions."
