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
# match.
#
# Input: a rendered manifest of Kubernetes objects (helm template output) as $1 or
# on stdin. app/hps are exempt (pinned by product global.version, not the manifest).
#
# Requires: python3 only (no PyYAML — the manifest is parsed with a regex, and the
# render is read from a FILE, never passed via env/argv, so large renders are fine).

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_dir}/../.." && pwd)}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/images/manifest.yaml}"

# Resolve the rendered input to a FILE path (a large render must not go through
# env/argv — that's an E2BIG "Argument list too long").
src="${1:--}"
tmp=""
if [ "${src}" = "-" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "${tmp}"' EXIT
  cat > "${tmp}"
  RENDERED_FILE="${tmp}"
else
  RENDERED_FILE="${src}"
fi

MANIFEST="${MANIFEST}" RENDERED_FILE="${RENDERED_FILE}" python3 - <<'PY'
import os, re, sys

# Parse the manifest with a regex (flow-style one-entry-per-line dicts); avoids a
# hard PyYAML dependency on the CI runner.
expected = {}   # full rulebricks ref -> manifest name
count = 0
with open(os.environ["MANIFEST"]) as f:
    for line in f:
        s = line.strip()
        if not s.startswith("- {"):
            continue
        name = re.search(r'\bname:\s*([A-Za-z0-9._-]+)', s)
        tag = re.search(r'\btag:\s*"([^"]*)"', s)
        target = re.search(r'\btarget:\s*([A-Za-z0-9._/-]+)', s)
        if not name or not tag:
            continue
        nm, tg = name.group(1), tag.group(1)
        repo = target.group(1) if target else f"rulebricks/{nm}"
        expected[f"docker.io/{repo}:{tg}"] = nm
        count += 1

rendered = set()
with open(os.environ["RENDERED_FILE"]) as f:
    for line in f:
        m = re.search(r'image:\s*["\']?(docker\.io/rulebricks/[^"\'\s]+)', line)
        if m:
            rendered.add(m.group(1))

if not rendered:
    print("ERROR: no docker.io/rulebricks/* images found in the input — the upstream "
          "`helm template` likely failed or produced nothing (don't vacuously pass).",
          file=sys.stderr)
    sys.exit(1)

exempt = {r for r in rendered if re.match(r'docker\.io/rulebricks/(app|hps):', r)}
drift = sorted(rendered - set(expected) - exempt)

print(f"verify-versions: {len(rendered)} rulebricks images rendered "
      f"({len(exempt)} app/hps exempt); {count} manifest entries")
if drift:
    print("\nERROR: chart rendered images NOT produced by images/manifest.yaml "
          "(bump the manifest or fix the drifted chart/CLI tag):", file=sys.stderr)
    for d in drift:
        print(f"  - {d}", file=sys.stderr)
    sys.exit(1)
print("OK: every rendered rulebricks/* image matches a manifest entry at the same tag.")
PY
