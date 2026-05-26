#!/usr/bin/env bash
set -euo pipefail

TARGET_IMAGE="${TARGET_IMAGE:-docker.io/rulebricks/supabase-postgres}"
SUPABASE_POSTGRES_TAG="${SUPABASE_POSTGRES_TAG:-15.1.0.147-rb1}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

echo "Publishing Barman-enabled Supabase Postgres image: ${TARGET_IMAGE}:${SUPABASE_POSTGRES_TAG}"

docker buildx build \
  --platform "${PLATFORMS}" \
  --tag "${TARGET_IMAGE}:${SUPABASE_POSTGRES_TAG}" \
  --push \
  images/supabase-postgres

echo "Inspecting published image: ${TARGET_IMAGE}:${SUPABASE_POSTGRES_TAG}"
docker buildx imagetools inspect "${TARGET_IMAGE}:${SUPABASE_POSTGRES_TAG}" | tee /tmp/rulebricks-supabase-postgres-target-manifest.txt

grep -q "Platform:.*linux/amd64" /tmp/rulebricks-supabase-postgres-target-manifest.txt
grep -q "Platform:.*linux/arm64" /tmp/rulebricks-supabase-postgres-target-manifest.txt

echo "Published ${TARGET_IMAGE}:${SUPABASE_POSTGRES_TAG} with linux/amd64 and linux/arm64 variants."
