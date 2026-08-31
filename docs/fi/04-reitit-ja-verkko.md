# 4. Reitit, verkko ja URL-osoitteet

> Miten sovellus saa julkisen osoitteen, miten palvelut puhuvat keskenään klusterin
> sisällä, ja mitä tehdä kun pitkä pyyntö katkeaa 30 sekunnissa.

## Sisällys

- [Kolme tasoa: Pod, Service, Route](#kolme-tasoa-pod-service-route)
- [Sisäinen liikenne: Service-DNS](#sisäinen-liikenne-service-dns)
- [Julkinen osoite: Route](#julkinen-osoite-route)
- [Oman URL-osoitteen luonti](#oman-url-osoitteen-luonti)
- [Reitin vaihto ilman katkosta](#reitin-vaihto-ilman-katkosta)
- [TLS-terminointi](#tls-terminointi)
- [504 Gateway Time-out pitkissä pyynnöissä](#504-gateway-time-out-pitkissä-pyynnöissä)
- [IP-rajaus ja muut annotaatiot](#ip-rajaus-ja-muut-annotaatiot)
- [Oma verkkotunnus](#oma-verkkotunnus)
- [Ulosmenevä liikenne](#ulosmenevä-liikenne)

## Kolme tasoa: Pod, Service, Route

```
Internet ──► Route (https://sovellus.2.rahtiapp.fi)
                │  TLS puretaan tässä (edge)
                ▼
             Service (sovellus:3000)   ← pysyvä DNS-nimi ja kuormantasaus
                │
                ▼
             Pod, Pod, Pod             ← vaihtuvat IP:t, kuolevat ja syntyvät
```

- **Podin IP vaihtuu** aina kun podi käynnistyy uudelleen. Älä käytä sitä mihinkään.
- **Service** on pysyvä nimi ja IP, joka reitittää liikenteen label-valitsimen perusteella.
- **Route** on ainoa asia, joka näkyy internetiin. Ilman Routea palvelu on tavoitettavissa
  vain klusterin sisältä — mikä on backendille ja tietokannalle **oikea** valinta.

Oletuksena podi voi puhua vain oman projektinsa podien kanssa (NetworkPolicy).

## Sisäinen liikenne: Service-DNS

Jokainen Service saa DNS-nimen:

```
<service>.<projekti>.svc.cluster.local     # täysi nimi
<service>.<projekti>                       # toisesta projektista
<service>                                  # saman projektin sisältä
```

Käytännössä frontend kutsuu backendiä näin:

```bash
oc set env deployment/frontend -n <projekti> \
  BACKEND_URL=http://backend-api:8000
```

![Ympäristömuuttujat konsolissa — BACKEND_URL osoittaa sisäiseen palveluun](../images/rahti-env-vars.jpg)

Huomaa `http://`, ei `https://` — TLS puretaan jo Routella, ja sisäverkko on klusterin
sisäistä liikennettä. Portti on **Servicen** portti, ei Routen.

Yhteyden testaus podista:

```bash
oc exec -it deployment/frontend -n <projekti> -- sh
# podin sisällä:
wget -qO- http://backend-api:8000/health
```

> **Paras käytäntö:** älä anna backendille Routea lainkaan. Silloin sitä ei voi kutsua
> internetistä eikä autentikointia tarvitse rakentaa kahteen kertaan.

Lisää kuvioita: [06 Frontend ja backend](06-frontend-ja-backend.md).

## Julkinen osoite: Route

Kun luot sovelluksen konsolista ja rastitat *Create a route*, Rahti generoi osoitteen
muodossa:

```
https://<komponentin-nimi>-<projekti>.2.rahtiapp.fi
```

![Routet-lista konsolissa](../images/rahti-routes.jpg)

Kuvassa `gaik-api` käyttää generoitua nimeä (`gaik-api-gaik.2.rahtiapp.fi`) ja muut
räätälöityä (`gaik-demo.2.rahtiapp.fi`). Molemmat toimivat rinnakkain.

```bash
oc get routes -n <projekti>
oc get route <nimi> -n <projekti> -o jsonpath='{.spec.host}'
```

## Oman URL-osoitteen luonti

Osoitteen etuliite on **uniikki koko Rahti-ympäristössä** ja päätteen on oltava
`.2.rahtiapp.fi`. Reitti on oma objektinsa, joten uuden osoitteen saa luomalla uuden
Routen — vanhaa ei tarvitse poistaa.

```yaml
# uusi-reitti.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: <reitin-nimi>
  namespace: <projekti>
  labels:
    app: <sovelluksen-nimi>
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: <haluttu-nimi>.2.rahtiapp.fi
  to:
    kind: Service
    name: <palvelun-nimi>
    weight: 100
  port:
    targetPort: <portin-nimi-tai-numero>
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

```bash
oc project                       # varmista projekti
oc apply -f uusi-reitti.yaml
curl -I https://<haluttu-nimi>.2.rahtiapp.fi
```

**Esimerkki.** Sovellus `oppimisavustaja`, jonka Service on `oppimisavustaja` portissa
3000:

```yaml
spec:
  host: oppimisavustaja.2.rahtiapp.fi
  to:
    kind: Service
    name: oppimisavustaja
  port:
    targetPort: 3000-tcp
```

> `targetPort` viittaa **Servicen** porttiin. Konsolista luoduilla palveluilla portin nimi
> on tyypillisesti `<numero>-tcp`. Tarkista: `oc get svc <nimi> -o yaml`.

Sama yhdellä komennolla ilman YAML-tiedostoa:

```bash
oc create route edge <reitin-nimi> \
  --service=<palvelu> --hostname=<nimi>.2.rahtiapp.fi \
  --insecure-policy=Redirect -n <projekti>
```

## Reitin vaihto ilman katkosta

Useampi Route voi osoittaa samaan Serviceen. Siirtymä tehdään näin:

1. Luo uusi Route uudella hostnamella
2. Testaa se
3. Päivitä linkit ja mahdolliset CORS-asetukset
4. Poista vanha vasta kun mikään ei enää käytä sitä

```bash
oc delete route <vanha-reitti> -n <projekti>
```

## TLS-terminointi

| Tapa | Mitä tapahtuu | Milloin |
| --- | --- | --- |
| **edge** | Router purkaa TLS:n ja välittää podille HTTP:tä | Oletus. Sovelluksen ei tarvitse tuntea sertifikaatteja. |
| **passthrough** | Router ei pura mitään; podi hoitaa TLS:n | Päästä päähän -salaus, oma sertifikaatti podissa |
| **reencrypt** | Router purkaa ja salaa uudelleen podille | Sisäverkkokin salattava, mutta ulospäin Rahdin sertifikaatti |

`*.2.rahtiapp.fi`-osoitteille Rahdin wildcard-sertifikaatti riittää — omaa
sertifikaattia ei tarvitse hankkia. **Route ilman `tls`-lohkoa palvellaan pelkkänä
HTTP:nä**, joten edge on pyydettävä erikseen.

## 504 Gateway Time-out pitkissä pyynnöissä

Routen HAProxy-timeout on oletuksena **30 sekuntia**. Pitkä synkroninen pyyntö —
LLM-kutsu, iso tiedostolataus, raskas raportti — katkeaa 504-virheeseen, jonka sovellus
usein näyttää geneerisenä "Request failed" -viestinä.

```bash
oc annotate route <reitti> \
  haproxy.router.openshift.io/timeout=120s -n <projekti> --overwrite
```

Tai manifestissa:

```yaml
metadata:
  annotations:
    haproxy.router.openshift.io/timeout: 120s
```

Varmista ensin, että pyyntö oikeasti kestää niin kauan — **504 tasan ~30 sekunnissa** on
tämän vian tunnusmerkki:

```bash
curl -o /dev/null -s -w 'HTTP %{http_code} in %{time_total}s\n' https://<osoite>/hidas
```

Todella pitkille töille parempi ratkaisu on asynkroninen job + tilakysely kuin yhteyden
pitäminen auki minuuttikausia.

## IP-rajaus ja muut annotaatiot

```bash
# Salli vain korkeakouluverkko
oc annotate route <reitti> \
  haproxy.router.openshift.io/ip_allowlist='193.166.0.0/16' -n <projekti>

# HSTS (pakota HTTPS selaimessa)
oc annotate route <reitti> \
  haproxy.router.openshift.io/hsts_header="max-age=31536000;includeSubDomains;preload" -n <projekti>
```

> **Varoitus:** virheellinen allowlist-arvo hylätään hiljaisesti ja **kaikki liikenne
> sallitaan**. Arvot erotellaan välilyönnillä, ei pilkulla, eikä perässä saa olla
> ylimääräistä välilyöntiä.

## Oma verkkotunnus

Oman domainin saa käyttöön osoittamalla DNS:n Rahdin routeriin:

```
CNAME  <oma-domain>  →  router-default.apps.2.rahti.csc.fi
```

Jos CNAME ei ole mahdollinen (juuridomain), käytä A-tietuetta kyseisen nimen IP:llä —
mutta muista, että IP voi muuttua. Sertifikaatti on omalla vastuulla; Let's Encrypt
-automaatio onnistuu Rahdin cert-manager-tuella. Ohjeet:
[CSC: Custom domains](https://docs.csc.fi/cloud/rahti/configurations/custom-domain/).

## Ulosmenevä liikenne

Kaikki Rahdista ulos lähtevä liikenne käyttää tällä hetkellä IP-osoitetta
`86.50.229.150`. Tarvitset sitä, jos ulkoinen tietokanta tai API on palomuurin takana.

CSC varoittaa, että osoite voi muuttua, ja rinnakkain ajettavilla Rahti-versioilla on eri
osoite. Älä kovakoodaa sitä ilman suunnitelmaa päivittämisestä — tarkista arvo aina
[dokumentaatiosta](https://docs.csc.fi/cloud/rahti/configurations/egress-ip/). Oman,
projektikohtaisen egress-IP:n voi pyytää palvelupisteestä.

---

**Edellinen:** [3. GitHub-integraatio](03-github-integraatio.md) · **Seuraava:** [5. Ympäristömuuttujat ja salaisuudet →](05-ymparistomuuttujat.md)

**Lähteet:** [CSC: Networking in Rahti](https://docs.csc.fi/cloud/rahti/usage/networking/) ·
[CSC: Security guide](https://docs.csc.fi/cloud/rahti/security-guide/)
