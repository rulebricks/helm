# check=skip=InvalidDefaultArgInFrom
# rulebricks/node — official node:24-alpine with the bundled npm CLI
# refreshed to current (the setup job needs npm at runtime, so it can't be
# stripped; node itself is byte-identical to upstream).
# Version pins live in images/manifest.yaml (base/args), injected as build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG NPM_VERSION
ARG UNDICI_VERSION

# npm's bundled undici lags its compatible security patch. It has no runtime
# dependencies, so replace only that package without reconciling npm's tree.
RUN apk upgrade --no-cache && \
    npm install -g npm@${NPM_VERSION} && \
    npm install --prefix /tmp/npm-security --no-save --no-audit --no-fund \
        --ignore-scripts undici@${UNDICI_VERSION} && \
    rm -rf /usr/local/lib/node_modules/npm/node_modules/undici && \
    cp -r /tmp/npm-security/node_modules/undici /usr/local/lib/node_modules/npm/node_modules/undici && \
    npm cache clean --force && \
    rm -rf /root/.npm /tmp/npm-security
