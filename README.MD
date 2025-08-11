# CSC-Rahti ohjeita

## Sisällysluettelo

1. [Sovelluksen julkaisu CSC Rahti 2:ssa](#sovelluksen-julkaisu-csc-rahti-2ssa-dockerin-avulla---yksinkertainen-ohje)
2. [GitHub-integraatio Rahti 2:ssa](#sovelluksen-julkaisu-csc-rahti-2ssa-github-integraatiolla)
3. [React (Vite) + Node.js sovelluksen tuotanto versiot](#react-vite--nodejs-sovelluksen-tuotanto-versiot)
4. [Rahti-sovelluksen URL-osoitteen (Route) muuttaminen](#rahti-sovelluksen-url-osoitteen-route-muuttaminen)
5. [PostgreSQL+pgVector tietokannan asennus ja käyttö Rahdissa](#postgresqlpgvector-tietokannan-asennus-ja-käyttö-rahdissa)
6. [CSC Allas S3 Credentials Hakuohjeet](#csc-allas-s3-credentials-hakuohjeet)

# Sovelluksen julkaisu CSC Rahti 2:ssa Dockerin avulla - Yksinkertainen ohje

## Tärkeä huomio ennen aloitusta!

Rahti 2:n konttirekisterin käyttöön on kaksi vaihtoehtoa:

1. Luo ImageStream manuaalisesti projektiisi (ohjeet alla)
2. TAI vie ensimmäinen sovellus DockerHubin kautta:
   - Käytä DockerHub-rekisteriä ensimmäisessä julkaisussa
   - Rahti luo onnistuneen julkaisun jälkeen automaattisesti ImageStreamin sovelluksellesi
   - Tämän jälkeen voit siirtyä käyttämään Rahdin omaa konttirekisteriä
   - ImageStream löytyy Builds → ImageStreams -valikosta

## 1. Kirjautuminen Rahtiin

1. Mene Rahti 2:n web-käyttöliittymään
2. Klikkaa oikeasta yläkulmasta nimeäsi -> "Copy login command"
3. Kopioi ja suorita kirjautumiskomento terminaalissa:

```bash
oc login --token=sha256~[sinun-tokenisi] --server=https://api.2.rahti.csc.fi:6443
```

## 2. Kontin rakennus ja testaus

1. Rakenna Docker-image:

```bash
# Peruskomento
docker build -t sovelluksesi-nimi .

# TAI jos haluat välttää välimuistin käyttöä (valinnainen)
docker build --no-cache -t sovelluksesi-nimi .
```

2. Testaa paikallisesti (valinnainen vaihe):

```bash
# Ilman ympäristömuuttujia
docker run -p 3000:3000 sovelluksesi-nimi

# Ympäristömuuttujien kanssa
docker run --env-file .env -p 3000:3000 sovelluksesi-nimi
```

## 3. Imagen vienti rekisteriin

Valitse JOKO Rahti 2:n oma konttirekisteri TAI DockerHub:

### Vaihtoehto A: Rahti 2:n konttirekisteri

(Käytettävissä kun ImageStream on luotu tai ensimmäinen sovellus on viety DockerHubin kautta)

1. Kirjaudu Rahti 2:n rekisteriin:

```bash
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi
```

2. Tagaa ja työnnä image:

```bash
docker tag sovelluksesi-nimi image-registry.apps.2.rahti.csc.fi/projektisi-nimi/sovelluksesi-nimi:latest
docker push image-registry.apps.2.rahti.csc.fi/projektisi-nimi/sovelluksesi-nimi:latest
```

### Vaihtoehto B: DockerHub

```bash
docker tag sovelluksesi-nimi käyttäjätunnus/sovelluksesi-nimi:latest
docker push käyttäjätunnus/sovelluksesi-nimi:latest
```

## 4. Sovelluksen käyttöönotto Rahti 2:ssa

### Vaihtoehto 1: Suora käyttöönotto konttirekisteristä

1. Siirry Rahti 2:n web-konsoliin ja projektiisi
2. Valitse "Add" → "Container images"
3. "Deploy Image" -näkymässä:

   **Image-asetukset:**

   - Valitse "Deploy an existing Image from an Image Stream or Image registry"
   - Käytä joko:
     - **DockerHub image**: Syötä suoraan muodossa `käyttäjätunnus/sovellus:latest` (esim. `laguagu/alya:latest`)
     - TAI **Rahti registry**: Valitse sisäisestä rekisteristä

   **Huom DockerHub yksityiset kuvat:**

   - yksityistä DockerHub-kuvaa, sinun täytyy luoda "Image pull secret"
   - Määritä secret name, registry (docker.io), käyttäjätunnus ja salasana
   - Julkisille kuville tätä ei tarvita

   **Yleiset asetukset:**

   - **Application**: Valitse/luo sovelluskokoonpano (esim. "alya-avustaja")
   - **Name**: Anna komponentille uniikki nimi
   - **Target port**: Määritä portti, jossa sovelluksesi kuuntelee (esim. 3000)

Rahti luo automaattisesti julkisen URL-osoitteen sovelluksellesi oletusasetuksilla:

- Generoi automaattisesti hostnamen
- Käyttää Edge TLS-terminointia
- Ohjaa HTTP-liikenteen HTTPS:ään

### Vaihtoehto 2: ImageStream luonti ja käyttö

1. Siirry Builds → ImageStreams → Create ImageStream
2. Luo ImageStream:

```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: sovelluksesi-nimi
  namespace: projektisi-nimi
```

Huom! Voit myös puskea kuvan suoraan Rahti 2:n registryyn ilman että luot ImageStreamia etukäteen! Rahti luo sen siinä tapauksessa automaattisesti

3. Käytä luotua ImageStreamia sovelluksen käyttöönotossa

## 5. Deployment-asetukset

Määrittele käyttöönoton yhteydessä:

- **Deployment strategy**: Rolling Update
- **Auto deploy**: Kytke päälle "Auto deploy when new Image is available"
- **Environment Variables**: Lisää tarvittavat ympäristömuuttujat Name/Value -pareina

# Sovelluksen julkaisu CSC Rahti 2:ssa GitHub-integraatiolla

Tämä ohje kattaa:

- Sovelluksen julkaisun Rahti 2:ssa käyttäen GitHub-integraatiota (BuildConfig)
- Automaattisen build-prosessin konfiguroinnin GitHub webhookin avulla

## Tärkeä huomautus (8.11.2024)

**Rahti 2:n nykyinen rajoitus/bugi:** Kun yrität luoda projektin suoraan GitHub-integraatiolla ja omalla Dockerfilella, saat virheilmoituksen "URL is valid but cannot be reached", vaikka SSH-yhteys olisi konfiguroitu oikein.

### Builder Image vs. Oma Dockerfile

Voit valita kahdesta lähestymistavasta:

1. **Käytä Rahdin Builder Imagea (yksinkertaisempi):**

   - Sopii perinteisille Node.js sovelluksille
   - Riittävä useimmille yksinkertaisille web-sovelluksille
   - Ei vaadi omaa Dockerfilea
   - Nopeampi ottaa käyttöön

2. **Käytä omaa Dockerfilea (joustavampi):**
   - Tarvitaan jos sovelluksella on erityisvaatimuksia
   - Vaaditaan esimerkiksi React Viten kanssa
   - Antaa täyden kontrollin build-prosessiin
   - Vaatii kaksivaiheisen setupin:
     1. Luo ensin projekti käyttäen Rahdin valmista Builder Imagea
     2. Muokkaa sen jälkeen BuildConfig käyttämään oman repositorysi Dockerfilea

Valitse lähestymistapa sovelluksesi vaatimusten mukaan. Jos et ole varma, aloita Builder Imagella - voit aina siirtyä käyttämään omaa Dockerfilea myöhemmin.

## Sisällysluettelo

1. [SSH-avaimen luonti ja konfigurointi](#ssh-avaimen-luonti-ja-konfigurointi)
2. [Rahdin konfigurointi](#rahdin-konfigurointi)
3. [Dockerfile konfigurointi (valinnainen)](#dockerfile-konfigurointi-valinnainen)
4. [Webhook määrittely](#webhook-määrittely)

## SSH-avaimen luonti ja konfigurointi

1. **Luo SSH-avainpari:**

```bash
ssh-keygen -t rsa -b 4096 -C "projektisi@example.com" -f ./rahti_github_key
```

- Paina Enter kun kysytään passphrasea (tyhjä on ok)

2. **GitHub konfigurointi:**

- Mene GitHub repositorion asetuksiin → Deploy keys
- Klikkaa "Add deploy key"
- Kopioi julkinen avain tiedostosta: `cat rahti_github_key.pub`
- Anna avaimelle kuvaava nimi (esim. "Rahti Deploy Key")
- Valitse "Allow write access"

## Rahdin konfigurointi

1. **Luo uusi projekti Rahdissa:**

- Valitse +Add → Import from Git
- Git Repo URL: Käytä SSH-muotoista URL:ää (esim. `git@github.com:username/repo.git`)
  - SSH-muodon repositorysta saat avaamalla repon, klikkaamalla Code-painiketta ja valitsemalla SSH
- Paina "Show advanced Git options"

2. **Lisää SSH-avain Rahtiin:**

- Source Secret → Create new Secret
- Authentication type: SSH key
- Kopioi yksityinen avain (`cat rahti_github_key`)
- **Tärkeää:** Sisällytä myös BEGIN ja END rivit

**HUOM!** Tässä vaiheessa Rahti näyttää virheen "URL is valid but cannot be reached" vaikka olet lisännyt SSH-avaimet oikein sekä Rahtiin että GitHubiin. Tämän rajoituksen takia emme voi käyttää Import Strategy → Dockerfile -vaihtoehtoa, vaan meidän on valittava valmis Builder Image (esim. Node.js). Voit jatkaa eteenpäin virheestä huolimatta ja valita Builder Image seuraavissa vaiheissa.

3. **Builder Image määrittely:**

- Valitse sopiva Builder Image (esim. Node.js 18 (UBI 8))
- Määritä sovelluksen portti Advanced options -kohdassa
- Valitse "Create a route" julkista URL:ää varten
- Lopuksi paina "Create"

**Huom:** Jos sovelluksesi toimii tällä konfiguraatiolla, voit jatkaa käyttämään sitä eikä oman Dockerfilen määrittelyä tarvita

## Dockerfile konfigurointi (valinnainen)

Jos Builder Image ei riitä sovelluksesi tarpeisiin:

1. **BuildConfig muokkaus Builder Imagesta omaan Dockerfileen:**

- Siirry Builds → BuildConfig → YAML
- Muuta strategy-osio käyttämään repositorysi Dockerfilea:

```yaml
strategy:
  type: Docker
  dockerStrategy:
    dockerfilePath: Dockerfile
```

Tämä korvaa Builder Image -konfiguraation ja alkaa käyttää repositoryssasi olevaa Dockerfilea.

**Huom!** Dockerfilen luominen on rajattu tämän ohjeen ulkopuolelle. Jos tarvitset apua Dockerfilen luomisessa sovelluksellesi, voit hyödyntää:

- ChatGPT/Claudea
- Dockerin virallista dokumentaatiota jne.

## Webhook määrittely

Webhook määrittely automaattisia buildejä varten

1. **Hae webhook tiedot Rahdista:**

- BuildConfig:ista löytyy automaattisesti generoidut webhook secretit
- Kopioi GitHub webhook secret (`<buildconfig-nimi>-generic-webhook-secret`)

2. **Lisää webhook GitHubiin:**

- GitHub repository → Settings → Webhooks → Add webhook
- Payload URL muoto:

```
https://api.2.rahti.csc.fi:6443/apis/build.openshift.io/v1/namespaces/<projekti>/buildconfigs/<buildconfig>/webhooks/<secret>/generic
```

> Voit kopioda URL osoitteen Rahdin käyttöliittymästä Webhooks -> "Copy URL with Secret"

- Content type: `application/json`
- Secret: Sama kuin URL:ssä oleva secret
- SSL verification: Enable
- Just the push event: ✓
- Active: ✓

## Testaus

1. Tee muutos GitHub repositorioon
2. Push main-branchiin
3. Tarkista Rahdista että build käynnistyy automaattisesti

## Huomioitavaa

- Rahti 2:ssa voi esiintyä "URL is valid but cannot be reached" -virhe SSH-yhteyden kanssa
- Ongelma voidaan kiertää käyttämällä ensin Builder Imagea ja sen jälkeen konfiguroimalla BuildConfig käyttämään Dockerfilea
- Varmista että portit täsmäävät konfiguraatiossa

- [CSC Rahti docs webhookin määrittelyy](https://csc-guide-preview.2.rahtiapp.fi/origin/kkmattil-sequencing-center-tutorial-2/cloud/tutorials/webhooks/#github)

## Hyödyllisiä vinkkejä Rahti/Docker ympäristöön

### Tagien käyttö

Rahti rakentaa kuvan määritellyn tagin perusteella. Voit määritellä tagin itse:

```bash
# Esimerkki uuden version julkaisusta tietyllä tagilla
docker tag sovelluksesi-nimi image-registry.apps.2.rahti.csc.fi/projektisi-nimi/sovelluksesi-nimi:v1.0.0
docker push image-registry.apps.2.rahti.csc.fi/projektisi-nimi/sovelluksesi-nimi:v1.0.0
```

- Voit määritellä Rahdissa tagi tunnisteen itse minkä perusteella auto deploy käynnistyy. Esim: `:latest`

### Hyödyllisiä komentoja

**ImageStream ja buildit (pysyvät resurssit):**

```bash
# Tarkista ImageStream ja sen tagit
oc get imagestream
oc describe imagestream sovelluksesi-nimi
```

**Podit (väliaikaiset suoritusympäristöt):**

```bash
# Katso podien tila
oc get pods
# Podit voivat olla tilassa:
# - Running (käynnissä)
# - Pending (käynnistymässä)
# - CrashLoopBackOff (käynnistysongelmia)

# Katso podien logit
oc logs pods/podin-nimi

# Tarkista deployment tila (hallinnoi podeja)
oc get deployment

# Poista pod (Rahti luo automaattisesti uuden)
oc delete pod podin-nimi

# Listaa kaikki
oc get all
```

**Huom! Podeista:**

- Podit ovat väliaikaisia suoritusympäristöjä, jotka voivat tuhoutua ja käynnistyä uudelleen
- Rahti hallinnoi podeja automaattisesti Deploymenttien kautta
- Jos pod tuhoutuu, Rahti käynnistää automaattisesti uuden
- Älä tallenna dataa podiin, sillä se häviää podin tuhoutuessa

### Yleisiä käytäntöjä

1. **Käytä sisäisiä palvelunimiä kun mahdollista**
   - Pidä backend sisäisenä palveluna ilman julkista reittiä
   - Käytä Kubernetes-palvelunimiä (esim. `http://backend-service-name:8080`)
2. Tarkista sovelluksen logit käyttöönoton jälkeen
3. Pidä image mahdollisimman pienenä (käytä .dockerignore)

# React (Vite) + Node.js sovelluksen tuotanto versiot

> **HUOM!** Tämä ohje sisältää teoreettisia ratkaisuvaihtoehtoja, joita ei ole vielä täysin testattu Rahti 2 tuotantoympäristössä. Periaatteet ovat oikein, mutta yksityiskohdissa voi olla tarvetta hienosäätöön. Käytä tätä ohjetta pohjana ja muokkaa tarvittaessa omaan käyttöösi sopivaksi.

Tämä ohje kattaa kolme eri tapaa julkaista React (Vite) + Node.js sovellus Rahdissa.

## Vaihtoehto A: Yksinkertainen ratkaisu (ilman erillistä DockerFileä)

Tämä on helpoin tapa, jos et halua käyttää Dockeria itse vaan antaa Rahdin hoitaa kontituksen:

1. Tee React-sovelluksen build:

```bash
cd frontend-repo
npm run build
```

2. Valmistele backend:

```bash
cd backend-repo
mkdir client      # Luo kansio frontend buildille
```

3. Kopioi frontend build backendiin:

- Kopioi `frontend-repo/dist` -kansio `backend-repo/client/dist` -kansioon

4. Muokkaa backend/index.js:

```javascript
const express = require("express");
const path = require("path");
const app = require("./app");
require("dotenv").config();

// Frontend buildin käyttöönotto
app.use(express.static(path.join(__dirname, "client/dist")));

// Tämä pitää olla API-reittien jälkeen
// Handlaa client-side reitityksen
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "client/dist", "index.html"));
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
```

**Huom!**

- Kun käynnistät sovelluksen `npm start` komennolla (oletus että tämä käynnistää sinun backend serverin), sekä backend että frontend pyörivät samassa portissa (8080)
- Frontend build on staattista sisältöä, jota backend jakaa
- Ei tarvetta erilliselle frontend-palvelimelle
- Kaikki API-kutsut menevät samaan osoitteeseen missä frontend pyörii

## Vaihtoehto B: Docker Compose (monorepo-ratkaisu)

1. Projektirakenne:

```
project/
├── backend/
│   ├── index.js
│   └── package.json
├── frontend/
│   ├── src/
│   └── package.json
├── docker-compose.yml
└── Dockerfile
```

2. Dockerfile:

```dockerfile
FROM node:18-alpine
WORKDIR /app

# Kopioi package.json tiedostot
COPY package*.json ./
COPY frontend/package*.json ./frontend/
COPY backend/package*.json ./backend/

# Asenna riippuvuudet
RUN npm install
RUN cd frontend && npm install
RUN cd backend && npm install

# Kopioi ja buildaa
COPY . .
RUN cd frontend && npm run build
RUN mkdir -p backend/client
RUN cp -r frontend/dist backend/client/

EXPOSE 8080
CMD ["node", "backend/index.js"]
```

3. docker-compose.yml:

```yaml
version: "3.8"
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - NODE_ENV=production
      - PORT=8080
      - OPENAI_KEY=your_key_here
```

## Vaihtoehto C: Erillinen Backend API

Backend toimii itsenäisenä API:na Rahdin Node.js samplen avulla rakennettuna. Frontend tarvitsee oman Dockerfilen, jos haluat vain kontittaa Vite-sovelluksen ja kutsua backend API:a.

### 1. Backend API:n käyttö

Backend toimii jo Rahdissa (esim. URL: https://backend-projektisi.rahtiapp.fi):

```javascript
const express = require("express");
const cors = require("cors");
const app = require("./app");
require("dotenv").config();

// CORS asetukset - lisää frontend URL
app.use(
  cors({
    origin: ["https://frontend-projektisi.rahtiapp.fi"],
  })
);

// API reitit...
app.get("/api/status", (req, res) => {
  res.json({ status: "ok" });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

> **Paras käytäntö:** Tietoturvan kannalta paras käytäntö Rahdissa on pitää backend-palvelu täysin sisäisenä ilman julkista reittiä. Tällöin frontend kutsuu backendiä sisäisen service-nimen kautta (esim. `http://backend-service-name:8080`). Kun määrittelet backendin palveluksi ilman reittejä (routes), se on saavutettavissa vain Rahti-projektin sisällä. Frontend-sovelluksessa voit määrittää ympäristömuuttujan `API_URL=http://backend-service-name:8000` osoittamaan sisäiseen palveluun.

### 2. Frontend setup (Vite)

1. Lisää Dockerfile frontend-kansioon:

```dockerfile
# Build vaihe
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Tuotantovaihe
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
RUN npm install -g serve
EXPOSE 8080
CMD ["serve", "-s", "dist", "-p", "8080"]
```

### Serve-työkalun käyttö

- Dockerfilessa käytetty komento `serve -s dist` on tarkoitettu SPA-sovelluksille
- `-s` tai `--single` lippu:
  - Ohjaa kaikki pyynnöt index.html:ään
  - Välttämätön SPA-reitityksen toiminnalle (React Router, Vue Router jne.)
- **Jos sovelluksesi EI ole SPA:**
  - Poista `-s` lippu komennosta
  - Käytä: `CMD ["serve", "dist", "-p", "8080"]`
  - Soveltuu tavallisille staattisille sivuille (multi-page)

2. Lisää .dockerignore frontend-kansioon:

```
node_modules
dist
.env
```

3. Määritä backendin URL frontendissä:

```javascript
// src/config.js
export const BACKEND_URL =
  import.meta.env.VITE_BACKEND_URL || "http://localhost:8080";

// Käyttö komponenteissa
const response = await fetch(`${BACKEND_URL}/api/endpoint`, {
  method: "POST",
  body: formData,
});
```

### Huomioita

- Frontend käyttää porttia 8080 (Rahdin vaatimus tässä esimerkissä)
- CORS-asetusten pitää sallia frontend URL
- Rahti luo automaattisesti julkisen URL:n frontendille

### Ympäristömuuttujat ja Tietoturva

- **API-reittien suojaus:** Käytä aina asianmukaista suojausta
  - API-avain (VITE_API_KEY)
  - JWT token
  - Muut autentikaatiomenetelmät

```env
VITE_BACKEND_URL=https://backend-projektisi.rahtiapp.fi
VITE_API_KEY=your-secret-api-key
```

## Yhteenveto

Valitse ratkaisu tarpeidesi mukaan:

A. **Yksinkertainen ratkaisu**: Vie Vite build backendiin

- Helpoin toteuttaa
- Ei vaadi Dockeria
- Kaikki yhdessä palvelussa

B. **Docker-ratkaisu**: Yhdistä frontend ja backend

- Monorepo-lähestymistapa
- Helppo ylläpitää
- Hyvä kehitysympäristö

C. **Erillinen API**: Pidä frontend ja backend erillään

- Selkeä jako palveluiden välillä
- Skaalautuu hyvin
- Vaatii CORS-konfiguraation

Tärkeimmät muistettavat asiat:

1. Käytä oikeaa porttia Rahdissa. Tässä esimerkissä 8080
2. Määrittele API-polut oikein
3. Huomioi CORS-asetukset tarvittaessa

## API-polkujen käyttö

### Yhdistetyssä ratkaisussa (Vaihtoehdot A ja B):

```javascript
// Käytä suhteellisia polkuja
const response = await fetch("/api/endpoint", {
  method: "POST",
  body: formData,
});
```

### Erillisessä API-ratkaisussa (Vaihtoehto C):

```javascript
// Käytä täyttä URL:ia konfiguraatiosta
const response = await fetch(`${BACKEND_URL}/api/endpoint`, {
  method: "POST",
  body: formData,
});
```

## Automatisointi monorepo-ympäristössä

```
monorepo/
├── package.json           # Päätason package.json
├── node_modules/
├── frontend/             # Frontend-projekti
│   ├── package.json
│   ├── src/
│   └── dist/            # Build-kansio
└── backend/             # Backend-projekti
    ├── package.json
    ├── src/
    └── client/          # Frontend build kopioidaan tänne
        └── dist/
```

Jos pidät frontendin ja backendin samassa repositoriossa, voit automatisoida build-prosessin lisäämällä seuraavan scriptin päätason package.json tiedostoon:

```json
{
  "scripts": {
    "build:frontend": "cd frontend && npm install && npm run build",
    "postbuild:frontend": "rm -rf backend/client/dist && cp -r frontend/dist backend/client/",
    "prebuild": "npm install",
    "build": "npm run build:frontend",
    "start": "cd backend && npm start"
  }
}
```

Tämä mahdollistaa:

1. Frontendin buildauksen
2. Buildin automaattisen kopioinnin backend/client -kansioon
3. Koko prosessin ajamisen yhdellä komennolla: `npm run build`

# Rahti-sovelluksen URL-osoitteen (Route) muuttaminen

Rahtissa voit lisätä uuden URL-osoitteen tai muuttaa olemassa olevan sovelluksen URL-osoitetta luomalla uuden Route-objektin. Useita reittejä voi osoittaa samaan palveluun eri hostname-osoitteilla.

## YAML-tiedosto menetelmä (Suositeltu)

### Vaihe 1: Luo YAML-tiedosto uutta reittiä varten

Luo tiedosto nimeltä `uusi-reitti.yaml` seuraavalla sisällöllä:

```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: <reitin-nimi>
  namespace: <nimiavaruus>
  labels:
    app: <sovelluksen-nimi>
    app.kubernetes.io/component: <sovelluksen-nimi>
    app.kubernetes.io/instance: <sovelluksen-nimi>
    app.kubernetes.io/name: <sovelluksen-nimi>
    app.kubernetes.io/part-of: <projektin-nimi>
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: <kustomoitu-nimi>.2.rahtiapp.fi
  to:
    kind: Service
    name: <palvelun-nimi>
    weight: 100
  port:
    targetPort: <portti>-tcp
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

Korvaa:

- `<reitin-nimi>`: Reittiobjektin nimi
- `<nimiavaruus>`: Projektisi nimiavaruus
- `<sovelluksen-nimi>`: Sovelluksesi nimi
- `<projektin-nimi>`: Projektisi nimi
- `<kustomoitu-nimi>`: Haluamasi URL-etuliite
- `<palvelun-nimi>`: Palvelun nimi johon reitti yhdistetään
- `<portti>`: Porttinumero jota palvelusi käyttää (esim. 3000, 8080)

### Vaihe 2: Luo uusi reitti

1. Varmista ensin, että olet oikeassa projektissa:

```bash
oc project
```

2. Luo sitten uusi reitti:

```bash
oc create -f uusi-reitti.yaml
```

### Vaihe 3: Testaa uutta reittiä

Käy uudessa URL-osoitteessasi varmistaaksesi että se toimii oikein

### Vaihe 4: Halutessasi poista vanha reitti

Jos et enää tarvitse vanhaa reittiä, voit poistaa sen:

```bash
oc delete route <vanhan-reitin-nimi> -n <nimiavaruus>
```

**Huom:** Voit pitää useita reittejä aktiivisena samanaikaisesti. Jokaisella reitillä voi olla eri hostname-osoite, vaikka ne osoittavat samaan palveluun. Tämä mahdollistaa sekä vanhojen että uusien URL-osoitteiden pitämisen aktiivisena siirtymävaiheiden aikana.

## Esimerkki

Sovellukselle "upbeat" jonka palvelun nimi on "upbeat" ja joka toimii portissa 3000:

```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: learning-assistant
  namespace: upbeat-apps
  labels:
    app: upbeat
    app.kubernetes.io/component: upbeat
    app.kubernetes.io/instance: upbeat
    app.kubernetes.io/name: upbeat
    app.kubernetes.io/part-of: learning-assistant
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: learning-assistant.2.rahtiapp.fi
  to:
    kind: Service
    name: upbeat
    weight: 100
  port:
    targetPort: 3000-tcp
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

**Huom:** Rahtin hostname-osoitteiden on päätyttävä `.2.rahtiapp.fi`-päätteeseen ja etuliitteen on oltava uniikki koko Rahti-ympäristössä.

## PostgreSQL+pgVector tietokannan asennus ja käyttö Rahdissa

### Tietokantakontin asennus CSC Rahti 2 -ympäristöön

PostgreSQL-tietokanta pgVector-laajennuksella voidaan asentaa Rahti-ympäristöön käyttäen Red Hat -yhteensopivaa konttikuvaa, joka on suunniteltu toimimaan OpenShift-ympäristössä.

1. Kirjaudu Rahti 2 -käyttöliittymään
2. Valitse projekti tai luo uusi
3. Valitse "Deploy Image" -toiminto
4. Valitse "Image name from external registry" ja syötä:
   ```
   quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s
   ```
5. Anna deploymentille nimi (esim. "postgresql-pgvector")
6. Määritä tarvittavat ympäristömuuttujat:
   - POSTGRESQL_USER=postgres
   - POSTGRESQL_PASSWORD=vahva_salasana
   - POSTGRESQL_DATABASE=vectordb
7. **ÄLÄ** luo Route-määritystä tietokannalle turvallisuussyistä

### Pysyvän tallennustilan lisääminen

Tietokanta tarvitsee pysyvän tallennustilan, jotta data säilyy podin uudelleenkäynnistysten välillä:

1. Avaa luomasi Deployment
2. Valitse "Actions" → "Add Storage"
3. Luo uusi PersistentVolumeClaim (PVC):
   - Nimi: "pgvector-data"
   - Access mode: Single user (RWO)
   - Koko: 5 GiB tai tarpeiden mukaan enemmän
   - Mount path: `/var/lib/pgsql/data`
4. Tallenna muutokset

## PgVector-laajennuksen käyttöönotto

Voit aktivoida pgVector-laajennuksen helposti pgAdmin-käyttöliittymän kautta:

1. **Yhdistä tietokantaan pgAdminilla** käyttäen port-forward-yhteyttä tai suoraa yhteyttä klusterin sisällä

2. **Laajenna palvelinyhteys** ja klikkaa oikealla hiiren painikkeella "Databases" valitaksesi "Create" → "Database..."
3. **Luo uusi tietokanta** (jos sitä ei ole vielä olemassa):

   - Anna nimeksi "vectordb"
   - Klikkaa "Save"

4. **Laajenna vectordb-tietokanta** ja klikkaa oikealla hiiren painikkeella "Extensions" → "Create" → "Extension..."

5. **Valitse pgVector-laajennus**:

   - Valitse pudotusvalikosta "vector"
   - Klikkaa "Save"

6. **Tarkista että laajennus on aktivoitu**:
   - Laajenna "Extensions"-kansio vectordb-tietokannan alla
   - Lista näyttää nyt "vector"-laajennuksen

Vaihtoehtoisesti voit myös suorittaa SQL-komennon pgAdminin kyselyikkunassa:

1. Avaa Query Tool (Työkalupalkista tai Ctrl+Shift+Q)
2. Kirjoita:

   ```sql
   CREATE EXTENSION vector;
   ```

3. Suorita kysely (F5 tai Execute-painike)

## PgVector-laajennuksen käyttö

Kun laajennus on aktivoitu, voit käyttää vektoriominaisuuksia:

```sql
-- Luo taulu vektoriominaisuudella (3-ulotteinen vektori)
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));

-- Lisää tauluun dataa
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');

-- Suorita vektorihaku (etsii lähimmät vektorit annetulle vektorille)
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

### Tietokannan hallinta pgAdmin-sovelluksella

PostgreSQL-tietokantaa voi hallita pgAdmin-sovelluksella käyttäen port-forward-yhteyttä:

1. Asenna pgAdmin paikallisesti (https://www.pgadmin.org/download/)

2. Luo port-forward-yhteys PostgreSQL-palveluun OpenShift CLI:n avulla:

   ```bash
   # Yhdistä ensin Rahtiin
   oc login

   # Valitse projekti
   oc project [projektin-nimi]

   # Luo port-forward-yhteys
   oc port-forward svc/postgresql-pgvector 5432:5432
   ```

   Jätä komentorivi-ikkuna auki, jotta yhteys säilyy.

3. Käynnistä paikallinen pgAdmin-sovellus ja luo uusi palvelinyhteys:

   - Nimi: Rahti PostgreSQL
   - Host: localhost (127.0.0.1)
   - Port: 5432
   - Maintenance database: vectordb
   - Username: postgres
   - Password: (määrittämäsi POSTGRESQL_PASSWORD)

4. Yhdistä ja aloita tietokannan hallinta.

### Tietokannan yhdistäminen sovellukseen Rahdissa

Kun sekä sovellus että PostgreSQL-tietokanta toimivat samassa Rahti-projektissa, sovellus voi yhdistää tietokantaan käyttäen palvelunimeä isäntänimenä:

```
DATABASE_URL=postgresql://postgres:salasana@postgresql-pgvector:5432/vectordb
```

Tämä yhteysosoite voidaan määrittää sovelluksen ympäristömuuttujissa.

### Huomioitavaa

- Port-forward-yhteys on tilapäinen ja katkaisee yhteyden, jos komentorivi suljetaan. Se on tarkoitettu lähinnä hallintakäyttöön.

# CSC Allas S3 Credentials Hakuohjeet

Tämä ohje kertoo miten saat haettua S3 credentials CSC Allas object storage palveluun Windows 11 ympäristössä.

**Nopea vaihtoehto:** Käytä valmista Python-skriptiä `get_s3_credentials.py` joka löytyy tämän projektin juurikansiosta (Vaihtoehto B). Skripti automatisoi koko prosessin ja hakee credentials yhdellä komennolla.

## Edellytykset

- ✅ CSC käyttäjätunnus ja projekti jossa Allas käytössä
- ✅ Python 3.8+ asennettu
- ✅ Pääsy CSC Pouta palveluun ([my.csc.fi](https://my.csc.fi))

## Vaihtoehto A: Manuaalinen credentials haku OpenStack CLI:llä

## Vaihtoehto B: Manuaalinen credentials haku OpenStack CLI:llä

### 1. Luo S3 Bucket Allas käyttöliittymässä

Ennen credentials hakua, luo tarvitsemasi bucket(s):

1. Kirjaudu [CSC Allas käyttöliittymään](https://allas.csc.fi/)
2. Valitse oikea projekti vasemmasta valikosta
3. Klikkaa **"+ Create bucket"** luodaksesi uuden bucketin
4. Anna bucketille yksilöllinen nimi

### Bucket nimeäminen

Bucket nimien tulee olla yksilöllisiä kaikille Allas käyttäjille. CSC suosittelee käyttämään projekti ID:tä nimessä, esim. `2000620-raw-data`. Käytä vain pieniä kirjaimia, numeroita ja viivoja - älä käytä ä, ö tai muita erikoismerkkejä.

### 2. Lataa clouds.yaml konfiguraatio

1. Kirjaudu sisään [CSC Pouta palveluun](https://pouta.csc.fi/)
2. Siirry **API Access** osioon
3. Klikkaa **Download OpenStack RC File** ja valitse **OpenStack clouds.yaml file**
4. Tallenna ladattu `clouds.yaml` tiedosto

### 3. Konfiguroi clouds.yaml

### Luo konfiguraatiokansio

```powershell
mkdir "$HOME\.config\openstack"
```

### Tallenna clouds.yaml tiedosto

Siirrä ladattu `clouds.yaml` tiedosto kansioon:

```
C:\Users\[käyttäjänimi]\.config\openstack\clouds.yaml
```

### Esimerkki clouds.yaml sisällöstä

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://pouta.csc.fi:5001/v3
      username: "käyttäjätunnus"
      project_id: "2fb68cf252gg40a8bv51d86d922f5977"
      project_name: "project_2111111"
      user_domain_name: "Default"
      # password: "salasana"  # Valinnainen - kysytään automaattisesti
    regions:
      - regionOne
    interface: "public"
    identity_api_version: 3
```

**Huom:** Salasanan voi jättää pois - ohjelma kysyy sitä automaattisesti.

### 4. Asenna OpenStack Client

### Asenna Python paketti

```powershell
python -m pip install --user python-openstackclient
```

### Korjaa PATH (tärkeää!)

OpenStack client ei välttämättä ole PATH:ssa asennuksen jälkeen. Lisää Python Scripts kansio PATH:iin:

```powershell
$env:PATH = "C:\Users\[käyttäjänimi]\AppData\Local\Programs\Python\Python313\Scripts;" + $env:PATH
```

**HUOM:** Polut vaihtelevat Python-asennuksen mukaan! Tarkista omat polkusi ensin komennolla:

```powershell
python -c "import sys; import os; print(os.path.dirname(sys.executable) + '\\Scripts')"
```

Käytä tulostunutta polkua yllä olevan komennon sijaan.

**Suosittelen asettamaan PATH:n pysyvästi:**

- Windows-näppäin + R → `sysdm.cpl`
- Advanced → Environment Variables
- System variables → PATH → Edit → New
- Lisää: Yllä selvittämäsi Scripts-kansion polku
- OK, OK, OK → Avaa uusi PowerShell

### Testaa asennus

```powershell
openstack.exe --version
```

Pitäisi näyttää jotain kuten: `openstack 8.1.0`

### 5. Hae S3 Credentials

### Tarkista ja vaihda projektia tarvittaessa

Ennen S3 credentials luomista, varmista että olet oikeassa projektissa:

### Tarkista nykyinen projekti

```powershell
openstack.exe configuration show
```

Etsi rivi `auth.project_id` - tämän arvon pitää täsmätä Object Store endpoint URL:n kanssa. Object Store URL:ssa näkyy muodossa: `AUTH_[project-id]`

### Listaa käytettävissä olevat projektit

```powershell
openstack.exe project list
```

### Vaihda projektia

Jos et ole oikeassa projektissa:

```powershell
openstack.exe project set [projektin-nimi]
```

Esim: `openstack.exe project set project_2013111`

### Varmista projektin vaihto

```powershell
openstack.exe project show [projektin-nimi]
```

**TÄRKEÄÄ:** S3 credentials ja buckets ovat projektikohtaisia. Varmista että luot credentials samassa projektissa kuin missä bucket sijaitsee!

### Aseta cloud environment

```powershell
$env:OS_CLOUD = "openstack"
```

### Listaa olemassa olevat credentials

```powershell
openstack.exe ec2 credentials list
```

Ohjelma kysyy CSC salasanaasi. Syötä se ja saat listan olemassa olevista S3 credentials:

```
+----------------------------------+----------------------------------+----------------------------------+----------+
| Access                           | Secret                           | Project ID                       | User ID  |
+----------------------------------+----------------------------------+----------------------------------+----------+
| abc123def456ghi789jkl012mno345pq | xyz789uvw456rst123qpo890lmn567abc | def456abc789ghi012jkl345mno678pqr | käyttäjä |
+----------------------------------+----------------------------------+----------------------------------+----------+
```

### Luo uudet credentials (jos tarvitaan)

Jos sinulla ei ole olemassa olevia credentials:

```powershell
openstack.exe ec2 credentials create
```

### 6. Tallenna Credentials

Kopioi **Access** ja **Secret** arvot ja tallenna ne turvallisesti. Voit käyttää niitä environment variableina:

```powershell
$env:ALLAS_ACCESS_KEY_ID="abc123def456ghi789jkl012mno345pq"
$env:ALLAS_SECRET_ACCESS_KEY="xyz789uvw456rst123qpo890lmn567abc"
$env:ALLAS_ENDPOINT_URL="https://a3s.fi"
$env:ALLAS_BUCKET_NAME="your-bucket-name"
```

### 7. Käyttö koodissa

### Python (boto3)

```python
import boto3
import os

# Asenna: pip install boto3
s3 = boto3.client(
    's3',
    endpoint_url=os.getenv('ALLAS_ENDPOINT_URL'),
    aws_access_key_id=os.getenv('ALLAS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('ALLAS_SECRET_ACCESS_KEY'),
    region_name='regionOne'
)

# Listaa buckets
buckets = s3.list_buckets()
for bucket in buckets['Buckets']:
    print(f"Bucket: {bucket['Name']}")

# Upload tiedosto
bucket_name = os.getenv('ALLAS_BUCKET_NAME')
s3.upload_file('local_file.txt', bucket_name, 'remote_file.txt')

# Download tiedosto
s3.download_file(bucket_name, 'remote_file.txt', 'downloaded_file.txt')
```

### JavaScript (Node.js)

```javascript
import {
  S3Client,
  ListBucketsCommand,
  PutObjectCommand,
} from "@aws-sdk/client-s3";

// Asenna: npm install @aws-sdk/client-s3
const s3Client = new S3Client({
  endpoint: process.env.ALLAS_ENDPOINT_URL,
  region: "regionOne",
  credentials: {
    accessKeyId: process.env.ALLAS_ACCESS_KEY_ID,
    secretAccessKey: process.env.ALLAS_SECRET_ACCESS_KEY,
  },
});

// Listaa buckets
const { Buckets } = await s3Client.send(new ListBucketsCommand({}));
Buckets.forEach((bucket) => console.log(`Bucket: ${bucket.Name}`));

// Upload
const uploadParams = {
  Bucket: process.env.ALLAS_BUCKET_NAME,
  Key: "test-file.txt",
  Body: "Hello Allas!",
};
await s3Client.send(new PutObjectCommand(uploadParams));
```

### 8. .env tiedosto (suositeltu)

Luo projektikansioon `.env` tiedosto:

```ini
ALLAS_ACCESS_KEY_ID=abc123def456ghi789jkl012mno345pq
ALLAS_SECRET_ACCESS_KEY=xyz789uvw456rst123qpo890lmn567abc
ALLAS_ENDPOINT_URL=https://a3s.fi
ALLAS_BUCKET_NAME=your-bucket-name
```

**Muista lisätä `.env` tiedosto `.gitignore`:een turvallisuuden vuoksi!**

## Vaihtoehto B: Automaattinen credentials haku Python-skriptillä

Projektin juurikansiossa on valmis `get_s3_credentials.py` skripti, joka automatisoi koko prosessin:

### 1. Asenna tarvittavat Python-paketit

```bash
pip install keystoneauth1 python-keystoneclient pyyaml
```

### 2. Lataa clouds.yaml konfiguraatio

1. Kirjaudu [CSC Pouta palveluun](https://pouta.csc.fi/)
2. Siirry **API Access** osioon
3. Klikkaa **Download OpenStack RC File** ja valitse **OpenStack clouds.yaml file**
4. Tallenna ladattu tiedosto nimellä `clouds.yaml` johonkin seuraavista paikoista:
   - `~/.config/openstack/clouds.yaml` (suositeltu)
   - `~/clouds.yaml`
   - Projektin juurikansioon `./clouds.yaml`

### 3. Suorita Python-skripti

```bash
python get_s3_credentials.py
```

Skripti:

- Kysyy CSC salasanasi
- Listaa olemassa olevat S3 credentials
- Luo uudet credentials jos tarpeellista
- Näyttää Access Key ja Secret Key jotka voit kopioida sovellukseesi

### 4. Kopioi credentials sovellukseesi

Skripti näyttää credentials muodossa:

```
Access Key: abc123def456ghi789jkl012mno345pq
Secret Key: xyz789uvw456rst123qpo890lmn567abc
Endpoint: https://a3s.fi
Region: regionOne
```

## Vianmääritys

### openstack komento ei toimi

Jos saat virheen `openstack : The term 'openstack' is not recognized`:

1. Tarkista Python Scripts kansion sijainti:

   ```powershell
   python -c "import sys; print(sys.executable)"
   ```

   Lisää `\Scripts\` loppuun ja aseta se PATH:iin.

2. Kokeile täydellä polulla:
   ```powershell
   "C:\Users\[käyttäjä]\AppData\Local\Programs\Python\Python313\Scripts\openstack.exe" --version
   ```

### pip ei toimi

Käytä Python modulina:

```powershell
python -m pip install python-openstackclient
```

## Region tiedot

**Huom:** CSC Allas käyttää `regionOne` nimenä - tätä ei voi vaihtaa. Vaikka palvelu sijaitsee Suomessa, region nimi on aina `regionOne`, ei `eu-north-1` tai vastaava.

## Endpoint tiedot

| Palvelu   | Endpoint                                        | Region      |
| --------- | ----------------------------------------------- | ----------- |
| S3 API    | `https://a3s.fi`                                | `regionOne` |
| Swift API | `https://a3s.fi:443/swift/v1/AUTH_[PROJECT_ID]` | `regionOne` |

---

**Hyödyllisiä linkkejä:**

- [CSC Allas käyttöliittymä](https://allas.csc.fi/)
- [CSC Allas dokumentaatio](https://docs.csc.fi/data/Allas/)
- [CSC Pouta](https://pouta.csc.fi/)
- [CSC How to get Allas S3 credentials](https://docs.csc.fi/support/faq/how-to-get-Allas-s3-credentials/)
