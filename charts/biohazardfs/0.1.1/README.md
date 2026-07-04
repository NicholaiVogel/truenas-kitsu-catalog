# BiohazardFS

BiohazardFS server MVP chart for TrueNAS SCALE.

This chart runs the Rust BiohazardFS API server with a migration init container before each API/worker pod starts. It expects a dedicated PostgreSQL metadata database and an S3-compatible/RustFS object store.

## Safety defaults

- Service defaults to `ClusterIP`.
- No public NodePort is exposed by default.
- Worker deployment is disabled by default.
- Secrets are passed through Kubernetes Secrets, not argv.
- Private image pulls can use existing Kubernetes docker-registry Secrets via `image.pullSecrets`, or an explicitly enabled chart-managed dockerconfig Secret via `image.registryAuth`.
- The chart does not modify Kitsu, Nextcloud, or the `biohazard-storage` release.

## Required secret data

Either provide `secrets.existingSecret` with these keys, or enter private values in the TrueNAS form. If you rotate an externally managed Secret, change `secrets.version` to force API/worker pods to restart and read fresh environment variables:

- `database-url`
- `object-store-endpoint`
- `object-store-bucket`
- `object-store-access-key-id`
- `object-store-secret-access-key`

The current BiohazardFS server requires Postgres URLs to include `sslmode=disable` until server-side Postgres TLS support lands.
