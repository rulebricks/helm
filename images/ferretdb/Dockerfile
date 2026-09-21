# check=skip=InvalidDefaultArgInFrom
# rulebricks/ferretdb — FerretDB rebuilt from unmodified upstream source on a
# current Go toolchain (clears fixed Go stdlib/module CVEs).
# All pins live in images/manifest.yaml (base/ref/tag), injected as build
# args by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE=docker.io/library/golang:1.26

FROM ${BUILDER_IMAGE} AS builder

ARG UPSTREAM_REF
ARG UPSTREAM_VERSION

WORKDIR /build
ADD https://github.com/FerretDB/FerretDB/archive/${UPSTREAM_REF}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# Version stamping (the archive tarball has no .git for `git describe`).
RUN printf 'v%s' "${UPSTREAM_VERSION#v}" > build/version/version.txt && \
    printf '%s' "${UPSTREAM_REF}" > build/version/commit.txt && \
    printf 'docker' > build/version/package.txt

# modelcontextprotocol/go-sdk is NOT bumped: fixes are 1.x-only and break the
# 0.2.0 API; the MCP server is opt-in and never enabled by the chart (VEX'd).
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
RUN go get github.com/jackc/pgx/v5@v5.11.0 golang.org/x/crypto@v0.57.0 golang.org/x/net@v0.59.0 google.golang.org/grpc@v1.84.0 go.opentelemetry.io/otel@v1.46.0 go.opentelemetry.io/otel/sdk@v1.46.0 go.opentelemetry.io/otel/trace@v1.46.0 go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@v1.46.0 && \
    go mod tidy && \
    go mod verify && \
    go build -mod=readonly -trimpath -o /out/ferretdb ./cmd/ferretdb

FROM ${BASE_IMAGE}

COPY --from=builder /out/ferretdb /ferretdb

# /state must be writable by the nonroot runtime user (uid 65532).
USER 0
RUN mkdir -p /state && chown 65532:65532 /state
USER 65532

ENV FERRETDB_LISTEN_ADDR=:27017
ENV FERRETDB_DEBUG_ADDR=:8088
ENV FERRETDB_STATE_DIR=/state

VOLUME /state
EXPOSE 27017 27018 8088

ENTRYPOINT ["/ferretdb"]
