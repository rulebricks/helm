# rulebricks/serverless-redis-http — Upstash-compatible Redis REST bridge
# (hiett/serverless-redis-http, MIT), rebuilt from unmodified upstream source
# on a Docker Hardened Images Erlang/OTP runtime.

ARG BASE_IMAGE=dhi.io/erlang-otp:28-alpine3.23
ARG BUILDER_IMAGE=docker.io/library/elixir:1.20-alpine

FROM ${BUILDER_IMAGE} AS builder

# Upstream release tag 0.0.10.
ARG SRH_COMMIT=794c5a372fa3997e08320250235f32e5a86338a3

WORKDIR /build
ADD https://github.com/hiett/serverless-redis-http/archive/${SRH_COMMIT}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# Upstream's own build steps (Dockerfile parity), with fresh dependency
# resolution inside upstream's declared constraints (cowboy ~> 2.9,
# plug ~> 1.13, redix ~> 1.1, ...).
ENV MIX_ENV=prod
RUN rm mix.lock && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix release

FROM ${BASE_IMAGE}

WORKDIR /app

# The release bundles ERTS from the builder; the runtime provides matching
# musl system libraries (incl. OpenSSL for the crypto NIF).
COPY --from=builder /build/_build/prod/rel/prod/ ./_build/prod/rel/prod/

ENV MIX_ENV=prod
# Release tmp files (and any crash dumps) must land somewhere uid 65532 can
# write; the release directory itself stays read-only.
ENV RELEASE_TMP=/tmp

CMD ["_build/prod/rel/prod/bin/prod", "start"]
