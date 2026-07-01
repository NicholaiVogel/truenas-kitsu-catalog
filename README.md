# TrueNAS SCALE catalog

Custom Helm charts intended for TrueNAS SCALE Dragonfish (24.04), where Apps are Kubernetes/Helm based.

## Use on TrueNAS SCALE Dragonfish

1. Push this `truenas-catalog` directory to a Git repository, or copy its contents into the root of an existing custom catalog repository.
2. In TrueNAS: **Apps → Manage Catalogs → Add Catalog**.
3. Point TrueNAS at the Git repository and use the `charts` train.
4. Install **Kitsu** from the catalog.

Dragonfish is the last TrueNAS SCALE release line that uses Kubernetes/Helm apps. Electric Eel and newer moved Apps to Docker-based management.
