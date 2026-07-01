# Kitsu for TrueNAS SCALE Dragonfish

Kitsu is CGWire's production-tracking web app for animation and VFX studios. This chart deploys a split self-hosted stack instead of CGWire's all-in-one trial container.

## Components

- Kitsu frontend nginx container.
- Zou API deployment.
- Zou Events websocket deployment.
- Optional Zou job worker.
- PostgreSQL StatefulSet.
- Redis StatefulSet.
- Optional Meilisearch StatefulSet for full-text search.
- Persistent preview storage mounted at `/opt/zou/previews`.

## Defaults

- Kitsu portal: `http://<truenas-ip>:30080/`
- Bootstrap login: value configured during install, default `admin@example.com`.
- Bootstrap password: value configured during install.

If password/key fields are left blank, the chart generates random Kubernetes Secret values on install. Save the generated bootstrap admin password or read it from the app Secret after install.

## Storage

Use PVC storage for normal catalog installs, or create TrueNAS datasets manually and choose `hostPath`. Host paths must exist before install so typos do not silently create empty data directories.
