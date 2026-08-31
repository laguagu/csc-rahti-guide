# 7. PostgreSQL and pgvector on Rahti

> A database in the same project as your app: installation, persistent storage,
> pgvector, and local management with pgAdmin.

## Contents

- [Before you install](#before-you-install)
- [Installing from the console](#installing-from-the-console)
- [Persistent storage (PVC)](#persistent-storage-pvc)
- [Installing with manifests](#installing-with-manifests)
- [Enabling the pgvector extension](#enabling-the-pgvector-extension)
- [Connecting from the app](#connecting-from-the-app)
- [Local management via port-forward](#local-management-via-port-forward)
- [Backups](#backups)

## Before you install

A self-managed database on Rahti uses **community images that CSC does not support**.
It's fine for demos, teaching, and light production use, but for critical data you
should consider a managed database service.

Two things you must get right:

1. **Persistent storage (PVC) before you write any real data.** Without it, the entire
   database disappears every time the pod restarts.
2. **No Route for the database.** Postgres belongs on the internal network. A Route
   would expose it to the internet.

## Installing from the console

1. **+Add → Container images**
2. **Image name from external registry:**

   ```
   quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s
   ```

   This is a community build from Red Hat's AI Services BU with pgvector already
   included, and it works with OpenShift's random UID. Check for a newer tag before you
   pin a version.

3. **Name:** e.g. `postgresql-pgvector`
4. **Environment variables** (on the *Environment* tab after creating the Deployment,
   or directly in the form):

   | Variable | Value |
   | --- | --- |
   | `POSTGRESQL_USER` | `postgres` |
   | `POSTGRESQL_PASSWORD` | a strong password |
   | `POSTGRESQL_DATABASE` | `vectordb` |

5. **Uncheck "Create a route".**

The password belongs in a Secret, not directly in the form:

```bash
oc create secret generic postgres-secret \
  --from-literal=POSTGRESQL_USER=postgres \
  --from-literal=POSTGRESQL_PASSWORD='<strong-password>' \
  --from-literal=POSTGRESQL_DATABASE=vectordb -n <project>

oc set env deployment/postgresql-pgvector --from=secret/postgres-secret -n <project>
```

## Persistent storage (PVC)

**In the browser:** open Deployment → *Actions → Add Storage*

- Name: `pgvector-data`
- Access mode: **Single user (RWO)**
- Size: 5 GiB or more (the quota allows 100 GiB total by default)
- Mount path: `/var/lib/pgsql/data`

**From the command line:**

```bash
oc set volume deployment/postgresql-pgvector \
  --add --name=pgvector-data \
  --type=pvc --claim-name=pgvector-data \
  --claim-size=5Gi --claim-mode=ReadWriteOnce \
  --mount-path=/var/lib/pgsql/data -n <project>
```

Check it:

```bash
oc get pvc -n <project>
```

## Installing with manifests

For a repeatable install, the same thing declaratively:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgvector-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql-pgvector
spec:
  replicas: 1
  strategy:
    type: Recreate          # an RWO volume can't be shared by two pods
  selector:
    matchLabels: { app: postgresql-pgvector }
  template:
    metadata:
      labels: { app: postgresql-pgvector }
    spec:
      securityContext: {}   # NO runAsUser
      containers:
        - name: postgresql
          image: quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s
          envFrom:
            - secretRef: { name: postgres-secret }
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/pgsql/data
          resources:
            requests: { cpu: 100m, memory: 512Mi }
            limits:   { cpu: 500m, memory: 1Gi }
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: pgvector-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql-pgvector
spec:
  selector: { app: postgresql-pgvector }
  ports:
    - port: 5432
      targetPort: 5432
```

> `strategy: Recreate` matters: by default a rolling update would try to start a new
> pod before shutting down the old one, but an RWO volume can't be attached to two pods
> at once — the new pod would get stuck in `Pending`.

## Enabling the pgvector extension

The extension is enabled once, inside the database:

```sql
CREATE EXTENSION vector;
```

Directly from the pod:

```bash
oc exec -it deployment/postgresql-pgvector -n <project> -- \
  psql -U postgres -d vectordb -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

Or in pgAdmin: *Query Tool* (Ctrl+Shift+Q) → the same command → F5. Alternatively,
right-click *Extensions → Create → Extension…* and pick `vector`.

Usage example:

```sql
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');

-- Nearest neighbors (L2 distance)
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

For larger datasets you'll need an index:

```sql
CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops);
```

## Connecting from the app

Within the same project, the database is reachable by its service name:

```
DATABASE_URL=postgresql://postgres:<password>@postgresql-pgvector:5432/vectordb
```

```bash
oc create secret generic app-db \
  --from-literal=DATABASE_URL='postgresql://postgres:<password>@postgresql-pgvector:5432/vectordb' \
  -n <project>
oc set env deployment/app --from=secret/app-db -n <project>
```

## Local management via port-forward

Since there's no Route, the database is managed through a tunnel:

```bash
oc project <project>
oc port-forward svc/postgresql-pgvector 5432:5432
```

Leave the window open. Connect with pgAdmin or `psql`:

| Field | Value |
| --- | --- |
| Host | `localhost` |
| Port | `5432` |
| Database | `vectordb` |
| Username | `postgres` |
| Password | `POSTGRESQL_PASSWORD` |

```bash
psql postgresql://postgres:<password>@localhost:5432/vectordb
```

The port-forward is a temporary management connection — not how the app talks to the
database.

## Backups

Backups are **your responsibility**. Minimum viable approach:

```bash
# Dump to a local file
oc exec deployment/postgresql-pgvector -n <project> -- \
  pg_dump -U postgres vectordb > backup-$(date +%F).sql

# Restore
cat backup-2026-08-31.sql | oc exec -i deployment/postgresql-pgvector -n <project> -- \
  psql -U postgres -d vectordb
```

It's worth shipping dumps to Allas: [8. Allas S3 storage](08-allas-s3.md).

---

**Previous:** [6. Frontend and backend](06-frontend-and-backend.md) · **Next:** [8. Allas S3 →](08-allas-s3.md)
