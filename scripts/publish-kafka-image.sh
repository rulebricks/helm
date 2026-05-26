#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="${SOURCE_IMAGE:-docker.io/bitnamilegacy/kafka}"
TARGET_IMAGE="${TARGET_IMAGE:-docker.io/rulebricks/kafka}"
KAFKA_TAG="${KAFKA_TAG:-4.0.0-debian-12-r10}"

SOURCE_REF="${SOURCE_IMAGE}:${KAFKA_TAG}"
TARGET_REF="${TARGET_IMAGE}:${KAFKA_TAG}"

echo "Inspecting source image: ${SOURCE_REF}"
docker buildx imagetools inspect "${SOURCE_REF}" | tee /tmp/rulebricks-kafka-source-manifest.txt

if ! grep -q "Platform:.*linux/amd64" /tmp/rulebricks-kafka-source-manifest.txt; then
  echo "Source image is missing linux/amd64: ${SOURCE_REF}" >&2
  exit 1
fi

if ! grep -q "Platform:.*linux/arm64" /tmp/rulebricks-kafka-source-manifest.txt; then
  echo "Source image is missing linux/arm64: ${SOURCE_REF}" >&2
  exit 1
fi

echo "Publishing multi-arch manifest: ${TARGET_REF}"
docker buildx imagetools create -t "${TARGET_REF}" "${SOURCE_REF}"

echo "Inspecting published image: ${TARGET_REF}"
docker buildx imagetools inspect "${TARGET_REF}" | tee /tmp/rulebricks-kafka-target-manifest.txt

grep -q "Platform:.*linux/amd64" /tmp/rulebricks-kafka-target-manifest.txt
grep -q "Platform:.*linux/arm64" /tmp/rulebricks-kafka-target-manifest.txt

echo "Published ${TARGET_REF} with linux/amd64 and linux/arm64 variants."
