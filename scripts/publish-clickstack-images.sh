#!/usr/bin/env bash
set -euo pipefail

# Republishes the external images used by the local ClickStack subchart under
# docker.io/rulebricks as multi-arch manifest lists. This keeps private installs
# pulling from the same image namespace while preserving upstream digests.

HYPERDX_SOURCE_IMAGE="${HYPERDX_SOURCE_IMAGE:-docker.hyperdx.io/hyperdx/hyperdx}"
HYPERDX_TARGET_IMAGE="${HYPERDX_TARGET_IMAGE:-docker.io/rulebricks/hyperdx}"
HYPERDX_TAG="${HYPERDX_TAG:-2.19.0}"

CLICKSTACK_OTEL_COLLECTOR_SOURCE_IMAGE="${CLICKSTACK_OTEL_COLLECTOR_SOURCE_IMAGE:-docker.clickhouse.com/clickhouse/clickstack-otel-collector}"
CLICKSTACK_OTEL_COLLECTOR_TARGET_IMAGE="${CLICKSTACK_OTEL_COLLECTOR_TARGET_IMAGE:-docker.io/rulebricks/clickstack-otel-collector}"
CLICKSTACK_OTEL_COLLECTOR_TAG="${CLICKSTACK_OTEL_COLLECTOR_TAG:-2.19.0}"

FERRETDB_SOURCE_IMAGE="${FERRETDB_SOURCE_IMAGE:-ghcr.io/ferretdb/ferretdb}"
FERRETDB_TARGET_IMAGE="${FERRETDB_TARGET_IMAGE:-docker.io/rulebricks/ferretdb}"
FERRETDB_TAG="${FERRETDB_TAG:-2.7.0}"

POSTGRES_DOCUMENTDB_SOURCE_IMAGE="${POSTGRES_DOCUMENTDB_SOURCE_IMAGE:-ghcr.io/ferretdb/postgres-documentdb}"
POSTGRES_DOCUMENTDB_TARGET_IMAGE="${POSTGRES_DOCUMENTDB_TARGET_IMAGE:-docker.io/rulebricks/postgres-documentdb}"
POSTGRES_DOCUMENTDB_TAG="${POSTGRES_DOCUMENTDB_TAG:-17-0.107.0-ferretdb-2.7.0}"

publish_image() {
  local source_ref="$1"
  local target_ref="$2"
  local manifest_prefix="$3"

  echo "Inspecting source image: ${source_ref}"
  docker buildx imagetools inspect "${source_ref}" | tee "/tmp/${manifest_prefix}-source-manifest.txt"

  if ! grep -q "Platform:.*linux/amd64" "/tmp/${manifest_prefix}-source-manifest.txt"; then
    echo "Source image is missing linux/amd64: ${source_ref}" >&2
    exit 1
  fi

  if ! grep -q "Platform:.*linux/arm64" "/tmp/${manifest_prefix}-source-manifest.txt"; then
    echo "Source image is missing linux/arm64: ${source_ref}" >&2
    exit 1
  fi

  echo "Publishing multi-arch manifest: ${target_ref}"
  docker buildx imagetools create -t "${target_ref}" "${source_ref}"

  echo "Inspecting published image: ${target_ref}"
  docker buildx imagetools inspect "${target_ref}" | tee "/tmp/${manifest_prefix}-target-manifest.txt"

  grep -q "Platform:.*linux/amd64" "/tmp/${manifest_prefix}-target-manifest.txt"
  grep -q "Platform:.*linux/arm64" "/tmp/${manifest_prefix}-target-manifest.txt"

  echo "Published ${target_ref} with linux/amd64 and linux/arm64 variants."
}

publish_image \
  "${HYPERDX_SOURCE_IMAGE}:${HYPERDX_TAG}" \
  "${HYPERDX_TARGET_IMAGE}:${HYPERDX_TAG}" \
  "rulebricks-hyperdx"

publish_image \
  "${CLICKSTACK_OTEL_COLLECTOR_SOURCE_IMAGE}:${CLICKSTACK_OTEL_COLLECTOR_TAG}" \
  "${CLICKSTACK_OTEL_COLLECTOR_TARGET_IMAGE}:${CLICKSTACK_OTEL_COLLECTOR_TAG}" \
  "rulebricks-clickstack-otel-collector"

publish_image \
  "${FERRETDB_SOURCE_IMAGE}:${FERRETDB_TAG}" \
  "${FERRETDB_TARGET_IMAGE}:${FERRETDB_TAG}" \
  "rulebricks-ferretdb"

publish_image \
  "${POSTGRES_DOCUMENTDB_SOURCE_IMAGE}:${POSTGRES_DOCUMENTDB_TAG}" \
  "${POSTGRES_DOCUMENTDB_TARGET_IMAGE}:${POSTGRES_DOCUMENTDB_TAG}" \
  "rulebricks-postgres-documentdb"
