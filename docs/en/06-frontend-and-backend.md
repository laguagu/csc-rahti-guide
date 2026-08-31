# 6. Frontend and backend on Rahti

> Three ways to deploy a React (Vite) + Node.js app, and how to wire the services
> together.

## Contents

- [Choose an architecture](#choose-an-architecture)
- [Option A: one service, backend serves the frontend](#option-a-one-service-backend-serves-the-frontend)
- [Option B: monorepo in a single container](#option-b-monorepo-in-a-single-container)
- [Option C: separate services](#option-c-separate-services)
- [API paths across the models](#api-paths-across-the-models)
- [CORS](#cors)
- [The framework does not matter](#the-framework-does-not-matter)
- [Health checks and Basic Auth](#health-checks-and-basic-auth)
- [Ports](#ports)

## Choose an architecture

| | A: One service | B: Monorepo, one container | C: Separate services |
| --- | --- | --- | --- |
| Containers | 1 | 1 | 2+ |
| CORS needed | no | no | yes (or an internal call) |
| Scales independently | no | no | yes |
| Deploy complexity | low | low | medium |
| Fits | small app, demo | team monorepo | production, different stacks |

If you can't decide: start with **A** or **B** and move to **C** once the frontend and
backend start evolving at different paces.

## Option A: one service, backend serves the frontend

Build the frontend as static files and let the backend serve them. One port, one
address, no CORS.

```bash
cd frontend && npm run build          # produces dist/
cp -r dist ../backend/client/dist     # the backend's static folder
```

```javascript
// backend/index.js
const express = require("express");
const path = require("path");
const app = require("./app");

// Static frontend
app.use(express.static(path.join(__dirname, "client/dist")));

// This MUST come AFTER the API routes — otherwise it also catches /api calls
// app.use works in both Express 4 and 5 (see the note below).
app.use((req, res) => {
  res.sendFile(path.join(__dirname, "client/dist", "index.html"));
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`Server running on ${PORT}`));
```

> **Express 5 broke `app.get("*")`.** Guides online almost always write the SPA fallback
> route as `app.get("*", …)`. That works in Express 4 but **throws in Express 5** with
> `TypeError: Missing parameter name`. Express 5 is the default on npm, so a fresh
> `npm install express` gets it. The `app.use` above works in both; if you specifically
> want a route, the Express 5 form is `app.get("/*splat", …)`.

In a monorepo, it's worth automating the copy step in the root `package.json`:

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

## Option B: monorepo in a single container

Same end result as A, but the copying happens in the Dockerfile, so no local build
step is needed.

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

> `docker-compose.yml` is handy for local development, but **Rahti does not run
> compose files**. It reads the Dockerfile and Kubernetes manifests.

## Option C: separate services

The frontend and backend are their own Deployments. The key decision: **give the
backend a Route or not.**

```
Internet ──► Route ──► frontend-Service ──► frontend-Pod
                                                 │  http://backend-api:8000
                                                 ▼
                                          backend-Service ──► backend-Pod
                                          (no Route = not visible to the internet)
```

Internal call using the service name:

```bash
oc set env deployment/frontend -n <project> \
  BACKEND_URL=http://backend-api:8000
```

```javascript
// In server-side code (Next.js route handler, Express proxy, …)
const backendUrl = process.env.BACKEND_URL || "http://localhost:8000";
const res = await fetch(`${backendUrl}/api/data`);
```

**Frontend Dockerfile (Vite, static serving):**

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
RUN npm install -g serve &&     chown -R 1001:0 /app && chmod -R g+rwX /app
USER 1001
EXPOSE 8080
CMD ["serve", "-s", "dist", "-p", "8080"]
```

`serve -s` (single) routes every path to `index.html`, which is required for
client-side routing (React Router). **If the app is not an SPA**, drop the `-s`:
`CMD ["serve", "dist", "-p", "8080"]`.

Remember `.dockerignore`:

```
node_modules
dist
.env
```

> **A call made from the browser can't use the internal name.** `http://backend-api:8000`
> only works from inside a pod. If the frontend is fully static and calls the API from
> the browser, the backend needs either its own Route (and CORS) or a server-side proxy
> on the frontend.

## API paths across the models

**A and B — same origin, use relative paths:**

```javascript
const res = await fetch("/api/endpoint", { method: "POST", body: formData });
```

**C — full URL from configuration:**

```javascript
// src/config.js
export const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:8080";
```

Remember: `VITE_*` is baked into the bundle at build time (see
[05 Environment variables](05-environment-variables.md#build-time-vs-runtime)) — never
put secrets there.

## CORS

CORS only applies to calls made by the **browser** to a different origin. A `fetch` from
the server side (a Next.js route handler, an Express proxy, anything leaving the pod)
ignores CORS entirely.

**The same parent domain does not mean the same origin.**
`https://frontend.2.rahtiapp.fi` and `https://backend.2.rahtiapp.fi` are different
origins, because an origin is scheme + the full hostname + port. Sharing the
`.2.rahtiapp.fi` suffix does not help.

**The best solution is to avoid CORS altogether:** don't give the backend a Route, and
call it from the frontend's server using the internal name (`http://backend-api:8000`).
Then the browser only ever sees one origin, no CORS is needed, and the backend is not on
the internet.

If the backend does need a public Route:

```javascript
app.use(
  cors({
    origin: ["https://frontend.2.rahtiapp.fi"],
    credentials: true,
  })
);
```

### Three things that break CORS on Rahti

1. **`origin: "*"` and `credentials: true` do not work together.** This is not a matter
   of style: the browser rejects a response carrying `Access-Control-Allow-Origin: *`
   if the request was made in `credentials: "include"` mode. List the origins
   explicitly.

2. **The preflight request is forgotten.** A call carrying an `Authorization` header or
   `Content-Type: application/json` makes the browser send an `OPTIONS` request first.
   If the backend does not answer it with a 2xx and the right headers, the actual
   request is never sent. Test it separately:

   ```bash
   curl -i -X OPTIONS https://backend.2.rahtiapp.fi/api/data      -H "Origin: https://frontend.2.rahtiapp.fi"      -H "Access-Control-Request-Method: POST"      -H "Access-Control-Request-Headers: content-type"
   ```

   The expected response is 204 or 200 with `Access-Control-Allow-Origin` present.

3. **Authentication kills the preflight.** The browser does **not** send cookies or an
   `Authorization` header on a preflight request. If the app requires a login on every
   path (Basic Auth, middleware), `OPTIONS` gets a 401 and the whole call fails. Let
   `OPTIONS` through the authentication. Same trap as the health checks below.

> The browser console error *"No 'Access-Control-Allow-Origin' header is present"*
> usually means one of these three, not that the `cors()` call is missing entirely.

## Health checks and Basic Auth

Rahti expects the pod to signal that it's ready. Two approaches:

```yaml
# Open /health path — the best option
readinessProbe:
  httpGet: { path: /health, port: 8000 }

# The app is entirely behind authentication — an HTTP check would get a 401
readinessProbe:
  tcpSocket: { port: 3000 }
```

> **This is a real pitfall.** If the app (e.g. Next.js middleware or `proxy.ts`)
> requires Basic Auth on **every** path, the `httpGet` check gets a 401, the pod never
> reaches Ready, and the rollout hangs forever. Use either a `tcpSocket` check or exempt
> `/health` from authentication.

## The framework does not matter

The examples use Express and Vite because they are the most familiar, but Rahti knows
nothing about frameworks. Hono, Fastify, NestJS, FastAPI, Flask, Spring Boot, Go, Rust
or anything else works, as long as the container meets these four conditions:

1. listens on `0.0.0.0`, not `127.0.0.1`
2. reads the port from the `PORT` environment variable, or uses a fixed port above 1024
3. does not require root or a specific UID
4. serves some path the health probe can fetch without authentication

Hono on Node, for example:

```javascript
import { serve } from "@hono/node-server";
import { Hono } from "hono";

const app = new Hono();
app.get("/health", (c) => c.json({ status: "ok" }));

serve({ fetch: app.fetch, port: Number(process.env.PORT) || 8080, hostname: "0.0.0.0" });
```

Everything else in this guide (Dockerfile, Service, Route, secrets) is exactly the same
regardless of what you wrote inside.

## Ports

- The app must listen on **`0.0.0.0`**, not `127.0.0.1` — otherwise traffic can't
  reach it from outside the pod.
- The port number itself doesn't matter (3000, 8000, 8080), as long as the same value
  is used in the Dockerfile's `EXPOSE`, the Deployment's `containerPort`, the Service's
  `targetPort`, and the Route's `targetPort`.
- Don't use a port below 1024. A random UID cannot bind a privileged port without the
  `NET_BIND_SERVICE` capability, the only one Rahti lets you add back. Listening on 8080
  is the easier route.
- Read the port from an environment variable where possible:
  `const PORT = process.env.PORT || 8080`.

---

**Previous:** [5. Environment variables](05-environment-variables.md) · **Next:** [7. Database and pgvector →](07-database.md)
