# 7. PostgreSQL ja pgvector Rahdissa

> Tietokanta samaan projektiin sovelluksen kanssa: asennus, pysyvä levy, pgvector ja
> paikallinen hallinta pgAdminilla.

## Sisällys

- [Ennen kuin asennat](#ennen-kuin-asennat)
- [Asennus konsolista](#asennus-konsolista)
- [Pysyvä tallennustila (PVC)](#pysyvä-tallennustila-pvc)
- [Asennus manifesteilla](#asennus-manifesteilla)
- [pgvector-laajennuksen käyttöönotto](#pgvector-laajennuksen-käyttöönotto)
- [Yhteys sovelluksesta](#yhteys-sovelluksesta)
- [Paikallinen hallinta port-forwardilla](#paikallinen-hallinta-port-forwardilla)
- [Varmuuskopiot](#varmuuskopiot)

## Ennen kuin asennat

Itse ylläpidetty tietokanta Rahdissa käyttää **yhteisöimageja, joille CSC ei anna
tukea**. Se sopii demoihin, opetukseen ja kevyeen tuotantoon, mutta kriittiselle datalle
kannattaa harkita hallinnoitua tietokantapalvelua.

Kaksi asiaa on pakko tehdä oikein:

1. **Pysyvä levy (PVC) ennen kuin kirjoitat oikeaa dataa.** Ilman sitä koko tietokanta
   katoaa jokaisella podin uudelleenkäynnistyksellä.
2. **Ei Routea tietokannalle.** Postgres kuuluu sisäverkkoon. Route tekisi siitä
   internetiin avoimen.

## Asennus konsolista

1. **+Add → Container images**
2. **Image name from external registry:**

   ```
   quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s
   ```

   Tämä on Red Hat AI Services BU:n yhteisöbuildi, jossa pgvector on valmiina ja joka
   toimii OpenShiftin satunnaisella UID:llä. Tarkista uudempi tagi ennen kuin kiinnität
   version.

3. **Name:** esim. `postgresql-pgvector`
4. **Ympäristömuuttujat** (Deploymentin luonnin jälkeen *Environment*-välilehdellä, tai
   suoraan lomakkeen kautta):

   | Muuttuja | Arvo |
   | --- | --- |
   | `POSTGRESQL_USER` | `postgres` |
   | `POSTGRESQL_PASSWORD` | vahva salasana |
   | `POSTGRESQL_DATABASE` | `vectordb` |

5. **Poista rasti kohdasta "Create a route".**

Salasana kuuluu Secretiin, ei suoraan lomakkeelle:

```bash
oc create secret generic postgres-secret \
  --from-literal=POSTGRESQL_USER=postgres \
  --from-literal=POSTGRESQL_PASSWORD='<vahva-salasana>' \
  --from-literal=POSTGRESQL_DATABASE=vectordb -n <projekti>

oc set env deployment/postgresql-pgvector --from=secret/postgres-secret -n <projekti>
```

## Pysyvä tallennustila (PVC)

**Selaimessa:** avaa Deployment → *Actions → Add Storage*

- Nimi: `pgvector-data`
- Access mode: **Single user (RWO)**
- Koko: 5 GiB tai enemmän (kiintiö sallii oletuksena yhteensä 100 GiB)
- Mount path: `/var/lib/pgsql/data`

**Komentoriviltä:**

```bash
oc set volume deployment/postgresql-pgvector \
  --add --name=pgvector-data \
  --type=pvc --claim-name=pgvector-data \
  --claim-size=5Gi --claim-mode=ReadWriteOnce \
  --mount-path=/var/lib/pgsql/data -n <projekti>
```

Tarkista:

```bash
oc get pvc -n <projekti>
```

## Asennus manifesteilla

Toistettavaa asennusta varten sama deklaratiivisesti:

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
    type: Recreate          # RWO-levyä ei voi jakaa kahdelle podille
  selector:
    matchLabels: { app: postgresql-pgvector }
  template:
    metadata:
      labels: { app: postgresql-pgvector }
    spec:
      securityContext: {}   # EI runAsUser
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

> `strategy: Recreate` on tärkeä: oletuksena rullaava päivitys yrittäisi käynnistää uuden
> podin ennen vanhan sammuttamista, mutta RWO-levyä ei voi liittää kahteen podiin
> yhtä aikaa — uusi podi jää `Pending`-tilaan.

## pgvector-laajennuksen käyttöönotto

Laajennus otetaan käyttöön kerran, tietokannan sisällä:

```sql
CREATE EXTENSION vector;
```

Suoraan podista:

```bash
oc exec -it deployment/postgresql-pgvector -n <projekti> -- \
  psql -U postgres -d vectordb -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

Tai pgAdminissa: *Query Tool* (Ctrl+Shift+Q) → sama komento → F5. Vaihtoehtoisesti
napsauta hiiren oikealla *Extensions → Create → Extension…* ja valitse `vector`.

Käyttöesimerkki:

```sql
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');

-- Lähimmät naapurit (L2-etäisyys)
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

Isommilla aineistoilla tarvitset indeksin:

```sql
CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops);
```

## Yhteys sovelluksesta

Saman projektin sisällä tietokanta löytyy palvelunimellä:

```
DATABASE_URL=postgresql://postgres:<salasana>@postgresql-pgvector:5432/vectordb
```

```bash
oc create secret generic sovellus-db \
  --from-literal=DATABASE_URL='postgresql://postgres:<salasana>@postgresql-pgvector:5432/vectordb' \
  -n <projekti>
oc set env deployment/sovellus --from=secret/sovellus-db -n <projekti>
```

## Paikallinen hallinta port-forwardilla

Koska Routea ei ole, tietokantaa hallitaan tunneloimalla:

```bash
oc project <projekti>
oc port-forward svc/postgresql-pgvector 5432:5432
```

Jätä ikkuna auki. Yhdistä pgAdminilla tai `psql`:llä:

| Kenttä | Arvo |
| --- | --- |
| Host | `localhost` |
| Port | `5432` |
| Database | `vectordb` |
| Username | `postgres` |
| Password | `POSTGRESQL_PASSWORD` |

```bash
psql postgresql://postgres:<salasana>@localhost:5432/vectordb
```

Port-forward on tilapäinen hallintayhteys — ei tapa, jolla sovellus kutsuu tietokantaa.

## Varmuuskopiot

Varmuuskopiointi on **sinun vastuullasi**. Minimitaso:

```bash
# Dumppaa paikalliseen tiedostoon
oc exec deployment/postgresql-pgvector -n <projekti> -- \
  pg_dump -U postgres vectordb > backup-$(date +%F).sql

# Palautus
cat backup-2026-08-31.sql | oc exec -i deployment/postgresql-pgvector -n <projekti> -- \
  psql -U postgres -d vectordb
```

Dumpit kannattaa viedä Allakseen: [8. Allas S3 -tallennus](08-allas-s3.md).

---

**Edellinen:** [6. Frontend ja backend](06-frontend-ja-backend.md) · **Seuraava:** [8. Allas S3 →](08-allas-s3.md)
