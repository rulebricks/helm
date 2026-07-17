# rulebricks/curljq — bash + curl + jq for helm-test hooks (supabase subchart).
#
# Replaces the unlicensed docker.io/kdevup/curljq image with a build whose every
# layer has clear provenance: the official Alpine base (Docker library) plus
# clearly-licensed OSS packages (bash GPL-3.0, curl curl-license, jq MIT).
# Built and pushed by scripts/images/build.sh via the manifest entry `curljq`
# (kind: build); BASE_IMAGE is injected from the entry's `base`.
ARG BASE_IMAGE=docker.io/library/alpine:3.22
FROM ${BASE_IMAGE}

RUN apk add --no-cache bash curl jq ca-certificates

CMD ["bash"]
