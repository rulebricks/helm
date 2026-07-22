# check=skip=InvalidDefaultArgInFrom
# rulebricks/postgres-documentdb — FerretDB's postgres-documentdb plus an OS
# security patch layer and a gosu recompile (upstream's prebuilt gosu carries
# fixed Go stdlib CVEs). Postgres/DocumentDB bits are byte-identical to upstream.
# The upstream pin lives in images/manifest.yaml (base), injected as a build
# arg by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE=docker.io/library/golang:1.25-alpine

FROM ${BUILDER_IMAGE} AS gosu-builder
# Same gosu release upstream ships, recompiled on current Go.
ARG GOSU_VERSION=1.19
WORKDIR /build
ADD https://github.com/tianon/gosu/archive/refs/tags/${GOSU_VERSION}.tar.gz /tmp/gosu.tar.gz
RUN tar -xzf /tmp/gosu.tar.gz --strip-components=1 && rm /tmp/gosu.tar.gz && \
    go mod tidy && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/gosu .

FROM ${BASE_IMAGE}

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=gosu-builder /out/gosu /usr/local/bin/gosu
