# rulebricks/postgres-documentdb — FerretDB's Postgres + DocumentDB extension
# image (ghcr.io/ferretdb/postgres-documentdb) with a Debian security patch
# layer applied.

ARG BASE_IMAGE=ghcr.io/ferretdb/postgres-documentdb:17-0.107.0-ferretdb-2.7.0
FROM ${BASE_IMAGE}

# The upstream image runs its entrypoint as root and drops to the postgres
# user itself, so no USER handling is needed; ENTRYPOINT/CMD are inherited.
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
