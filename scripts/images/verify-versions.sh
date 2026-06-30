#!/usr/bin/env bash
set -euo pipefail
#
# verify-versions.sh [rendered.yaml]
#
# Enforce that images/manifest.yaml is the SINGLE SOURCE OF TRUTH for image
# versions: every docker.io/rulebricks/* image the chart actually renders must
# correspond to exactly one manifest entry at the SAME tag. Fails (non-zero) on
# any chart image whose repo:tag is not produced by the manifest — i.e. the chart
# (or the CLI that fed it) drifted from the manifest.
#
# This is the guardrail behind "control versions in the manifest": bump a tag in
# images/manifest.yaml, and CI flags any chart/CLI value that wasn't updated to
# match (and the mirror job then publishes that tag + pins its digest into
# global.imageDigests, so prod runs exactly the manifest's version).
#
# Input: a rendered manifest of Kubernetes objects (helm template output) as $1 or
# on stdin. app/hps are exempt (pinned by product global.version, not the manifest).
#
# Requires: python3 (PyYAML), and the repo's images/manifest.yaml.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_dir}/../.." && pwd)}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/images/manifest.yaml}"

src="${1:--}"
if [ "${src}" = "-" ]; then
  rendered="$(cat)"
else
  rendered="$(cat "${src}")"
fi

MANIFEST="${MANIFEST}" RENDERED="${rendered}" python3 - <<'PY'
import os, re, sys, yaml
man = yaml.safe_load(open(os.environ["MANIFEST"]))
# expected: full rulebricks ref -> manifest name
expected = {}
for e in man["images"]:
    repo = e.get("target") or f"rulebricks/{e['name']}"
    expected[f"docker.io/{repo}:{e['tag']}"] = e["name"]

rendered = set()
for line in os.environ["RENDERED"].splitlines():
    m = re.search(r'image:\s*["\']?(docker\.io/rulebricks/[^"\'\s]+)', line)
    if m:
        rendered.add(m.group(1))

exempt = {r for r in rendered if re.match(r'docker\.io/rulebricks/(app|hps):', r)}
drift = sorted(rendered - set(expected) - exempt)

print(f"verify-versions: {len(rendered)} rulebricks images rendered "
      f"({len(exempt)} app/hps exempt); {len(man['images'])} manifest entries")
if drift:
    print("\nERROR: chart rendered images NOT produced by images/manifest.yaml "
          "(bump the manifest or fix the drifted chart/CLI tag):", file=sys.stderr)
    for d in drift:
        print(f"  - {d}", file=sys.stderr)
    sys.exit(1)
print("OK: every rendered rulebricks/* image matches a manifest entry at the same tag.")
PY
