# check=skip=InvalidDefaultArgInFrom
# rulebricks/clickstack-otel-collector — HyperDX's ClickStack OTel collector
# rebuilt from unmodified upstream source: all four Go binaries (collector,
# OpAMP supervisor, gomplate, goose/migrate) recompiled on a current toolchain
# (clears fixed Go stdlib/module CVEs). Configs/entrypoint/layout mirror
# upstream's Dockerfile exactly.
# All pins live in images/manifest.yaml (base/ref plus the version-adjacent
# args: OTEL_COLLECTOR_VERSION / OTEL_COLLECTOR_CORE_VERSION from upstream's
# .env at the release tag, GOMPLATE_VERSION), injected as build args by
# scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE=docker.io/library/golang:1.26-alpine

# Upstream source, shared by later stages.
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS src

ARG UPSTREAM_REF

WORKDIR /src
ADD https://github.com/hyperdxio/hyperdx/archive/${UPSTREAM_REF}.tar.gz /tmp/src.tar.gz
RUN tar -xzf /tmp/src.tar.gz --strip-components=1 && rm /tmp/src.tar.gz

# Custom collector via upstream's own OCB builder-config.
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS collector-builder
ARG TARGETARCH
ARG OTEL_COLLECTOR_VERSION
ARG OTEL_COLLECTOR_CORE_VERSION

RUN go install go.opentelemetry.io/collector/cmd/builder@v${OTEL_COLLECTOR_VERSION}

WORKDIR /build
COPY --from=src /src/packages/otel-collector/builder-config.yaml .
RUN sed -i "s/__OTEL_COLLECTOR_VERSION__/${OTEL_COLLECTOR_VERSION}/g; s/__OTEL_COLLECTOR_CORE_VERSION__/${OTEL_COLLECTOR_CORE_VERSION}/g; s|output_path:.*|output_path: /build/output|" builder-config.yaml && \
    CGO_ENABLED=0 builder --config=builder-config.yaml --skip-compilation && \
    cd output && \
    go get golang.org/x/crypto@latest golang.org/x/net@latest google.golang.org/grpc@latest && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath -tags grpcnotrace -ldflags="-s -w" -o /out/otelcol-hyperdx .

# OpAMP supervisor from the matching contrib release.
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS supervisor-builder
ARG TARGETARCH
ARG OTEL_COLLECTOR_VERSION

WORKDIR /contrib
ADD https://github.com/open-telemetry/opentelemetry-collector-contrib/archive/refs/tags/v${OTEL_COLLECTOR_VERSION}.tar.gz /tmp/contrib.tar.gz
RUN tar -xzf /tmp/contrib.tar.gz --strip-components=1 && rm /tmp/contrib.tar.gz && \
    cd cmd/opampsupervisor && \
    go get golang.org/x/crypto@latest golang.org/x/net@latest google.golang.org/grpc@latest && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /out/opampsupervisor .

# gomplate + goose CLI tools. gomplate v4 pins aged deps, so it is built from
# its release source with flagged modules re-resolved; goose @latest is current.
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS tools-builder
ARG TARGETARCH
ARG GOMPLATE_VERSION
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go install -trimpath -ldflags="-s -w" \
      github.com/pressly/goose/v3/cmd/goose@latest && \
    mkdir -p /out && \
    find /go/bin -type f -name goose -exec cp {} /out/ \;
WORKDIR /gomplate
ADD https://github.com/hairyhenderson/gomplate/archive/refs/tags/${GOMPLATE_VERSION}.tar.gz /tmp/gomplate.tar.gz
RUN tar -xzf /tmp/gomplate.tar.gz --strip-components=1 && rm /tmp/gomplate.tar.gz && \
    go get golang.org/x/crypto@latest golang.org/x/net@latest google.golang.org/grpc@latest \
           github.com/go-jose/go-jose/v4@latest github.com/go-git/go-git/v5@latest \
           go.opentelemetry.io/otel@latest go.opentelemetry.io/otel/sdk@latest && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath \
      -ldflags="-s -w -X github.com/hairyhenderson/gomplate/v4/version.Version=${GOMPLATE_VERSION#v}" \
      -o /out/gomplate ./cmd/gomplate

# HyperDX's Go migrate tool.
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS migrate-builder
ARG TARGETARCH
WORKDIR /build
COPY --from=src /src/packages/otel-collector/ ./
RUN go get github.com/pressly/goose/v3@latest github.com/ClickHouse/clickhouse-go/v2@latest && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate

# Runtime, mirrors upstream's Dockerfile prod stage.
FROM ${BASE_IMAGE}

ARG USER_UID=10001
ARG USER_GID=10001

RUN apk upgrade --no-cache && \
    apk add --no-cache ca-certificates && \
    addgroup -S -g ${USER_GID} otel && \
    adduser  -S -u ${USER_UID} -G otel otel && \
    install -d -m 0777 -o ${USER_UID} -g ${USER_GID} /etc/otel/supervisor-data && \
    install -d -m 0755 -o ${USER_UID} -g ${USER_GID} /etc/otelcol-contrib

COPY --from=tools-builder /out/gomplate /usr/local/bin/gomplate
COPY --from=tools-builder /out/goose /usr/local/bin/goose
COPY --from=migrate-builder /out/migrate /usr/local/bin/migrate

USER ${USER_UID}:${USER_GID}

COPY --from=supervisor-builder --chmod=755 /out/opampsupervisor /opampsupervisor
COPY --from=collector-builder --chmod=755 /out/otelcol-hyperdx /otelcontribcol

COPY --from=src --chmod=755 /src/docker/otel-collector/entrypoint.sh /entrypoint.sh
COPY --from=src --chmod=755 /src/docker/otel-collector/log-tailer.sh /log-tailer.sh
COPY --from=src --chown=10001:10001 /src/docker/otel-collector/config.yaml /etc/otelcol-contrib/config.yaml
COPY --from=src --chown=10001:10001 /src/docker/otel-collector/config.standalone.yaml /etc/otelcol-contrib/standalone-config.yaml
COPY --from=src --chown=10001:10001 /src/docker/otel-collector/config.standalone.auth.yaml /etc/otelcol-contrib/standalone-auth-config.yaml
COPY --from=src --chown=10001:10001 /src/docker/otel-collector/config.standalone.promql.yaml /etc/otelcol-contrib/standalone-promql-config.yaml
COPY --from=src --chown=10001:10001 /src/docker/otel-collector/supervisor_docker.yaml.tmpl /etc/otel/supervisor.yaml.tmpl
COPY --from=src --chown=10001:10001 /src/docker/otel-collector/schema /etc/otel/schema

EXPOSE 4317 4318 13133

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -q --spider http://localhost:13133/ || exit 1

ENTRYPOINT ["/entrypoint.sh", "/opampsupervisor"]
