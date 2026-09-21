# check=skip=InvalidDefaultArgInFrom
# rulebricks/kafka-proxy — grepplabs/kafka-proxy rebuilt from unmodified
# upstream source on a current Go toolchain (clears fixed Go stdlib/module CVEs).
# All pins live in images/manifest.yaml (base/ref), injected as build args
# by scripts/images/build.sh. Bumps: images/README.md.

ARG BASE_IMAGE
ARG BUILDER_IMAGE=docker.io/library/golang:1.26-alpine

FROM ${BUILDER_IMAGE} AS builder

ARG UPSTREAM_REF
ARG UPSTREAM_VERSION

WORKDIR /build
ADD https://github.com/grepplabs/kafka-proxy/archive/${UPSTREAM_REF}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# Drop upstream's vendored tree so re-resolved module fixes actually land.
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
RUN rm -rf vendor && \
    go get golang.org/x/crypto@v0.57.0 golang.org/x/net@v0.59.0 golang.org/x/oauth2@v0.37.0 google.golang.org/grpc@v1.84.0 && \
    go mod tidy && \
    go mod verify && \
    go build -mod=readonly -o build/kafka-proxy -ldflags "-X github.com/grepplabs/kafka-proxy/config.Version=${UPSTREAM_VERSION#v} -w -s" .

FROM ${BASE_IMAGE}

COPY --from=builder /build/build/kafka-proxy /opt/kafka-proxy/bin/kafka-proxy

ENTRYPOINT ["/opt/kafka-proxy/bin/kafka-proxy"]
CMD ["--help"]
