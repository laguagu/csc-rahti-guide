# 6. Frontend ja backend Rahdissa

> Kolme tapaa julkaista React (Vite) + Node.js -sovellus, ja miten palvelut kannattaa
> kytkeä toisiinsa.

## Sisällys

- [Valitse arkkitehtuuri](#valitse-arkkitehtuuri)
- [Vaihtoehto A: yksi palvelu, backend tarjoilee frontendin](#vaihtoehto-a-yksi-palvelu-backend-tarjoilee-frontendin)
- [Vaihtoehto B: monorepo yhdessä kontissa](#vaihtoehto-b-monorepo-yhdessä-kontissa)
- [Vaihtoehto C: erilliset palvelut](#vaihtoehto-c-erilliset-palvelut)
- [API-polut eri malleissa](#api-polut-eri-malleissa)
- [CORS](#cors)
- [Terveystarkistukset ja Basic Auth](#terveystarkistukset-ja-basic-auth)
- [Portit](#portit)

## Valitse arkkitehtuuri

| | A: Yksi palvelu | B: Monorepo, yksi kontti | C: Erilliset palvelut |
| --- | --- | --- | --- |
| Kontteja | 1 | 1 | 2+ |
| CORS tarvitaan | ei | ei | kyllä (tai sisäinen kutsu) |
| Skaalautuu erikseen | ei | ei | kyllä |
| Deploy-monimutkaisuus | pieni | pieni | keskitaso |
| Sopii | pieni sovellus, demo | tiimin monorepo | tuotanto, eri teknologiat |

Jos et osaa päättää: aloita **A**:sta tai **B**:stä ja siirry **C**:hen kun frontend ja
backend alkavat elää eri tahtia.

## Vaihtoehto A: yksi palvelu, backend tarjoilee frontendin

Buildaa frontend staattiseksi ja anna backendin tarjoilla se. Yksi portti, yksi
osoite, ei CORSia.

```bash
cd frontend && npm run build          # tuottaa dist/
cp -r dist ../backend/client/dist     # backendin staattinen kansio
```

```javascript
// backend/index.js
const express = require("express");
const path = require("path");
const app = require("./app");

// Staattinen frontend
app.use(express.static(path.join(__dirname, "client/dist")));

// TÄMÄN on oltava API-reittien JÄLKEEN, muuten se nappaa myös /api-kutsut.
// app.use toimii sekä Expressissä 4 että 5 (ks. huomio alla).
app.use((req, res) => {
  res.sendFile(path.join(__dirname, "client/dist", "index.html"));
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`Server running on ${PORT}`));
```

> **Express 5 rikkoi `app.get("*")`.** Netin ohjeissa SPA:n fallback-reitti kirjoitetaan
> lähes aina muotoon `app.get("*", …)`. Se toimii Expressissä 4, mutta **kaatuu Expressissä
> 5** virheeseen `TypeError: Missing parameter name`. Express 5 on npm:n oletusversio, eli
> tuore `npm install express` saa sen. Yllä oleva `app.use` toimii molemmissa; jos haluat
> nimenomaan reitin, Express 5:n muoto on `app.get("/*splat", …)`.

Monorepossa kopiointi kannattaa automatisoida juuren `package.json`-tiedostoon:

```json
{
  "scripts": {
    "build:frontend": "cd frontend && npm install && npm run build",
    "postbuild:frontend": "rm -rf backend/client/dist && cp -r frontend/dist backend/client/",
    "build": "npm run build:frontend",
    "start": "cd backend && npm start"
  }
}
```

## Vaihtoehto B: monorepo yhdessä kontissa

Sama lopputulos kuin A:ssa, mutta kopiointi tapahtuu Dockerfilessa, joten paikallista
build-vaihetta ei tarvita.

```
project/
├── backend/       (index.js, package.json)
├── frontend/      (src/, package.json)
└── Dockerfile
```

```dockerfile
# --- Build ---
FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
COPY frontend/package*.json ./frontend/
COPY backend/package*.json ./backend/
RUN cd frontend && npm ci && cd ../backend && npm ci
COPY . .
RUN cd frontend && npm run build
RUN mkdir -p backend/client && cp -r frontend/dist backend/client/

# --- Runtime ---
FROM node:24-alpine
WORKDIR /app
COPY --from=builder /app/backend ./backend
RUN chown -R 1001:0 /app && chmod -R g+rwX /app
USER 1001
EXPOSE 8080
CMD ["node", "backend/index.js"]
```

> `docker-compose.yml` on kätevä paikalliseen kehitykseen, mutta **Rahti ei aja
> compose-tiedostoja**. Se lukee Dockerfilen ja Kubernetes-manifestit.

## Vaihtoehto C: erilliset palvelut

Frontend ja backend ovat omia Deploymenttejaan. Tärkein päätös: **anna backendille
Route vai ei.**

```
Internet ──► Route ──► frontend-Service ──► frontend-Pod
                                                 │  http://backend-api:8000
                                                 ▼
                                          backend-Service ──► backend-Pod
                                          (ei Routea = ei näy internetiin)
```

Sisäinen kutsu palvelunimellä:

```bash
oc set env deployment/frontend -n <projekti> \
  BACKEND_URL=http://backend-api:8000
```

```javascript
// Palvelinpuolen koodissa (Next.js route handler, Express-proxy, …)
const backendUrl = process.env.BACKEND_URL || "http://localhost:8000";
const res = await fetch(`${backendUrl}/api/data`);
```

**Frontendin Dockerfile (Vite, staattinen tarjoilu):**

```dockerfile
FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:24-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
RUN npm install -g serve
EXPOSE 8080
CMD ["serve", "-s", "dist", "-p", "8080"]
```

`serve -s` (single) ohjaa kaikki polut `index.html`:ään, mikä on välttämätöntä
client-side-reitityksessä (React Router). **Jos sovellus ei ole SPA**, jätä `-s` pois:
`CMD ["serve", "dist", "-p", "8080"]`.

Muista `.dockerignore`:

```
node_modules
dist
.env
```

> **Selaimesta tehtävä kutsu ei voi käyttää sisäistä nimeä.** `http://backend-api:8000`
> toimii vain podin sisältä. Jos frontend on täysin staattinen ja kutsuu API:a selaimesta,
> backend tarvitsee joko oman Routen (ja CORSin) tai frontendin palvelinpuolen proxyn.

## API-polut eri malleissa

**A ja B — sama origin, käytä suhteellisia polkuja:**

```javascript
const res = await fetch("/api/endpoint", { method: "POST", body: formData });
```

**C — täysi URL konfiguraatiosta:**

```javascript
// src/config.js
export const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:8080";
```

Muista: `VITE_*` paistetaan bundleen build-aikana (ks.
[05 Ympäristömuuttujat](05-ymparistomuuttujat.md#build-aika-vs-ajonaika)) — sinne ei
laiteta salaisuuksia.

## CORS

CORS koskee vain **selaimen** tekemiä kutsuja eri originiin. Palvelinpuolelta tehty
`fetch` (Next.js route handler, Express-proxy, mikä tahansa podista lähtevä kutsu) ei
välitä CORSista lainkaan.

**Sama päädomain ei tarkoita samaa originia.** `https://frontend.2.rahtiapp.fi` ja
`https://backend.2.rahtiapp.fi` ovat eri origineja, koska origin on protokolla + koko
hostname + portti. Jaettu `.2.rahtiapp.fi`-pääte ei auta.

**Paras ratkaisu on välttää CORS kokonaan:** älä anna backendille Routea, vaan kutsu
sitä frontendin palvelimelta sisäisellä nimellä (`http://backend-api:8000`). Silloin
selain näkee vain yhden originin, CORSia ei tarvita ja backend ei ole internetissä.

Jos backend kuitenkin tarvitsee julkisen Routen:

```javascript
app.use(
  cors({
    origin: ["https://frontend.2.rahtiapp.fi"],
    credentials: true,
  })
);
```

### Kolme asiaa jotka kaatavat CORSin Rahdissa

1. **`origin: "*"` ja `credentials: true` eivät toimi yhdessä.** Tämä ei ole
   tyyliseikka: selain hylkää vastauksen, jossa on `Access-Control-Allow-Origin: *`,
   jos pyyntö tehtiin `credentials: "include"` -tilassa. Listaa originit
   eksplisiittisesti.

2. **Preflight-pyyntö unohtuu.** Kutsu, jossa on `Authorization`-header tai
   `Content-Type: application/json`, saa selaimen lähettämään ensin `OPTIONS`-pyynnön.
   Jos backend ei vastaa siihen 2xx-koodilla ja oikeilla headereilla, varsinaista
   pyyntöä ei koskaan lähetetä. Testaa erikseen:

   ```bash
   curl -i -X OPTIONS https://backend.2.rahtiapp.fi/api/data      -H "Origin: https://frontend.2.rahtiapp.fi"      -H "Access-Control-Request-Method: POST"      -H "Access-Control-Request-Headers: content-type"
   ```

   Odotettu vastaus on 204 tai 200 ja mukana `Access-Control-Allow-Origin`.

3. **Autentikointi tappaa preflightin.** Selain **ei** lähetä evästeitä eikä
   `Authorization`-headeria preflight-pyynnössä. Jos sovellus vaatii kirjautumisen
   kaikilla poluilla (Basic Auth, middleware), `OPTIONS` saa 401:n ja koko kutsu
   epäonnistuu. Päästä `OPTIONS` läpi autentikoinnista. Sama ansa kuin
   terveystarkistuksissa alla.

> Selainkonsolin virhe *"No 'Access-Control-Allow-Origin' header is present"* tarkoittaa
> useimmiten yhtä näistä kolmesta, ei sitä että `cors()`-kutsu puuttuisi kokonaan.

## Terveystarkistukset ja Basic Auth

Rahti odottaa, että podi kertoo olevansa valmis. Kaksi tapaa:

```yaml
# Avoin /health-polku — paras vaihtoehto
readinessProbe:
  httpGet: { path: /health, port: 8000 }

# Sovellus on kokonaan autentikoinnin takana — HTTP-tarkistus saisi 401
readinessProbe:
  tcpSocket: { port: 3000 }
```

> **Tämä on aito sudenkuoppa.** Jos sovellus (esim. Next.js middleware tai
> `proxy.ts`) vaatii Basic Authin **kaikilla** poluilla, `httpGet`-tarkistus saa 401,
> podi ei koskaan siirry Ready-tilaan ja rullaus jää roikkumaan ikuisesti. Käytä joko
> `tcpSocket`-tarkistusta tai jätä `/health` autentikoinnin ulkopuolelle.

## Portit

- Sovelluksen on kuunneltava **`0.0.0.0`**, ei `127.0.0.1` — muuten liikenne ei tule
  perille podin ulkopuolelta.
- Portin numerolla ei sinänsä ole väliä (3000, 8000, 8080), kunhan sama arvo on
  Dockerfilen `EXPOSE`ssa, Deploymentin `containerPort`issa, Servicen `targetPort`issa
  ja Routen `targetPort`issa.
- Älä käytä porttia alle 1024. Satunnainen UID ei saa sitoa etuoikeutettua porttia
  ilman `NET_BIND_SERVICE`-capabilityä, joka on ainoa jonka Rahdissa saa lisätä takaisin.
  Helpompi tapa on kuunnella 8080:aa.
- Lue portti ympäristömuuttujasta, jos mahdollista: `const PORT = process.env.PORT || 8080`.

---

**Edellinen:** [5. Ympäristömuuttujat](05-ymparistomuuttujat.md) · **Seuraava:** [7. Tietokanta ja pgvector →](07-tietokanta.md)
