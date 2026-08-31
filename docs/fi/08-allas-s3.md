# 8. Allas-objektitallennus (S3)

> Rahdin podit ovat tilattomia: podin levylle kirjoitettu data katoaa. Pysyvä data
> kuuluu joko PVC:lle tai — isot tiedostot, jaettu käyttö, varmuuskopiot — CSC:n
> Allas-objektitallennukseen.

## Sisällys

- [S3 vai Swift](#s3-vai-swift)
- [1. Luo bucket](#1-luo-bucket)
- [2. Asenna OpenStack-työkalut](#2-asenna-openstack-työkalut)
- [3. Hae S3-tunnukset](#3-hae-s3-tunnukset)
- [4. Tallenna tunnukset](#4-tallenna-tunnukset)
- [5. Käyttö koodista](#5-käyttö-koodista)
- [Tunnukset Rahtiin](#tunnukset-rahtiin)
- [Vianmääritys](#vianmääritys)

## S3 vai Swift

Allas tukee kahta protokollaa. **Käytä S3:a sovelluksissa.**

| | S3 | Swift |
| --- | --- | --- |
| Tunnusten elinikä | pitkäikäiset avaimet | token vanhenee ~8 h |
| Sopii Rahtiin | kyllä | huonosti — token vanhenisi kesken ajon |
| Kirjastotuki | boto3, AWS SDK, s3cmd, rclone | swift-client |

Älä sekoita protokollia samassa bucketissa.

| Palvelu | Endpoint | Region |
| --- | --- | --- |
| S3 API | `https://a3s.fi` | `regionOne` |
| Swift API | `https://a3s.fi:443/swift/v1/AUTH_<project-id>` | `regionOne` |

> Region on aina `regionOne`, vaikka palvelin on Suomessa. Ei `eu-north-1`.

## 1. Luo bucket

1. Kirjaudu [allas.csc.fi](https://allas.csc.fi/)
2. Valitse oikea projekti vasemmalta
3. **+ Create bucket**

**Nimeäminen:** bucket-nimien on oltava uniikkeja **kaikkien Allas-käyttäjien kesken**.
CSC suosittelee etuliitteeksi projektin numeroa, esim. `1234567-raw-data`. Vain pieniä
kirjaimia, numeroita ja väliviivoja — ei ääkkösiä.

> **Tunnukset ja bucketit ovat projektikohtaisia.** Varmista että luot tunnukset samassa
> projektissa, jossa bucket on — muuten saat 403-virheen etkä ymmärrä miksi.

## 2. Asenna OpenStack-työkalut

Tunnukset haetaan OpenStack-komentorivityökalulla.

```powershell
python -m pip install --user python-openstackclient
```

Jos `openstack`-komento ei löydy asennuksen jälkeen, Scripts-kansio ei ole PATHissa.
Selvitä oikea polku:

```powershell
python -c "import sys, os; print(os.path.dirname(sys.executable) + '\\Scripts')"
```

Lisää tuloste PATHiin (pysyvästi: Windows + R → `sysdm.cpl` → *Advanced → Environment
Variables → Path → New*), avaa uusi terminaali ja tarkista:

```powershell
openstack --version
```

**Konfiguraatio:**

1. Kirjaudu [pouta.csc.fi](https://pouta.csc.fi/)
2. **API Access → Download OpenStack RC File → OpenStack clouds.yaml file**
3. Tallenna tiedosto polkuun `~/.config/openstack/clouds.yaml`
   (Windowsilla `C:\Users\<tunnus>\.config\openstack\clouds.yaml`)

```powershell
mkdir "$HOME\.config\openstack"
```

Tiedoston sisältö on tätä muotoa:

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://pouta.csc.fi:5001/v3
      username: "<csc-tunnus>"
      project_id: "<projektin-id>"
      project_name: "project_XXXXXXX"
      user_domain_name: "Default"
      # password: jätä pois — kysytään ajettaessa
    regions:
      - regionOne
    interface: "public"
    identity_api_version: 3
```

## 3. Hae S3-tunnukset

```powershell
$env:OS_CLOUD = "openstack"

# Varmista että olet oikeassa projektissa
openstack configuration show          # katso auth.project_id
openstack project list                # kaikki projektit
openstack project set project_XXXXXXX # vaihda tarvittaessa

# Listaa olemassa olevat tunnukset
openstack ec2 credentials list

# Luo uudet, jos tarvitaan
openstack ec2 credentials create
```

Komento kysyy CSC-salasanaa. Tuloste:

```
+----------------------------------+-----------------------------------+----------------------------------+---------+
| Access                           | Secret                            | Project ID                       | User ID |
+----------------------------------+-----------------------------------+----------------------------------+---------+
| abc123def456ghi789jkl012mno345pq | xyz789uvw456rst123qpo890lmn567abc | def456abc789ghi012jkl345mno678pq | tunnus  |
+----------------------------------+-----------------------------------+----------------------------------+---------+
```

`Access` = access key, `Secret` = secret key.

> CSC:n supertietokoneilla (Roihu, LUMI) sama onnistuu yhdellä komennolla:
> `allas-conf` näyttää S3-yhteystiedot suoraan.

## 4. Tallenna tunnukset

Paikallisesti `.env`-tiedostoon (joka on `.gitignore`ssa):

```ini
ALLAS_ACCESS_KEY_ID=abc123def456ghi789jkl012mno345pq
ALLAS_SECRET_ACCESS_KEY=xyz789uvw456rst123qpo890lmn567abc
ALLAS_ENDPOINT_URL=https://a3s.fi
ALLAS_BUCKET_NAME=1234567-raw-data
```

## 5. Käyttö koodista

**Tärkein yksityiskohta:** Allas tukee vain **path-style**-osoitteita
(`a3s.fi/<bucket>/<avain>`), ei virtual-host-tyyliä (`<bucket>.a3s.fi`). AWS SDK v3
käyttää oletuksena virtual-hostia, joten asetus on pakko ohittaa.

### Python (boto3)

```python
import boto3, os

s3 = boto3.client(
    "s3",
    endpoint_url=os.getenv("ALLAS_ENDPOINT_URL"),
    aws_access_key_id=os.getenv("ALLAS_ACCESS_KEY_ID"),
    aws_secret_access_key=os.getenv("ALLAS_SECRET_ACCESS_KEY"),
    region_name="regionOne",
)

for b in s3.list_buckets()["Buckets"]:
    print(b["Name"])

bucket = os.getenv("ALLAS_BUCKET_NAME")
s3.upload_file("paikallinen.txt", bucket, "kansio/etä.txt")
s3.download_file(bucket, "kansio/etä.txt", "ladattu.txt")
```

boto3 osaa path-stylen automaattisesti tälle endpointille. Jos törmäät ongelmiin,
pakota se:

```python
from botocore.config import Config
s3 = boto3.client("s3", ..., config=Config(s3={"addressing_style": "path"}))
```

### JavaScript / TypeScript (AWS SDK v3)

```javascript
import { S3Client, ListBucketsCommand, PutObjectCommand } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  endpoint: process.env.ALLAS_ENDPOINT_URL,   // https://a3s.fi
  region: "regionOne",
  forcePathStyle: true,                        // ← PAKOLLINEN Allakselle
  credentials: {
    accessKeyId: process.env.ALLAS_ACCESS_KEY_ID,
    secretAccessKey: process.env.ALLAS_SECRET_ACCESS_KEY,
  },
});

const { Buckets } = await s3.send(new ListBucketsCommand({}));

await s3.send(
  new PutObjectCommand({
    Bucket: process.env.ALLAS_BUCKET_NAME,
    Key: "test.txt",
    Body: "Hei Allas!",
  })
);
```

## Tunnukset Rahtiin

```bash
oc create secret generic allas-credentials \
  --from-literal=ALLAS_ACCESS_KEY_ID='...' \
  --from-literal=ALLAS_SECRET_ACCESS_KEY='...' \
  --from-literal=ALLAS_ENDPOINT_URL='https://a3s.fi' \
  --from-literal=ALLAS_BUCKET_NAME='1234567-raw-data' \
  -n <projekti>

oc set env deployment/sovellus --from=secret/allas-credentials -n <projekti>
```

Nämä ovat ajonaikaisia muuttujia — **älä laita niitä `NEXT_PUBLIC_`- tai
`VITE_`-etuliitteen taakse**, muuten avaimet päätyvät selaimeen (ks.
[05 Ympäristömuuttujat](05-ymparistomuuttujat.md#build-aika-vs-ajonaika)).

Jos build kaatuu puuttuviin avaimiin, anna sille tyhjä paikanpitäjä:

```dockerfile
ARG ALLAS_ACCESS_KEY_ID=""
ENV ALLAS_ACCESS_KEY_ID=$ALLAS_ACCESS_KEY_ID
RUN npm run build
```

## Vianmääritys

| Oire | Todennäköinen syy |
| --- | --- |
| `SignatureDoesNotMatch` | Väärä secret key, tai virtual-host-osoitteet päällä → `forcePathStyle: true` |
| `403 Forbidden` bucketiin | Tunnukset luotu eri projektissa kuin bucket |
| `NoSuchBucket` | Bucket on toisessa projektissa, tai nimessä kirjoitusvirhe |
| `openstack: command not found` | Python Scripts -kansio ei ole PATHissa (ks. yllä) |
| `pip: command not found` | Käytä `python -m pip install …` |
| Yhteys aikakatkeaa Rahdista | Tarkista ettei endpointissa ole `http://` — vain `https://a3s.fi` |

---

**Edellinen:** [7. Tietokanta](07-tietokanta.md) · **Seuraava:** [9. Vianmääritys →](09-vianmaaritys.md)

**Lähteet:** [CSC: Allas](https://docs.csc.fi/data/Allas/) ·
[CSC: How to get Allas S3 credentials](https://docs.csc.fi/support/faq/how-to-get-Allas-s3-credentials/)
