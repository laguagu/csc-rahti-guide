# hello-rahti — testattu esimerkkisovellus

Pienin mahdollinen sovellus, joka täyttää kaikki Rahdin vaatimukset. Käytä tätä
tarkistaaksesi, että työkalusi, oikeutesi ja komentosi toimivat — ennen kuin
väännät omaa sovellustasi pystyyn.

Sovellus näyttää podin nimen, sille annetun UID:n ja portin, joten se todistaa
silmämääräisesti että kontti käynnistyi, Service löysi podin ja Route vastaa.

![hello-rahti ajossa Rahdissa](../../docs/images/hello-rahti-live.jpg)

## Mitä tässä on

| Tiedosto | Mitä opettaa |
| --- | --- |
| `server.js` | Kuuntelee `0.0.0.0`, lukee portin `PORT`-muuttujasta, tarjoaa autentikoimattoman `/health`-polun |
| `Dockerfile` | Ei roottia, `chown 1001:0` + `chmod g+rwX`, `USER 1001` — toimii satunnaisella UID:llä |
| `.dockerignore` | Pitää imagen pienenä |

Ei riippuvuuksia, ei `npm install`ia. Image on noin 140 MB (`node:22-alpine`).

## Kokeile paikallisesti

```bash
docker build --platform linux/amd64 -t hello-rahti .
docker run --rm -p 8080:8080 hello-rahti
# avaa http://localhost:8080  ja  http://localhost:8080/health
```

## Vie Rahtiin

Nämä komennot on ajettu läpi sellaisenaan Rahti 2:ssa. Korvaa `<projekti>` omalla
projektinimelläsi.

```bash
# 1. Kirjaudu (konsolista: nimesi → Copy login command)
oc login https://api.2.rahti.csc.fi:6443 --token=sha256~<tokenisi>
oc project <projekti>

# 2. ImageStream on luotava ENNEN pushia
oc create imagestream hello-rahti

# 3. Rakenna, kirjaudu rekisteriin ja työnnä
docker build --platform linux/amd64 -t hello-rahti .
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi
docker tag  hello-rahti image-registry.apps.2.rahti.csc.fi/<projekti>/hello-rahti:latest
docker push image-registry.apps.2.rahti.csc.fi/<projekti>/hello-rahti:latest

# 4. Deployment imagestreamista
oc new-app --image-stream=hello-rahti

# 5. Service — oc new-app EI luo tätä, ks. huomio alla
oc expose deployment/hello-rahti --port=8080 --target-port=8080

# 6. Julkinen HTTPS-osoite
oc create route edge hello-rahti --service=hello-rahti --insecure-policy=Redirect

# 7. Osoite ja testi
oc get route hello-rahti -o jsonpath='{.spec.host}{"\n"}'
curl -s https://$(oc get route hello-rahti -o jsonpath='{.spec.host}')/health
```

> **Vaihe 5 on se, joka yllättää.** `oc new-app --image-stream=…` luo pelkän
> Deploymentin, ei Serviceä. Jos hyppäät suoraan reitin luontiin, saat virheen
> *"you need to provide a route port via --port when exposing a non-existent
> service"*. `oc expose deployment/…` luo Servicen oikealla valitsimella.

## Mitä tästä oppii

Ajossa oleva podi todistaa neljä asiaa, jotka ohjeessa väitetään:

```bash
POD=$(oc get pods -l deployment=hello-rahti -o name | head -1)

oc get $POD -o jsonpath='{.spec.containers[0].resources}{"\n"}'
# {"limits":{"cpu":"500m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"500Mi"}}
#   ← LimitRangen oletukset, vaikka manifestissa ei pyydetty mitään

oc get $POD -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}'
# restricted-v2

oc get $POD -o jsonpath='{.spec.containers[0].securityContext.runAsUser}{"\n"}'
# 1006240000   ← satunnainen UID, ei 1001 vaikka Dockerfile niin sanoo
```

Sivu itse näyttää `gid 0` — siksi Dockerfilessä on `chown 1001:0` ja `chmod g+rwX`.

> **`oc get pods -l app=hello-rahti` ei löydä mitään.** `oc new-app` merkitsee podit
> labelilla `deployment=<nimi>`, ei `app=<nimi>`. Deploymentilla itsellään on `app`-label,
> podeilla ei. Sama ansa selittää tyhjän `endpoints`-listan, jos kirjoitat Servicen
> valitsimen käsin.

## Siivoa jälkesi

```bash
oc delete route/hello-rahti svc/hello-rahti deployment/hello-rahti is/hello-rahti
```

Kiintiö on jaettu koko laskentaprojektin kesken, joten testisovellukset kannattaa
poistaa heti kun ne ovat tehneet tehtävänsä.

---

Koko työnkulku selityksineen: [2. Sovelluksen julkaisu](../../docs/fi/02-julkaisu.md) ·
[English](../../docs/en/02-deploying.md)
