# check=skip=InvalidDefaultArgInFrom
# rulebricks/serverless-redis-http — hiett/serverless-redis-http rebuilt from
# unmodified upstream source on a current Erlang/OTP (clears the 2021-era base,
# incl. CISA KEV CVE-2025-32433).
# All pins live in images/manifest.yaml (base/ref plus the Elixir/OTP builder),
# injected as build args by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE
ARG RUNTIME_TOOLS_IMAGE

FROM ${BUILDER_IMAGE} AS builder

ARG UPSTREAM_REF

WORKDIR /build
ADD https://github.com/hiett/serverless-redis-http/archive/${UPSTREAM_REF}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# 2021 mix.lock pins a cowlib that no longer compiles on modern OTP; deps
# re-resolve within upstream's own mix.exs constraints.
ENV MIX_ENV=prod
RUN rm mix.lock && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix release

FROM ${RUNTIME_TOOLS_IMAGE} AS runtime-tools

FROM ${BASE_IMAGE}

WORKDIR /app

# Mix release launchers require these utilities, but the hardened Erlang
# runtime intentionally omits them. Source only the binaries from the matching
# DHI dev variant; their shared libraries are already present in the runtime.
COPY --from=runtime-tools /usr/bin/grep /usr/bin/grep
COPY --from=runtime-tools /usr/bin/sed /usr/bin/sed
COPY --from=builder /build/_build/prod/rel/prod/ ./_build/prod/rel/prod/

# Only path uid 65532 can write; release dir stays read-only.
ENV MIX_ENV=prod \
    RELEASE_TMP=/tmp

CMD ["_build/prod/rel/prod/bin/prod", "start"]
