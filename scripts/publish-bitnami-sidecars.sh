#!/usr/bin/env bash
set -euo pipefail

# Republishes the Bitnami sidecar/helper images referenced by the vendored Kafka
# and ClickHouse subcharts under the docker.io/rulebricks org as multi-arch
# manifest lists. These were previously published single-arch (arm64 only) or
# missing entirely, which breaks pulls on amd64 nodes (now the default).
#
# Like the kafka/clickhouse publish scripts, this copies the full upstream
# manifest list with `docker buildx imagetools create` (no rebuild) and verifies
# that both linux/amd64 and linux/arm64 variants are present.

JMX_EXPORTER_SOURCE_IMAGE="${JMX_EXPORTER_SOURCE_IMAGE:-docker.io/bitnamilegacy/jmx-exporter}"
JMX_EXPORTER_TARGET_IMAGE="${JMX_EXPORTER_TARGET_IMAGE:-docker.io/rulebricks/jmx-exporter}"
JMX_EXPORTER_TAG="${JMX_EXPORTER_TAG:-1.4.0-debian-12-r0}"

KUBECTL_SOURCE_IMAGE="${KUBECTL_SOURCE_IMAGE:-docker.io/bitnamilegacy/kubectl}"
KUBECTL_TARGET_IMAGE="${KUBECTL_TARGET_IMAGE:-docker.io/rulebricks/kubectl}"
KUBECTL_TAG="${KUBECTL_TAG:-1.33.4-debian-12-r0}"

OS_SHELL_SOURCE_IMAGE="${OS_SHELL_SOURCE_IMAGE:-docker.io/bitnamilegacy/os-shell}"
OS_SHELL_TARGET_IMAGE="${OS_SHELL_TARGET_IMAGE:-docker.io/rulebricks/os-shell}"
OS_SHELL_TAG="${OS_SHELL_TAG:-12-debian-12-r51}"

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
  "${JMX_EXPORTER_SOURCE_IMAGE}:${JMX_EXPORTER_TAG}" \
  "${JMX_EXPORTER_TARGET_IMAGE}:${JMX_EXPORTER_TAG}" \
  "rulebricks-jmx-exporter"

publish_image \
  "${KUBECTL_SOURCE_IMAGE}:${KUBECTL_TAG}" \
  "${KUBECTL_TARGET_IMAGE}:${KUBECTL_TAG}" \
  "rulebricks-kubectl"

publish_image \
  "${OS_SHELL_SOURCE_IMAGE}:${OS_SHELL_TAG}" \
  "${OS_SHELL_TARGET_IMAGE}:${OS_SHELL_TAG}" \
  "rulebricks-os-shell"
