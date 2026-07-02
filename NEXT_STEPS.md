# Next steps: Kitsu on TrueNAS Dragonfish, then RustFS/JuiceFS storage

Context:

- Catalog repo: <https://github.com/NicholaiVogel/truenas-kitsu-catalog.git>
- Chart path in this repo: `truenas-catalog/charts/kitsu/`
- Biohazard repo commit: `969b2c2c Document Tailnet bridge deployment state`
- Public catalog HEAD: `8cee1eb Document Tailnet bridge deployment state`
- TrueNAS Dragonfish API/UI: `https://100.97.98.116:8443` over Tailscale or `https://192.168.1.128:8443` on LAN
- Current Kitsu status: `kitsu-prod` is live on chart `0.1.3`, `ACTIVE`, `7/7` pods available.
- Current Kitsu endpoints:
  - `http://192.168.1.128:30080/`
  - `http://100.97.98.116:30080/`
- Current Nextcloud endpoint remains on native TrueNAS app port `9001` with HTTPS enabled:
  - `https://192.168.1.128:9001/`
  - `https://100.97.98.116:9001/`
  - Note: the active certificate is the TrueNAS default certificate, so browsers may warn for IP-based URLs.

---

## Phase 0 — Safety rules

1. Do not touch unrelated dirty `web/` changes in the Biohazard repo.
2. Do not use `--force` or destructive database/storage options in chart jobs unless a backup exists.
3. Prefer TrueNAS middleware (`midclt`) for app cleanup. Use direct Kubernetes cleanup only if middleware is wedged.
4. Keep Kitsu and storage work separable:
   - Kitsu chart proves production tracking.
   - RustFS/JuiceFS chart proves production filesystem.
   - Later, combine them under an umbrella chart if desired.

---

## Phase 1 — Recover TrueNAS from failed Kitsu releases

SSH into TrueNAS over Tailscale.

### 1.1 Inspect middleware state

```bash
midclt call chart.release.query | jq '.[] | {name, status, namespace, catalog, catalog_train, chart_metadata: .chart_metadata.name}'
midclt call chart.release.query | jq '.[] | select(.name | test("kitsu"; "i"))'
```

If the command itself times out or errors, restart middleware once:

```bash
systemctl restart middlewared
sleep 30
midclt call core.get_jobs | jq '.[-10:]'
```

This may briefly interrupt the UI. Do not reboot yet unless middleware remains unhealthy.

### 1.2 Delete the failed Kitsu release through middleware

If a release named `kitsu` exists:

```bash
midclt call chart.release.delete kitsu '{"force": true}'
```

Wait and watch jobs:

```bash
watch -n 5 "midclt call core.get_jobs | jq '.[-8:]'"
```

### 1.3 Confirm Kubernetes leftovers

Dragonfish uses Kubernetes underneath. Namespace is usually `ix-<release-name>`.

```bash
k3s kubectl get ns | grep -i kitsu || true
k3s kubectl get all,pvc,secret,cm -A | grep -i kitsu || true
```

If middleware deletion succeeded, there should be no `ix-kitsu` namespace/resources.

### 1.4 Last-resort cleanup only if middleware cannot delete it

Use this only if `chart.release.delete` repeatedly times out/fails and the namespace is clearly stuck:

```bash
k3s kubectl delete ns ix-kitsu --wait=false
```

Then restart middleware again:

```bash
systemctl restart middlewared
```

Re-check:

```bash
midclt call chart.release.query | jq '.[] | select(.name | test("kitsu"; "i"))'
k3s kubectl get ns | grep -i kitsu || true
```

---

## Phase 2 — Verify hostPath datasets and permissions

The target hostPath datasets already created are:

```text
/mnt/Pool2/Applications/Kitsu/postgres
/mnt/Pool2/Applications/Kitsu/redis
/mnt/Pool2/Applications/Kitsu/previews
/mnt/Pool2/Applications/Kitsu/meilisearch
```

Verify they exist and are directories:

```bash
for d in \
  /mnt/Pool2/Applications/Kitsu/postgres \
  /mnt/Pool2/Applications/Kitsu/redis \
  /mnt/Pool2/Applications/Kitsu/previews \
  /mnt/Pool2/Applications/Kitsu/meilisearch; do
  test -d "$d" && echo "OK $d" || echo "MISSING $d"
done
```

Because the chart uses `hostPath.type=Directory`, missing paths will fail safely. That is intentional.

If first install is allowed to create fresh DB contents, make sure the directories are empty or contain only expected app data:

```bash
find /mnt/Pool2/Applications/Kitsu -maxdepth 2 -mindepth 1 -type d -print -exec sh -c 'echo "--- $1"; ls -la "$1" | sed -n "1,20p"' sh {} \;
```

---

## Phase 3 — Reinstall Kitsu using hostPath, not PVC

In TrueNAS Apps UI:

1. Refresh/sync the `KITSU` catalog.
2. Install `Kitsu` version `0.1.1`.
3. Use these important settings:

```yaml
service:
  web:
    nodePort: 30080

persistence:
  enabled: true
  type: hostPath
  storageClassName: ""
  accessMode: ReadWriteOnce
  postgresql:
    hostPath: /mnt/Pool2/Applications/Kitsu/postgres
  redis:
    hostPath: /mnt/Pool2/Applications/Kitsu/redis
  previews:
    hostPath: /mnt/Pool2/Applications/Kitsu/previews
  meilisearch:
    hostPath: /mnt/Pool2/Applications/Kitsu/meilisearch
```

Set an explicit admin password for first install to avoid needing to fetch generated secrets during bring-up:

```yaml
zou:
  admin:
    email: admin@example.com
    password: <temporary-strong-password>
```

Keep Meilisearch enabled for now unless it causes resource pressure.

---

## Phase 4 — Observe Kitsu startup

After install starts:

```bash
k3s kubectl get pods -n ix-kitsu -w
```

In another SSH session:

```bash
k3s kubectl get events -n ix-kitsu --sort-by=.metadata.creationTimestamp | tail -80
```

Expected progression:

1. Postgres pod starts and becomes ready.
2. Redis pod starts and becomes ready.
3. Meilisearch pod starts and becomes ready.
4. Zou API starts, waits for DB/Redis/Meili, runs DB init/upgrade/init-data/admin creation, then serves on `:5000`.
5. Zou events starts on `:5001`.
6. Kitsu frontend starts and proxies `/api` and `/socket.io`.
7. `http://100.97.98.116:30080/` becomes reachable.

Useful logs:

```bash
k3s kubectl logs -n ix-kitsu statefulset/kitsu-postgresql --tail=100
k3s kubectl logs -n ix-kitsu statefulset/kitsu-redis --tail=100
k3s kubectl logs -n ix-kitsu statefulset/kitsu-meilisearch --tail=100
k3s kubectl logs -n ix-kitsu deploy/kitsu-zou-api --tail=200
k3s kubectl logs -n ix-kitsu deploy/kitsu --tail=100
```

Actual resource names may be release-prefixed. If unsure:

```bash
k3s kubectl get deploy,statefulset,svc,pvc -n ix-kitsu
```

---

## Phase 5 — If it fails again, diagnose in this order

### 5.1 PVC/hostPath issues

```bash
k3s kubectl describe pod -n ix-kitsu <pod-name>
k3s kubectl get events -n ix-kitsu --sort-by=.metadata.creationTimestamp | tail -120
```

If errors mention PVC binding, the install is still using `persistence.type=pvc` or TrueNAS did not pass values as expected.

If errors mention hostPath path missing, fix the dataset/path spelling.

### 5.2 Image pull issues

```bash
k3s kubectl describe pod -n ix-kitsu <pod-name> | grep -A5 -B5 -i 'pull\|image'
```

Check that TrueNAS can pull:

- `ghcr.io/emberlightvfx/kitsu-for-docker:latest`
- `ghcr.io/emberlightvfx/zou-for-docker:latest`
- `postgres:15-alpine`
- `redis:7-alpine`
- `getmeili/meilisearch:v1.8.3`

### 5.3 Zou bootstrap issue

Check API logs:

```bash
k3s kubectl logs -n ix-kitsu deploy/kitsu-zou-api --tail=300
```

Known thing to verify: the chart currently runs:

```sh
zou create-admin "$ZOU_ADMIN_EMAIL" --password="$ZOU_ADMIN_PASSWORD" || true
```

Zou docs show:

```sh
zou create-admin --password <password> <email>
```

If admin creation silently fails, patch the chart command order in `templates/configmap.yaml`, bump chart version, regenerate catalog metadata, push, resync, upgrade.

### 5.4 Frontend proxy issue

If pods are healthy but UI cannot call API:

```bash
curl -i http://100.97.98.116:30080/
curl -i http://100.97.98.116:30080/api
```

Then inspect Kitsu nginx config and logs.

---

## Phase 6 — Only after Kitsu works: create `biohazard-storage` chart

Do not mix storage platform work into the Kitsu chart until the Kitsu app is stable.

Create a new chart:

```text
truenas-catalog/charts/biohazard-storage/0.1.0/
```

Initial components:

1. RustFS StatefulSet + Service
2. JuiceFS metadata Postgres StatefulSet + Service
3. JuiceFS bootstrap Job
4. Secret generation/preservation helper
5. TrueNAS questions for hostPath datasets and NodePorts
6. NOTES with Windows/macOS/Linux mount instructions

Suggested datasets:

```text
/mnt/Pool2/Applications/BiohazardStorage/rustfs
/mnt/Pool2/Applications/BiohazardStorage/juicefs-postgres
/mnt/Pool2/Applications/BiohazardStorage/backups
```

Suggested exposed ports over Tailscale/VPN only:

```text
RustFS S3:       30900 -> pod 9000
RustFS Console:  30901 -> pod 9001, optional/VPN only
JuiceFS PG:      30432 -> pod 5432
```

JuiceFS clients need access to both RustFS S3 and the JuiceFS metadata DB. Kitsu does not.

---

## Phase 7 — Prove storage before umbrella integration

From a Linux workstation/agent over Tailscale:

1. Install JuiceFS.
2. Mount `/show` using the generated metadata URL.
3. Run:

```bash
juicefs bench /show
mkdir -p /show/projects/_smoke
printf 'hello from juicefs\n' >/show/projects/_smoke/hello.txt
cat /show/projects/_smoke/hello.txt
```

Then test macOS and Windows clients.

Windows smoke test must include:

- mount as `X:`
- create/edit/delete files
- open a sample Nuke/Houdini/Blender/Maya file if available
- disconnect/reconnect VPN
- verify cache behavior

---

## Phase 8 — Kitsu + filesystem integration

Once both Kitsu and JuiceFS are independently stable:

1. Add a Kitsu file tree descriptor for canonical `/show` paths.
2. Add a small sync worker using Gazu/Zou API that creates directories and `.kitsu.json` markers.
3. Standardize paths:

```text
/show/projects/<Project>/shots/<Sequence>/<Shot>/<TaskType>
/show/projects/<Project>/assets/<AssetType>/<Asset>/<TaskType>
/show/projects/<Project>/publish
/show/projects/<Project>/delivery
/show/projects/<Project>/scratch/agents
```

4. Agents should always work under `/show` and use Kitsu IDs from `.kitsu.json` when present.

---

## Definition of done for the immediate next milestone

Kitsu milestone is complete when:

- `midclt call chart.release.query` shows Kitsu ACTIVE/healthy.
- All pods in `ix-kitsu` are Running/Ready.
- `http://100.97.98.116:30080/` loads the Kitsu UI over Tailscale.
- Admin login works.
- A project can be created.
- Preview upload works and writes under `/mnt/Pool2/Applications/Kitsu/previews`.
- Rebooting/restarting the app preserves Postgres data and previews.

Storage milestone begins only after this is true.

---

## 2026-07-01 deployment result

The Kitsu stack is working on the LAN after switching TrueNAS Apps/Kubernetes to the current `192.168.1.x` network.

Current working endpoint:

```text
http://192.168.1.128:30080/
```

Current working TrueNAS API/UI endpoint:

```text
https://192.168.1.128:8443
```

Important notes:

- The previous portal IP `10.0.0.128` is stale for the current network.
- The router/network is `192.168.1.1/24`.
- Kubernetes `node_ip` was changed to `192.168.1.128`.
- `192.168.1.128/24` was persisted on interface `enp37s0f0` so it appears in Kubernetes bind choices.
- The original release name `kitsu` hit a TrueNAS stale release-dataset issue after delete/recreate: `/mnt/Pool2/ix-applications/releases/kitsu/charts/0.1.2` already existed.
- The working release is named `kitsu-prod` in namespace `ix-kitsu-prod`.
- Kitsu Tailnet access was restored with chart `0.1.3` using an externalIP Service for `100.97.98.116`.
- Nextcloud remains on native app port `9001`; do not move it to another port as a workaround.
- Nextcloud HTTPS was enabled on `9001` using the TrueNAS default certificate (`certificateID: 1`).
- The stale Tailscale Serve backend for Tailnet `9001` was corrected from `10.0.0.128:9001` to `192.168.1.128:9001`.

Validated state:

- `kitsu-prod` is `ACTIVE` on chart `0.1.3`.
- Pod status is `7/7` available.
- `GET http://192.168.1.128:30080/` returns the Kitsu frontend HTML.
- `GET http://192.168.1.128:30080/api` returns Zou API version `1.0.52`.
- `GET http://100.97.98.116:30080/` returns the Kitsu frontend HTML.
- `GET http://100.97.98.116:30080/api` returns Zou API version `1.0.52`.
- Admin login with `admin@example.com` works.
- Project creation works.
- Preview upload works via Gazu/Zou.
- Uploaded preview files were confirmed under `/mnt/Pool2/Applications/Kitsu/previews`, including:
  - `pictures/original/306/796/30679670-52e6-475b-9fe7-330850e170e0`
  - `pictures/thumbnails/306/796/30679670-52e6-475b-9fe7-330850e170e0`
  - `pictures/thumbnails/squ/are/square-30679670-52e6-475b-9fe7-330850e170e0`
  - `pictures/previews/306/796/30679670-52e6-475b-9fe7-330850e170e0`
- A TrueNAS `chart.release.redeploy` of `kitsu-prod` completed and returned to `ACTIVE 7/7`.
- Post-redeploy API/project/preview checks passed.

Chart fixes shipped:

- Kitsu `0.1.2` adds hostPath permission init containers for PostgreSQL, Redis, Meilisearch, and Zou preview storage.
- Kitsu `0.1.3` adds optional Tailnet externalIP exposure for the Kitsu web service.
- Catalog metadata marks latest chart versions correctly and includes changelog metadata required by TrueNAS upgrade summary.

Nextcloud Tailnet note:

- Nextcloud is on native app port `9001` and is `ACTIVE 4/4`.
- Tailscale Serve was binding `100.97.98.116:9001` and forwarding to stale `10.0.0.128:9001`, which caused resets after the LAN moved to `192.168.1.x`.
- Tailscale Serve now forwards Tailnet `9001` to `192.168.1.128:9001`.
- `GET https://100.97.98.116:9001/status.php` returns Nextcloud status JSON when certificate verification is skipped/accepted.
- `GET https://100.97.98.116:9001/apps/files/files/15675289?dir=/02_Projects/Aranoke` reaches Nextcloud and returns `401 Unauthorized` when unauthenticated, confirming routing works.
- A temporary `hostnet-diag` diagnostics release was used and deleted after verification.

Next recommended step before Phase 6:

1. Optionally replace the default TrueNAS certificate with a certificate matching the Tailnet DNS name/IP if browser certificate warnings are unacceptable.
2. Optionally clean up the stale deleted `kitsu` release dataset after a backup/snapshot or during a maintenance window.
3. Use `kitsu-prod` as the live Kitsu release unless/until the stale `kitsu` release dataset is safely removed.

---

## 2026-07-01 storage milestone result

The dedicated RustFS + JuiceFS storage stack is deployed separately from Kitsu/Nextcloud.

Live release:

- Release: `biohazard-storage`
- Namespace: `ix-biohazard-storage`
- Chart: `0.1.6`
- Status: `ACTIVE`, desired app pods `2/2` available
- RustFS image: `rustfs/rustfs:1.0.0-beta.8`
- JuiceFS client image for format jobs: `juicedata/mount:ce-v1.3.1`

Datasets:

```text
/mnt/Pool2/Applications/JuiceFS/rustfs
/mnt/Pool2/Applications/JuiceFS/postgres
```

LAN endpoints validated from a Linux client:

```text
RustFS S3:                 http://192.168.1.128:30900
RustFS Console:            http://192.168.1.128:30901
JuiceFS PostgreSQL meta:   192.168.1.128:30432
JuiceFS volume name:       biohazard
JuiceFS bucket:            juicefs-chunks
```

Important operational notes:

- The JuiceFS metadata database is dedicated to JuiceFS and separate from Kitsu PostgreSQL.
- The RustFS bucket is dedicated to JuiceFS chunks.
- The guarded JuiceFS format Job was enabled only for the one-time format and is now disabled in chart values.
- The format Job succeeded once with `succeeded=1`.
- The formatter initially recorded the in-cluster RustFS DNS name; this was corrected with `juicefs config` to the client-reachable LAN S3 endpoint: `http://192.168.1.128:30900/juicefs-chunks`.
- Chart `0.1.3+` formats future fresh installs with a client-facing bucket URL by default: `http://<nodeIP>:<rustfsS3NodePort>/<bucket>`.
- The first RustFS chart revision passed the RustFS secret on the command line; RustFS echoed startup args in logs. The credential was rotated and chart `0.1.1+` no longer passes the secret as a CLI argument.
- Chart `0.1.3+` leaves secret values blank by default and generates/preserves strong Kubernetes Secret values when explicit values are not supplied.
- Chart `0.1.4+` rejects old public placeholder credentials (`changeme-*`) instead of preserving them during install/upgrade.
- Chart `0.1.5+` treats stateful RustFS/Postgres credentials as immutable after first install unless an explicit rotation procedure is used.
- Chart `0.1.6+` also treats Postgres user/database as immutable after first install to avoid drift with persisted metadata.
- Chart `0.1.5+` pins the format job AWS CLI image to `amazon/aws-cli:2.35.14`.
- Chart `0.1.3+` disables Tailnet `externalIPs` by default to avoid exposing service ports `9000/9001/5432` or colliding with Nextcloud `9001`; use explicit Tailscale Serve forwards if Tailnet storage ports are needed.

Validation evidence:

- Metadata DB contains JuiceFS tables: `metadata_table_count=18`.
- Linux client mounted the JuiceFS volume successfully.
- Smoke write/read succeeded:
  - wrote `smoke/timestamp.txt`
  - wrote `smoke/random.bin` (`8 MiB`)
  - SHA-256 check passed after unmount/remount.
- `juicefs bench` completed successfully with small validation settings:
  - write big file: `82.38 MiB/s`
  - read big file: `81.58 MiB/s`
  - write small file: `120.3 files/s`
  - read small file: `478.9 files/s`
  - stat file: `2423.9 files/s`
- RustFS bucket listing after client writes showed JuiceFS objects:
  - `Total Objects: 28`
  - `Total Size: 27787326`
  - sample prefix: `biohazard/chunks/...`
- After upgrading the live release to hardened chart `0.1.3`, post-upgrade smoke passed:
  - metadata table count remained `18`
  - mount succeeded
  - existing `smoke/random.bin` SHA-256 check passed after remount
  - RustFS listing still showed `28` objects / `27787326` bytes
- Final live upgrade to chart `0.1.6` completed with release `ACTIVE`, pod status `2/2`, and no formatter Jobs present.
- Manual validation snapshots were created:
  - `Pool2/Applications/JuiceFS/rustfs@biohazard-storage-validated-2026-07-01`
  - `Pool2/Applications/JuiceFS/postgres@biohazard-storage-validated-2026-07-01`
- Existing TrueNAS snapshot schedule covers the storage datasets:
  - `Pool2` recursive daily snapshots
  - retention: `2 WEEK`

Catalog/chart changes shipped:

- `biohazard-storage` `0.1.0`: initial RustFS + dedicated PostgreSQL + guarded JuiceFS format job.
- `biohazard-storage` `0.1.1`: fixed format job Postgres readiness and stopped passing RustFS secret as command-line args.
- `biohazard-storage` `0.1.2`: switched format job client image to official `juicedata/mount:ce-v1.3.1`.
- `biohazard-storage` `0.1.3`: hardened repeatability/security with generated preserved secrets, client-facing JuiceFS bucket URL, Tailnet externalIPs disabled by default, and RustFS pinned to `1.0.0-beta.8`.
- `biohazard-storage` `0.1.4`: rejects old public placeholder credentials and marks earlier insecure versions unsupported/deprecated in catalog metadata.
- `biohazard-storage` `0.1.5`: makes stateful credentials immutable after first install and pins the AWS CLI bootstrap image to `amazon/aws-cli:2.35.14`.
- `biohazard-storage` `0.1.6`: makes Postgres user/database immutable after first install to prevent drift with persisted metadata.

Tailnet note:

- LAN storage endpoints are validated.
- Direct Tailnet NodePort checks currently refuse on `100.97.98.116:30900` and `100.97.98.116:30432`.
- If artist clients should mount over Tailnet instead of LAN/subnet routing, add Tailscale Serve TCP forwards:
  - `100.97.98.116:30900 -> 192.168.1.128:30900`
  - `100.97.98.116:30432 -> 192.168.1.128:30432`
  - optionally `100.97.98.116:30901 -> 192.168.1.128:30901` for RustFS console access.
- Preserve the existing Nextcloud Tailnet `9001 -> 192.168.1.128:9001` Serve rule.
