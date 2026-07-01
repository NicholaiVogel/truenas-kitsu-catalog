# Kitsu TrueNAS/Helm chart

This chart packages a split self-hosted Kitsu stack for TrueNAS SCALE Dragonfish. It does **not** use CGWire's all-in-one trial image.

## Components

- Kitsu frontend: `ghcr.io/emberlightvfx/kitsu-for-docker`
- Zou API and Events: `ghcr.io/emberlightvfx/zou-for-docker`
- PostgreSQL
- Redis
- Meilisearch, enabled by default for full-text search
- Optional Zou job worker, enabled by default

## Install with Helm

Either provide explicit secrets or leave secret fields blank and let Helm generate/preserve random values in the Kubernetes Secret:

```bash
helm install kitsu ./truenas-catalog/charts/kitsu \
  --set service.web.nodePort=30080 \
  --set kitsu.domainName="100.97.98.116:30080" \
  --set zou.admin.email="you@example.com" \
  --set zou.admin.password="replace-me"
```

Then open `http://<node-ip>:30080/`.

## TrueNAS SCALE Dragonfish catalog layout

Place this chart under a catalog train:

```text
my-catalog/
  charts/
    kitsu/
      Chart.yaml
      values.yaml
      questions.yaml
      item.yaml
      app-readme.md
      templates/
```

Add the repo in **Apps → Manage Catalogs → Add Catalog**, choose the `charts` train, then install **Kitsu**.

## Storage

By default the chart creates PVCs for:

- PostgreSQL data
- Redis data
- Meilisearch data
- Zou previews

For TrueNAS datasets you create manually, create all directories first, then set:

```yaml
persistence:
  type: hostPath
  postgresql:
    hostPath: /mnt/tank/apps/kitsu/postgresql
  redis:
    hostPath: /mnt/tank/apps/kitsu/redis
  meilisearch:
    hostPath: /mnt/tank/apps/kitsu/meilisearch
  previews:
    hostPath: /mnt/tank/apps/kitsu/previews
```

The chart uses `hostPath.type=Directory`, not `DirectoryOrCreate`, so a typo fails safely instead of booting a fresh empty database.

## Initialization and upgrades

The Zou API pod waits for Postgres, Redis, and Meilisearch, checks database readiness with `zou is-db-ready`, initializes when needed, runs `zou upgrade-db`, seeds base data, and creates the bootstrap admin if needed.

Before changing image tags, back up PostgreSQL and previews.
