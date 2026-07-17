# rulebricks/curljq — bash + curl + jq for helm-test hooks (supabase subchart).
#
# Replaces the unlicensed docker.io/kdevup/curljq image with a build whose every
# layer has clear provenance: the DHI curl -dev variant (ships bash, curl, and
# apt wired to DHI's hardened Debian repo) plus jq (MIT) installed from that
# same DHI repo. Built and pushed by scripts/images/build.sh via the manifest
# entry `curljq` (kind: build); BASE_IMAGE is injected from the entry's `base`.
ARG BASE_IMAGE=dhi.io/curl:8.14.1-debian13-dev
FROM ${BASE_IMAGE}

RUN apt-get update \
  && apt-get install -y --no-install-recommends jq \
  && rm -rf /var/lib/apt/lists/*

USER nonroot
CMD ["bash"]
