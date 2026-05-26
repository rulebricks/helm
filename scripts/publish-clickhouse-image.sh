#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="${SOURCE_IMAGE:-docker.io/bitnamilegacy/clickhouse}"
TARGET_IMAGE="${TARGET_IMAGE:-docker.io/rulebricks/clickhouse}"
KEEPER_SOURCE_IMAGE="${KEEPER_SOURCE_IMAGE:-docker.io/bitnamilegacy/clickhouse-keeper}"
KEEPER_TARGET_IMAGE="${KEEPER_TARGET_IMAGE:-docker.io/rulebricks/clickhouse-keeper}"
CLICKHOUSE_TAG="${CLICKHOUSE_TAG:-25.7.5-debian-12-r0}"

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
  "${SOURCE_IMAGE}:${CLICKHOUSE_TAG}" \
  "${TARGET_IMAGE}:${CLICKHOUSE_TAG}" \
  "rulebricks-clickhouse"

publish_image \
  "${KEEPER_SOURCE_IMAGE}:${CLICKHOUSE_TAG}" \
  "${KEEPER_TARGET_IMAGE}:${CLICKHOUSE_TAG}" \
  "rulebricks-clickhouse-keeper"
