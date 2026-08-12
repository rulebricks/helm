# check=skip=InvalidDefaultArgInFrom
# rulebricks/smtp-acs-bridge — in-cluster SMTP listener that forwards mail to
# the Azure Communication Services Email REST API (HMAC auth with the resource
# access key), for ACS tenants that use API-key auth instead of Entra SMTP
# credentials. Built from Rulebricks' maintained copy of the source
# (github.com/rulebricks/smtp-acs-bridge, MIT, forked from
# ArrEssJay/smtp-acs-bridge); that repo carries an equivalent Dockerfile for
# standalone builds. OpenSSL is statically linked (musl) so the runtime stage
# stays a bare hardened base. Dependencies are pinned by the repo's committed
# Cargo.lock (--locked); bump them there with `cargo update`.
# All pins live in images/manifest.yaml (base/ref), injected as build args
# by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE=docker.io/library/rust:1-alpine

FROM ${BUILDER_IMAGE} AS builder

ARG UPSTREAM_REF
ARG UPSTREAM_VERSION

RUN apk add --no-cache musl-dev pkgconfig openssl-dev openssl-libs-static

WORKDIR /build
ADD https://github.com/rulebricks/smtp-acs-bridge/archive/${UPSTREAM_REF}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# Build the release binary with the HTTP health-server feature the chart's
# probes rely on.
ENV OPENSSL_STATIC=1 \
    CARGO_PROFILE_RELEASE_STRIP=symbols
RUN cargo build --release --locked --features health-server

# DHI base: CA bundle and nonroot user 65532 included, no package manager.
FROM ${BASE_IMAGE}

COPY --from=builder /build/target/release/acs-smtp-relay /usr/local/bin/acs-smtp-relay

ENV RUST_LOG=info \
    LISTEN_ADDR=0.0.0.0:1025 \
    HEALTH_LISTEN_ADDR=0.0.0.0:9090

EXPOSE 1025 9090

USER 65532
ENTRYPOINT ["acs-smtp-relay"]
