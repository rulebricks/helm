# check=skip=InvalidDefaultArgInFrom
# rulebricks/curljq — bash + curl + jq for helm-test hooks (replaces the
# unlicensed kdevup/curljq image).
# The upstream pin lives in images/manifest.yaml (base), injected as a build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apk add --no-cache bash curl jq ca-certificates

CMD ["bash"]
