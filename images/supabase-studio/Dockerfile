# check=skip=InvalidDefaultArgInFrom
# rulebricks/supabase-studio — upstream supabase/studio plus an OS security
# patch layer, purge of unused no-fix packages (git/perl/libcurl/dev headers),
# and removal of the never-invoked npm/pnpm CLI tooling. App code is
# byte-identical to upstream; /app/node_modules is left untouched (pnpm
# store layout; remaining findings are VEX'd).
# The upstream pin lives in images/manifest.yaml (base), injected as a build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y purge git git-man perl perl-modules-5.36 libperl5.36 \
        libcurl3-gnutls librtmp1 libc6-dev libc-dev-bin linux-libc-dev libc-devtools 2>/dev/null || true && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN rm -rf /usr/local/lib/node_modules \
           /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/bin/pnpm /usr/local/bin/pnpx \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg \
           /opt/yarn* /root/.npm
