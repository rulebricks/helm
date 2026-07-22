# check=skip=InvalidDefaultArgInFrom
# rulebricks/supabase-postgres-meta — upstream supabase/postgres-meta plus an
# OS security patch layer, purge of unused no-fix packages, in-range fast-uri
# refresh, and removal of the never-invoked npm CLI tooling. App code is
# byte-identical to upstream. fastify stays at upstream's 4.x pin (fix is
# 5.x-only; VEX'd — Kong-authenticated cluster-internal admin API).
# The upstream pin lives in images/manifest.yaml (base), injected as a build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y purge git git-man libcurl3-gnutls libc6-dev libc-dev-bin linux-libc-dev 2>/dev/null || true && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# fast-uri is dependency-free, so both copies (top-level ^3, ajv's nested ^2)
# are staged and copied in place rather than letting npm reconcile the tree.
RUN mkdir -p /tmp/fu3 /tmp/fu2 && \
    cd /tmp/fu3 && npm install --no-save --no-audit --no-fund fast-uri@3 && \
    cd /tmp/fu2 && npm install --no-save --no-audit --no-fund fast-uri@2 && \
    rm -rf /usr/src/app/node_modules/fast-uri /usr/src/app/node_modules/ajv/node_modules/fast-uri && \
    cp -r /tmp/fu3/node_modules/fast-uri /usr/src/app/node_modules/fast-uri && \
    cp -r /tmp/fu2/node_modules/fast-uri /usr/src/app/node_modules/ajv/node_modules/fast-uri && \
    rm -rf /tmp/fu3 /tmp/fu2 \
           /usr/local/lib/node_modules \
           /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg \
           /opt/yarn* /root/.npm
