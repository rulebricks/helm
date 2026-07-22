# rulebricks/kafka-proxy — grepplabs/kafka-proxy (Apache-2.0), rebuilt from
# unmodified upstream source on a current Go toolchain and a hardened runtime.
#
# Why a rebuild instead of a mirror: upstream v0.4.3 (latest release) was
# compiled with an older Go toolchain against 2024-era modules, so the binary
# carries fixed-upstream Go stdlib and golang.org/x/* CVEs that only a
# recompile can clear. The application source is byte-identical to the
# v0.4.3 tag; only the Go toolchain and dependency module versions move
# (upstream vendors its deps, so the vendor tree is dropped and modules are
# re-resolved), and the runtime base becomes the hardened multi-arch
# dhi.io/alpine-base (nonroot 65532, CA bundle included).

ARG BASE_IMAGE=dhi.io/alpine-base:3.22
ARG BUILDER_IMAGE=docker.io/library/golang:1.25-alpine

FROM ${BUILDER_IMAGE} AS builder

# Upstream release tag v0.4.3.
ARG KP_COMMIT=317f1d7aca20d80a341a11235d615b185857d9d6

WORKDIR /build
ADD https://github.com/grepplabs/kafka-proxy/archive/${KP_COMMIT}.tar.gz /build/src.tar.gz
RUN tar -xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# Upstream builds with -mod=vendor against its checked-in vendor tree; drop it
# and re-resolve modules so the security fixes for the flagged dependencies
# (x/crypto SSH stack, x/net, x/oauth2, gRPC authz) actually land, then build
# exactly as upstream does (static binary, same LDFLAGS version stamp).
ENV CGO_ENABLED=0
RUN rm -rf vendor && \
    go get golang.org/x/crypto@latest golang.org/x/net@latest golang.org/x/oauth2@latest google.golang.org/grpc@latest && \
    go mod tidy && \
    go build -o build/kafka-proxy -ldflags "-X github.com/grepplabs/kafka-proxy/config.Version=0.4.3 -w -s" .

FROM ${BASE_IMAGE}

COPY --from=builder /build/build/kafka-proxy /opt/kafka-proxy/bin/kafka-proxy

# dhi.io/alpine-base already runs as nonroot (uid 65532) and ships the CA
# bundle the proxy needs for TLS to managed brokers.
ENTRYPOINT ["/opt/kafka-proxy/bin/kafka-proxy"]
CMD ["--help"]
