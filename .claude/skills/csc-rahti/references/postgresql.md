# PostgreSQL and pgvector on Rahti

> **Images are community/upstream, not CSC-supported.** `openshift/postgresql:16-el9`
> comes from the cluster's default image streams — verify availability with
> `oc get is -n openshift | grep postgres`.
> `quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s` is a Red Hat AI Services BU
> community build. Check for a newer tag before pinning; no CSC support guarantee.
>
> For anything beyond a demo, consider CSC's managed database services or an
> external managed Postgres instead of self-hosting in the namespace.

## Standard PostgreSQL

```bash
# Create secret
oc create secret generic postgresql-secrets \
  --from-literal=POSTGRESQL_USER=<user> \
  --from-literal=POSTGRESQL_PASSWORD=<password> -n <namespace>

# Apply manifests (PVC + Deployment + Service + ConfigMap)
oc apply -f postgresql/ -n <namespace>

# Port-forward for local access
oc port-forward service/postgresql 5432:5432 -n <namespace>
```

Image reference from the cluster's internal registry:
`image-registry.openshift-image-registry.svc:5000/openshift/postgresql:16-el9`

## PostgreSQL + pgvector

For AI/vector-search workloads. Via web console:

1. **Add → Container images** → image name from external registry:
   `quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s`
2. Environment variables:
   - `POSTGRESQL_USER=postgres`
   - `POSTGRESQL_PASSWORD=<strong-password>`
   - `POSTGRESQL_DATABASE=vectordb`
3. **Do NOT create a Route** — the database must stay internal.
4. Add persistent storage after deployment: **Actions → Add Storage**
   - Name `pgvector-data`, access mode RWO, 5 GiB+
   - Mount path `/var/lib/pgsql/data`

Enable the extension once, inside the database:

```sql
CREATE EXTENSION vector;
```

Connect from an app in the same namespace (Service DNS, no route needed):

```
DATABASE_URL=postgresql://postgres:<password>@postgresql-pgvector:5432/vectordb
```

Local admin access:

```bash
oc port-forward svc/postgresql-pgvector 5432:5432 -n <namespace>
# then point psql / pgAdmin at localhost:5432
```

## Gotchas

- Storage must be attached **before** real data is written; a pod without a PVC
  loses the database on every restart.
- The pod runs with an arbitrary UID — do not set `runAsUser` in the manifest.
- Backups are your responsibility. `oc exec deploy/<pg> -- pg_dump …` into Allas
  (see [allas-s3.md](allas-s3.md)) is the minimum viable approach.
