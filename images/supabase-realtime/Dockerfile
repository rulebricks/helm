# check=skip=InvalidDefaultArgInFrom
# rulebricks/supabase-realtime — Supabase Realtime rebuilt from unmodified
# upstream source (mix.lock frozen) on patched Erlang/OTP and Debian 13
# (clears the OTP SSH/SSL CVEs and bookworm's no-fix curl/gnutls tail).
# awscli/curl are not installed: run.sh only uses them in AWS-ECS-only paths
# the chart never enables.
# All pins live in images/manifest.yaml (base/ref plus the version-adjacent
# args: ELIXIR/OTP/DEBIAN versions, PG_DELTA_COMMIT, BUN_VERSION — these
# mirror upstream's pins at the release tag), injected as build args by
# scripts/images/build.sh. Bumps: images/README.md.

ARG ELIXIR_VERSION
ARG OTP_VERSION
ARG DEBIAN_VERSION
ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}-slim"
ARG BASE_IMAGE

# pg-delta CLI, mirrors upstream's pgdelta-builder stage.
FROM ${BASE_IMAGE} AS pgdelta-builder
ARG PG_DELTA_COMMIT
ARG BUN_VERSION

RUN set -eux; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends curl ca-certificates unzip xz-utils; \
    curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"; \
    export PATH="/root/.bun/bin:${PATH}"; \
    mkdir -p /build && cd /build; \
    curl -fsSL "https://github.com/supabase/pg-toolbelt/archive/${PG_DELTA_COMMIT}.tar.gz" \
      | tar xz --strip-components=1; \
    bun install --frozen-lockfile --ignore-scripts; \
    cd /build/packages/pg-delta; \
    bun build --compile src/cli/bin/cli.ts --outfile /tmp/pgdelta; \
    /tmp/pgdelta --help > /dev/null; \
    xz -9 -e -T0 -c /tmp/pgdelta > /tmp/pgdelta.xz; \
    cd / && find build -path '*/@libpg-query/parser/wasm/libpg-query.wasm' \
      | tar -czf /tmp/libpg-query.tar.gz -T -; \
    printf '%s\n' \
      '#!/bin/sh' \
      'set -e' \
      'BIN=/app/.pgdelta-cache/pgdelta' \
      'if [ ! -x "$BIN" ]; then' \
      '  mkdir -p "$(dirname "$BIN")"' \
      '  xz -dcT0 /usr/local/share/pgdelta/pgdelta.xz > "$BIN"' \
      '  chmod +x "$BIN"' \
      'fi' \
      'exec "$BIN" "$@"' \
      > /tmp/pgdelta-wrapper; \
    chmod +x /tmp/pgdelta-wrapper; \
    rm -rf /tmp/pgdelta /build /root/.bun /var/lib/apt/lists/*

# Elixir release, mirrors upstream's builder stage.
FROM ${BUILDER_IMAGE} AS builder

ARG UPSTREAM_REF

ENV MIX_ENV="prod"

RUN set -uex; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates gnupg; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    NODE_MAJOR=24; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list; \
    apt-get -qy update; \
    apt-get -qy install nodejs; \
    apt-get clean

WORKDIR /app
ADD https://github.com/supabase/realtime/archive/${UPSTREAM_REF}.tar.gz /tmp/src.tar.gz
RUN tar -xzf /tmp/src.tar.gz --strip-components=1 && rm /tmp/src.tar.gz

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only $MIX_ENV && \
    mix deps.compile && \
    cd assets && npm install && cd .. && \
    mix assets.deploy && \
    mix compile && \
    mix release

# Runtime, mirrors upstream's runner stage (libncurses6: trixie ships no 5).
FROM ${BASE_IMAGE}
ARG SLOT_NAME_SUFFIX

ENV SLOT_NAME_SUFFIX="${SLOT_NAME_SUFFIX}" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8" \
    MIX_ENV="prod" \
    ECTO_IPV6="true" \
    ERL_AFLAGS="-proto_dist inet6_tcp"

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales iptables sudo tini jq xz-utils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=pgdelta-builder /tmp/pgdelta.xz /usr/local/share/pgdelta/pgdelta.xz
COPY --from=pgdelta-builder /tmp/pgdelta-wrapper /usr/local/bin/pgdelta
COPY --from=pgdelta-builder /tmp/libpg-query.tar.gz /tmp/libpg-query.tar.gz
RUN tar -C / -xzf /tmp/libpg-query.tar.gz && rm /tmp/libpg-query.tar.gz

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

WORKDIR "/app"

RUN chown nobody /app && mkdir -p /app/.pgdelta-cache && chown nobody /app/.pgdelta-cache

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/realtime ./
COPY --from=builder --chown=nobody:root /app/run.sh run.sh

ENTRYPOINT ["/usr/bin/tini", "-s", "-g", "--", "/app/run.sh"]
CMD ["/app/bin/server"]
