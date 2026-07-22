# check=skip=InvalidDefaultArgInFrom
# rulebricks/valkey-admin — upstream valkey/valkey-admin plus an OS security
# patch layer, in-range refresh of two runtime deps, and removal of the
# never-invoked npm/yarn CLI tooling. App code is byte-identical to upstream.
# The upstream pin lives in images/manifest.yaml (base), injected as a build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# protobufjs/ws refresh stays inside upstream's own lockfile ranges.
RUN cd /app && \
    npm install --no-save --no-audit --no-fund protobufjs@7 ws@8 && \
    rm -rf /usr/local/lib/node_modules \
           /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg \
           /opt/yarn* /root/.npm
