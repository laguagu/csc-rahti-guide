# 3. GitHub-integraatio (BuildConfig ja webhookit)

> `git push` → webhook → Rahti rakentaa imagen → sovellus päivittyy. Ei paikallista
> Dockeria, ei manuaalisia pushia.

## Sisällys

- [Milloin tämä kannattaa](#milloin-tämä-kannattaa)
- [Builder Image vai oma Dockerfile](#builder-image-vai-oma-dockerfile)
- [Tunnettu virhe: "URL is valid but cannot be reached"](#tunnettu-virhe-url-is-valid-but-cannot-be-reached)
- [Vaihe 1: SSH-avain GitHubiin](#vaihe-1-ssh-avain-githubiin)
- [Vaihe 2: BuildConfig](#vaihe-2-buildconfig)
- [Vaihe 3: Webhook](#vaihe-3-webhook)
- [Buildien seuranta](#buildien-seuranta)
- [Sudenkuopat](#sudenkuopat)

## Milloin tämä kannattaa

| Tapa | Hyvä | Huono |
| --- | --- | --- |
| **Docker push paikallisesti** ([luku 2](02-julkaisu.md)) | Nopea, täysi kontrolli, toimii offline | Vaatii Dockerin, manuaalinen |
| **BuildConfig + webhook** (tämä luku) | Automaattinen, ei paikallista Dockeria, build lokitetaan klusteriin | Build syö projektin kiintiötä, hitaampi, virheet debugataan build-logeista |
| **GitHub Actions → docker push** | Tuttu putki, testit samassa | Vaatii Rahti-tokenin CI:n salaisuuksiin |

## Builder Image vai oma Dockerfile

**Builder Image (S2I)** — Rahti pakkaa lähdekoodin valmiiseen ajoympäristöön. Ei
Dockerfilea, nopea aloittaa, riittää tavalliselle Node.js- tai Python-sovellukselle.

**Oma Dockerfile (Docker strategy)** — täysi kontrolli, monivaiheiset buildit,
välttämätön esim. Vite/React-frontendille. Vaatii alla kuvatun kiertotien.

> Builder imagen versiot vanhenevat. Valitse listasta ajantasainen UBI-pohjainen versio;
> vuosia vanha Node.js 18 -builder ei enää saa tietoturvapäivityksiä.

## Tunnettu virhe: "URL is valid but cannot be reached"

Kun projektin yrittää luoda suoraan *Import from Git* -toiminnolla käyttäen SSH-osoitetta
ja Dockerfile-strategiaa, Rahti näyttää virheen **"URL is valid but cannot be reached"**
vaikka SSH-avain olisi oikein sekä GitHubissa että Rahdissa.

**Kiertotie:**

1. Luo sovellus ensin **Builder Imagella**. Punainen "URL is valid but cannot be
   reached" jää näkyviin kentän alle, mutta se on pelkkä varoitus: **Create**-painike
   toimii ja projekti syntyy normaalisti. Virhe koskee vain Dockerfile-strategian
   validointia.
2. Muokkaa sen jälkeen BuildConfigia (*Builds → BuildConfigs → Actions → Edit BuildConfig*
   tai suoraan YAML) Docker-strategiaan:

```yaml
strategy:
  type: Docker
  dockerStrategy:
    dockerfilePath: Dockerfile
```

Vaihtoehtoisesti luo BuildConfig kokonaan komentoriviltä, jolloin lomakkeen
validointibugi ei häiritse (ks. vaihe 2).

## Vaihe 1: SSH-avain GitHubiin

Julkiselle repositoriolle riittää HTTPS-osoite eikä avainta tarvita. Yksityiselle:

```bash
# 1. Luo avainpari (tyhjä passphrase — Rahti ei osaa kysyä sitä)
ssh-keygen -t ed25519 -C "rahti-deploy" -f ./rahti_github_key

# 2. Vie julkinen avain GitHubiin:
#    repo → Settings → Deploy keys → Add deploy key → liitä rahti_github_key.pub
#    Jätä "Allow write access" pois päältä — buildi tarvitsee vain lukuoikeuden.

# 3. Vie yksityinen avain Rahtiin salaisuutena
oc create secret generic github-ssh-key \
  --type=kubernetes.io/ssh-auth \
  --from-file=ssh-privatekey=./rahti_github_key -n <projekti>

oc secrets link builder github-ssh-key -n <projekti>

# 4. Poista yksityinen avain levyltä
rm rahti_github_key
```

Selaimessa sama tehdään *Import from Git* -lomakkeen kohdassa **Show advanced Git
options → Source Secret → Create new Secret** (tyyppi *SSH key*). Liitä avain
kokonaisuudessaan, myös `BEGIN`- ja `END`-rivit.

## Vaihe 2: BuildConfig

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: sovellukseni
spec:
  source:
    type: Git
    git:
      uri: git@github.com:<org>/<repo>.git
      ref: main                      # ks. sudenkuopat!
    sourceSecret:
      name: github-ssh-key
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: sovellukseni:latest
  triggers:
    - type: ConfigChange
    - type: GitHub
      github:
        secretReference:
          name: github-webhook-secret
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: sovellukseni
```

```bash
# Webhook-salaisuus ensin
oc create secret generic github-webhook-secret \
  --from-literal=WebHookSecretKey=$(openssl rand -hex 20) -n <projekti>

oc apply -f buildconfig.yaml -n <projekti>
```

## Vaihe 3: Webhook

1. **Hae URL Rahdista:** *Builds → BuildConfigs → \<nimi\> → Webhooks →
   **Copy URL with Secret***

   Komentoriviltä:

   ```bash
   oc describe bc/sovellukseni -n <projekti> | grep -A2 "Webhook"
   ```

   Muoto:

   ```
   https://api.2.rahti.csc.fi:6443/apis/build.openshift.io/v1/namespaces/<projekti>/buildconfigs/<bc>/webhooks/<secret>/github
   ```

   > Yleiskäyttöinen (ei-GitHub) päätepiste päättyy `/generic`. Valitse tyyppi sen
   > mukaan, missä koodi on: GitHub, GitLab, Bitbucket vai Generic.

2. **Lisää webhook GitHubiin:** repo → *Settings → Webhooks → Add webhook*
   - **Payload URL:** kopioitu osoite
   - **Content type:** `application/json`
   - **Secret:** sama salaisuus kuin URL:ssä
   - **SSL verification:** Enable
   - **Which events:** *Just the push event*
   - **Active:** ✓

3. **Testaa:** tee muutos, pushaa, ja katso käynnistyykö buildi.

## Buildien seuranta

```bash
oc get builds -n <projekti>                  # kaikki buildit
oc logs build/<build-nimi> -n <projekti>     # yhden buildin loki
oc logs -f bc/sovellukseni -n <projekti>     # seuraa uusinta buildia
oc start-build sovellukseni -n <projekti>    # käynnistä käsin
```

## Sudenkuopat

**Haaran nimi.** Rahdin BuildConfigin oletushaara on `master`, GitHubin `main`. Jos
`ref`-kenttää ei ole asetettu, `main`-haaran pushit jäävät huomiotta ilman virheilmoitusta.
Aseta `spec.source.git.ref: main` — tai selaimessa *Show advanced Git options → Git
reference*.

**Epäonnistunut buildi on hiljainen vika.** Kaatunut buildi ei riko ajossa olevaa
sovellusta: uutta imagea ei vain synny ja podi ajaa vanhaa koodia. Podi näyttää
`Ready 1/1` ja route palauttaa 200 — mutta koodimuutos ei näy. Tarkista aina
`oc get builds` kun "deploy ei mennyt läpi".

**Build syö kiintiötä.** Build-podi varaa CPU:n ja muistin samasta laskentaprojektin
kiintiöstä kuin sovellukset. Jos kiintiö on täynnä, build jää `Pending`-tilaan.

**Build-podit kasautuvat.** Jokainen ajo jättää `<sovellus>-<n>-build`-podin.
`Completed`/`Succeeded` on normaali, `Failed` on aito löydös. Siivoa vanhat tarvittaessa:

```bash
oc delete pods -n <projekti> --field-selector=status.phase==Succeeded
```

**Yksityisen imagen pull.** Jos BuildConfig kirjoittaa Satamaan tai vetää pohjaimagen
yksityisestä rekisteristä, linkitä pull secret myös `builder`-tunnukselle:

```bash
oc secrets link builder <pull-secret> -n <projekti>
```

---

**Edellinen:** [2. Julkaisu](02-julkaisu.md) · **Seuraava:** [4. Reitit ja verkko →](04-reitit-ja-verkko.md)

**Lähteet:** [CSC: Webhooks](https://docs.csc.fi/cloud/rahti/tutorials/basic/webhooks/) ·
[CSC: Deploy from Git](https://docs.csc.fi/cloud/rahti/tutorials/basic/deploy-from-git/)
