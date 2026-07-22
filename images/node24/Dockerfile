# check=skip=InvalidDefaultArgInFrom
# rulebricks/node — official node:24-alpine with the bundled npm CLI
# refreshed to current (the setup job needs npm at runtime, so it can't be
# stripped; node itself is byte-identical to upstream).
# The upstream pin lives in images/manifest.yaml (base), injected as a build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apk upgrade --no-cache && \
    npm install -g npm@latest && \
    npm cache clean --force && \
    rm -rf /root/.npm
