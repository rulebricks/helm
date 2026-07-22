# Custom-built images (`kind: build`)

Every `docker.io/rulebricks/*` image is defined in [manifest.yaml](manifest.yaml). Most are
plain mirrors; entries with `kind: build` are built from a context directory here by
[scripts/images/build.sh](../scripts/images/build.sh) (multi-arch, pushed by the
Mirror Images workflow) and rebuilt automatically by the weekly cron, so hardened-base
refreshes and new OS package fixes flow in without manual action.

## Why these exist

Vulnerability scans cover every image at full OS + application depth. Some upstreams
publish infrequently (or are dormant), so their images accumulate CVEs that already have
published fixes. Rebuilding or patch-layering the identical upstream source/image on
current toolchains and hardened bases clears those findings without forking anything.

## The two archetypes

### Source rebuild (`kafka-proxy`, `serverless-redis-http`, `ferretdb`,
### `supabase-gotrue`, `supabase-realtime`, `clickstack-otel-collector`)

Unmodified upstream source at a pinned release commit (`ref` in the manifest, injected as
`ARG UPSTREAM_REF`), compiled with a current toolchain — dependencies re-resolve inside
upstream's own declared version constraints — and shipped on a hardened runtime
(`base` in the manifest, injected as `ARG BASE_IMAGE`). No forks, no source patches.

**To bump upstream:** in the manifest entry, set `ref` to the new release commit/tag and
`tag` to `<new-version>-r1` (bump `-rN` instead when rebuilding the same upstream
version); check the entry's `args` against upstream's pins at the new tag; run
`scripts/images/sync-chart-pins.sh`; push. Update the runtime `base` whenever a newer
hardened tag exists.

### Patch layer (`postgres-documentdb`, `valkey-admin`, `supabase-studio`,
### `supabase-postgres-meta`, `node24`)

Upstream's own published image (`base` in the manifest) plus an OS security-upgrade layer
(and, where the runtime never invokes it, removal of the Node base image's bundled npm
CLI tooling; `valkey-admin` also refreshes two runtime npm deps within upstream's own
declared semver ranges). Application bits are otherwise byte-identical to upstream.

**To bump upstream:** set `base` to the new upstream image tag and `tag` to
`<new-version>-r1`; run `scripts/images/sync-chart-pins.sh`; push. Between upstream
releases the weekly cron rebuild keeps pulling new OS fixes into the same `-rN` tag.

## Conventions

- **The manifest is the single source of truth for upstream pins.** `build.sh` injects
  them as build args: `base` -> `BASE_IMAGE`, `ref` -> `UPSTREAM_REF`, and the tag minus
  its `-rN` suffix -> `UPSTREAM_VERSION`. The Dockerfiles declare these `ARG`s with no
  defaults, so they carry no pin info of their own (a standalone `docker build` must
  pass the args; normally you build through `build.sh`).
- **Source rebuilds pin a commit SHA, patch layers pin an image tag.** `ref` is a commit
  SHA because GitHub release tags are mutable and source tarballs are fetched by ref; the
  entry's `tag` names the release version that SHA corresponds to. Patch layers have no
  `ref` — their upstream pin is the `base` image tag itself.
- Tags are always `<upstream-version>-rN`.
- The manifest `base` is the upstream provenance the release-manifest report tracks for
  "newer available" checks.
- **Chart pins are synced, not hand-edited.** Each entry's `chartRefs` lists every chart
  values location that pins its tag (`<file>:<yaml.path>`, space-separated) — both the
  places an image is consumed (useful for reviewers) and the sync targets for
  `scripts/images/sync-chart-pins.sh`, which rewrites them all from the manifest after
  any tag bump (`--check` reports drift without writing).
- **Version-adjacent build pins live in the entry's `args`** (space-separated
  `KEY=VALUE`, injected as `--build-arg`s by `build.sh`). They mirror values upstream
  pins at the release tag, so check them on every upstream bump:
  - `supabase-realtime`: `ELIXIR_VERSION`, `OTP_VERSION` (patched 27.3.4.x line
    from hexpm), `DEBIAN_VERSION`, `PG_DELTA_COMMIT`, `BUN_VERSION`
  - `clickstack-otel-collector`: `OTEL_COLLECTOR_VERSION`,
    `OTEL_COLLECTOR_CORE_VERSION` (from upstream's `.env`), `GOMPLATE_VERSION`
  - `postgres-documentdb`: `GOSU_VERSION`
