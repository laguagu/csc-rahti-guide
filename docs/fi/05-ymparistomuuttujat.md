# 5. Ympäristömuuttujat ja salaisuudet

> Yleisin yksittäinen virhe Rahti-projekteissa on sekoittaa build-aikainen ja
> ajonaikainen muuttuja. Se johtaa joko rikkinäiseen buildiin tai selaimeen vuotaneeseen
> API-avaimeen.

## Sisällys

- [Build-aika vs. ajonaika](#build-aika-vs-ajonaika)
- [Ajonaikaisten arvojen asettaminen](#ajonaikaisten-arvojen-asettaminen)
- [Salaisuudet (Secret)](#salaisuudet-secret)
- [ConfigMap ei-salaiselle konfiguraatiolle](#configmap-ei-salaiselle-konfiguraatiolle)
- [Sudenkuopat](#sudenkuopat)
- [Muuttujien tarkastelu konsolissa](#muuttujien-tarkastelu-konsolissa)

## Build-aika vs. ajonaika

| Muuttujan tyyppi | Milloin asetetaan | Missä se päätyy |
| --- | --- | --- |
| `NEXT_PUBLIC_*`, `VITE_*`, `REACT_APP_*` | `docker build` | **Paistetaan JS-bundleen — näkyy jokaiselle sivun kävijälle** |
| Kaikki muut | Podin käynnistyessä (`oc set env`, Secret) | Vain palvelinpuolella |

Kaksi seurausta:

1. **Salaisuus `NEXT_PUBLIC_`-etuliitteellä on julkinen.** Se on selaimen lähdekoodissa.
   Jos API-avain on päätynyt sinne, se on kierrätettävä.
2. **Ajonaikainen muuttuja, jota build tarvitsee, kaataa buildin.** Esimerkiksi Next.js:n
   `next build` ajaa sivut läpi ja kaatuu, jos konfiguraatio vaatii avaimen, jota ei ole.
   Ratkaisu on antaa buildille tyhjä paikanpitäjä ja oikea arvo vasta ajossa:

```dockerfile
# Build hyväksyy tyhjän arvon, oikea tulee Secretistä podin käynnistyessä
ARG DATABASE_URL=""
ENV DATABASE_URL=$DATABASE_URL
RUN npm run build
```

## Ajonaikaisten arvojen asettaminen

```bash
# Yksittäisiä arvoja
oc set env deployment/sovellus -n <projekti> \
  NODE_ENV=production BACKEND_URL=http://backend-api:8000

# Kaikki Secretin avaimet kerralla
oc set env deployment/sovellus --from=secret/sovellus-env -n <projekti>

# ConfigMapista
oc set env deployment/sovellus --from=configmap/sovellus-config -n <projekti>

# Listaa nykyiset
oc set env deployment/sovellus -n <projekti> --list

# Poista (huomaa loppuviiva)
oc set env deployment/sovellus -n <projekti> VANHA_MUUTTUJA-
```

Jokainen `oc set env` käynnistää rullaavan päivityksen automaattisesti.

## Salaisuudet (Secret)

Salasanat, API-avaimet ja tokenit kuuluvat Secretiin — eivät Deploymentin
`env`-lohkoon eivätkä versionhallintaan.

```bash
# Suositeltu: yksi avain kerrallaan, ei jäsennysyllätyksiä
oc create secret generic sovellus-env \
  --from-literal=DATABASE_URL='postgresql://user:salasana@postgres:5432/db' \
  --from-literal=OPENAI_API_KEY='sk-...' \
  -n <projekti>

# Tai gitignoratusta tiedostosta (lue sudenkuopat ensin!)
oc create secret generic sovellus-env --from-env-file=.env.local -n <projekti>

# Kytke Deploymentiin
oc set env deployment/sovellus --from=secret/sovellus-env -n <projekti>
```

Yksittäinen avain vain tiettyyn muuttujaan:

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: sovellus-env
        key: DATABASE_URL
```

Arvon tarkistus (kannattaa aina tehdä luonnin jälkeen):

```bash
oc get secret sovellus-env -n <projekti> -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

Päivitys ja kierrätys:

```bash
oc create secret generic sovellus-env \
  --from-literal=OPENAI_API_KEY='sk-uusi' \
  --dry-run=client -o yaml | oc apply -f -

oc rollout restart deployment/sovellus -n <projekti>
```

## ConfigMap ei-salaiselle konfiguraatiolle

```bash
oc create configmap sovellus-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=FEATURE_X=true -n <projekti>

oc set env deployment/sovellus --from=configmap/sovellus-config -n <projekti>
```

ConfigMapin sisältö näkyy kaikille, joilla on lukuoikeus projektiin — se ei ole
salaisuus, vain rakenteinen konfiguraatio.

## Sudenkuopat

**`--from-env-file` säilyttää rivin lopun kommentit.** Rivi

```ini
MODEL=gpt-5.6-sol   # nopein
```

tallentaa arvoksi `gpt-5.6-sol   # nopein`, ja sovellus hajoaa hämärästi. Käytä
`--from-literal`-muotoa tai siivoa tiedosto ensin. Tarkista aina `base64 -d`:llä.

**Salaisuudet eivät päivity lennossa.** Muutettu Secret ei näy ajossa olevalle podille.
Vasta `oc rollout restart` tuo uudet arvot.

**Lainausmerkit.** Erikoismerkkejä sisältävä salasana kannattaa laittaa yksinkertaisiin
lainausmerkkeihin, jotta shell ei tulkitse niitä: `--from-literal=PW='p@$$w0rd!'`.

**`.env` versionhallintaan.** Varmista, että `.gitignore` sisältää `.env` ja
`.env.local`. Jos salaisuus on jo committoitu, sen poistaminen historiasta ei riitä —
avain on kierrätettävä.

**Kubernetes-Secret ei ole salattu, vaan base64-koodattu.** Kuka tahansa, jolla on
lukuoikeus projektiin, näkee arvon. Rajoita projektin oikeudet vain niille, jotka niitä
tarvitsevat (*User Management → RoleBindings*).

## Muuttujien tarkastelu konsolissa

*Workloads → Deployments → \<sovellus\> → Environment*:

![Deploymentin Environment-välilehti](../images/rahti-env-vars.jpg)

Kuvassa `BACKEND_URL` on tavallinen arvo ja loput haetaan Secretistä — Secretin nimi ja
avain näkyvät, arvo ei. Tämä on juuri se tapa, jolla salaisuudet halutaan näkyvän.

---

**Edellinen:** [4. Reitit ja verkko](04-reitit-ja-verkko.md) · **Seuraava:** [6. Frontend ja backend →](06-frontend-ja-backend.md)
