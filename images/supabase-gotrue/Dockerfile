# check=skip=InvalidDefaultArgInFrom
# rulebricks/supabase-gotrue — Supabase Auth/GoTrue rebuilt from unmodified
# upstream source on a current Go toolchain (clears fixed Go module CVEs).
# All pins live in images/manifest.yaml (base/ref/tag), injected as build
# args by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE=docker.io/library/golang:1.25-alpine

# Cross-compiled from the build platform (no emulation): upstream's `make
# build` compiles four release binaries, which under QEMU takes the arm64 CI
# leg ~an hour; this builds just the shipped binary with upstream's exact
# flags (Makefile BUILD_CMD: -buildvcs=false + utilities.Version ldflag).
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS builder
ARG TARGETARCH

ARG UPSTREAM_REF
ARG UPSTREAM_VERSION

WORKDIR /build
ADD https://github.com/supabase/auth/archive/${UPSTREAM_REF}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

ENV CGO_ENABLED=0 GOOS=linux
RUN go get golang.org/x/crypto@latest golang.org/x/net@latest google.golang.org/grpc@latest && \
    go mod tidy && \
    GOARCH=${TARGETARCH} go build -o auth -buildvcs=false \
      -ldflags "-X github.com/supabase/auth/internal/utilities.Version=v${UPSTREAM_VERSION#v}" .

# Runtime mirrors upstream's Dockerfile stage.
FROM ${BASE_IMAGE}

RUN adduser -D -u 1000 supabase && \
    apk add --no-cache ca-certificates

COPY --from=builder /build/auth /usr/local/bin/auth
COPY --from=builder /build/migrations /usr/local/etc/auth/migrations/
RUN ln -s /usr/local/bin/auth /usr/local/bin/gotrue

ENV GOTRUE_DB_MIGRATIONS_PATH=/usr/local/etc/auth/migrations

USER supabase
CMD ["auth"]
