---
name: csc-rahti
description: Deploy and manage applications on CSC's cloud — Rahti 2 (OpenShift/OKD container cloud), Satama (CSC's Harbor container image registry at satama.csc.fi), Allas S3 object storage, and CSC Aitta, CSC's OpenAI-compatible LLM inference API (Llama, gpt-oss, Poro 2, Gemma, Qwen3-VL, embeddings). Use when deploying Docker images to Rahti, building with ImageStreams or BuildConfigs, configuring routes and custom URLs, setting environment variables, connecting frontend and backend services, running PostgreSQL/pgvector, using `oc` CLI commands; when pushing, pulling, scanning or tagging images in Satama, creating Satama robot accounts or registry pull secrets; when reading or writing Allas buckets over S3 (`a3s.fi`); or when calling CSC's LLM API at `aitta-api.csc.fi`, listing/preloading Aitta models, or wiring `AITTA_API_TOKEN` / `AITTA_API_BASE` into an OpenAI-compatible client — even when the user only mentions OpenShift, OKD, `oc`, `*.2.rahtiapp.fi`, Harbor, Satama, Allas, Aitta, or "CSC LLM".
compatibility: Requires the `oc` CLI and a container tool (Docker or Podman). Bundled credential scripts (scripts/) are PowerShell 7+; equivalent plain `oc` commands are given inline for other shells.
---

# CSC Rahti 2 Deployment

CSC Rahti 2 is a container cloud based on OKD 4.x — the community distribution that Red Hat OpenShift is built on. This skill helps with common deployment workflows.

## Authentication

Two identities are in play. Know which one you are using:

| Identity | Lifetime | Use for |
|---|---|---|
| **Personal CSC login** (`oc login --token=sha256~…`) | ~24 h, needs MFA | Interactive work, first-time setup, granting rights |
| **Service account token** | Up to years, no MFA | Agents, scripts, CI — anything that must not stop to re-login |

**Personal login (start here):**
1. Go to [Rahti 2 console](https://console.rahti.csc.fi)
2. Click your name (top right) → **Copy login command**
3. Click **Display Token**, copy the `oc login …` line
4. Paste it into a terminal

**`error: You must be logged in to the server (Unauthorized)`** usually means the
personal token expired (about a day), or the kubeconfig `current-context` switched
back to the personal user. Check which identity is active before re-logging in:

```bash
oc whoami                 # personal username, or system:serviceaccount:<ns>:<name>
oc config current-context
```

**For recurring agent and CLI use, prefer a service account.** It has no MFA and a
token you choose the lifetime of:

```bash
oc create serviceaccount <sa-name> -n <namespace>
oc adm policy add-role-to-user edit system:serviceaccount:<namespace>:<sa-name> -n <namespace>
oc create token <sa-name> -n <namespace> --duration=8760h   # 1 year
```

Use `view` for read-only automation, `edit` for deploys, `admin` only if the agent
must manage RBAC too. Give a separate account per purpose — e.g. `system:image-pusher`
for a CI account that only pushes images.

The bundled PowerShell scripts wrap this whole lifecycle, storing the token outside
the repository in a private env directory (never in the skill, never in git):

```powershell
# Once, with a personal oc login active. -Force rotates an existing credential.
& "$PSScriptRoot\scripts\Initialize-RahtiCredential.ps1" -Namespace <namespace> -Role edit -Duration 8760h

# Later, on this or any synced machine — no MFA, no web console.
& "$PSScriptRoot\scripts\Connect-Rahti.ps1" -Namespace <namespace>
```

`Connect-Rahti.ps1` installs the stored token into the local kubeconfig and verifies
that the resulting identity is exactly the expected service account. If the stored
secret exists, an agent may run it without asking the user for a fresh token.

After editing either script, re-run the mocked test suite (no live cluster needed):
`pwsh -NoProfile -Command "& './tests/RahtiCredentials.Tests.ps1'"` from the skill root.

**An agent cannot:**
- Complete CSC MFA or fetch a personal login token from the web console
- Bootstrap or rotate a service-account credential without an already-privileged `oc` session
- Use an SSH key instead of OpenShift API authentication (SSH keys authenticate Git, not `oc`)

Full credential lifecycle, revocation and multi-machine notes: [references/authentication.md](references/authentication.md)

**Security (multi-tenant):**
- Containers cannot run as root
- Privileged mode disabled
- Arbitrary UID assignment (container may run as any UID)

**Key URLs:**
- Console: `https://console.rahti.csc.fi`
- Rahti internal image registry: `image-registry.apps.2.rahti.csc.fi`
- Satama registry (CSC-wide, Harbor): `satama.csc.fi` — UI <https://satama.csc.fi/harbor/projects>
- Route domain: `*.2.rahtiapp.fi`
- Egress IP: `86.50.229.150` (for firewall rules). **Caveat:** CSC warns this may change — if several Rahti versions are run in parallel, each has a different egress IP. Do not hard-code without a plan to update. Always verify current value at docs.csc.fi/cloud/rahti/networking/.

## Resource Limits (CSC Defaults)

Per-container defaults when a Deployment sets no `resources` block:

| Resource | Default |
|----------|---------|
| CPU request | 100m |
| CPU limit | 500m |
| Memory request | 500Mi |
| Memory limit | 1Gi |
| Max limit/request ratio | 5x |

The ceiling is the **CSC computing project quota** — initially 4 cores, 16 GiB RAM, 100 GiB storage — and it is *shared across every Rahti project* under that computing project, not a per-container maximum. Verify current values at [docs.csc.fi/cloud/rahti/usage/projects_and_quota/](https://docs.csc.fi/cloud/rahti/usage/projects_and_quota/).

**Check limits:**
```bash
oc describe limitranges -n <namespace>
```

**OOMKilled (error 137)?** Pod exceeded memory limit. Increase limit:
```bash
oc set resources deployment/<deployment> -n <namespace> --limits=memory=2Gi
```

**Need higher limits?** Contact CSC Service Desk: servicedesk@csc.fi

## Build & Push Docker Image

Three registry options — pick by how far the image has to travel:

| Registry | Use when |
|---|---|
| **Rahti internal** (`image-registry.apps.2.rahti.csc.fi`) | Fast inner loop inside one namespace. Default for `deploy.sh`. |
| **Satama** (`satama.csc.fi`) | Image is shared across projects/clusters/CI, or needs CVE scanning, signing, retention, long-lived robot credentials. |
| **DockerHub** | Public image, or no CSC project involvement. |

### Option A: Rahti Internal Registry (requires ImageStream)

```bash
# 1. Build image locally
docker build -t <image-name> .

# 2. Login to Rahti registry (requires active oc session)
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi

# 3. Tag for Rahti registry
docker tag <image-name> image-registry.apps.2.rahti.csc.fi/<namespace>/<image-name>:latest

# 4. Push to registry
docker push image-registry.apps.2.rahti.csc.fi/<namespace>/<image-name>:latest
```

ImageStream must exist before pushing. Create if needed:
```bash
oc create imagestream <name> -n <namespace>
```

**Bootstrap tip:** Push to DockerHub first → Rahti auto-creates the ImageStream on first deploy → then switch to Rahti registry for subsequent pushes.

### Option B: Satama — CSC's container registry (Harbor)

CSC's own registry at `satama.csc.fi`. Separate service from Rahti; the Rahti
internal registry is **not** deprecated by it. Login uses a **CLI secret**
(Satama UI → username → *User Profile* → *CLI Secret*), not the MyCSC password.

```bash
docker login satama.csc.fi -u <csc-username>          # paste CLI secret
docker tag  <image>:<tag> satama.csc.fi/<satama-project>/<image>:<tag>
docker push satama.csc.fi/<satama-project>/<image>:<tag>
```

Satama projects are named `project_<number>` (plus the shared public `library`);
they appear ~15 min after the CSC project has Satama enabled. Avoid `latest` for
anything promoted to production — Satama can enforce tag immutability and
retention.

Pulling into Rahti from a **private** Satama project needs a pull secret:

```bash
oc create secret docker-registry satama-pull --docker-server=satama.csc.fi \
  --docker-username='robot$<project>+<name>' --docker-password="$SATAMA_ROBOT_SECRET" -n <namespace>
oc secrets link default satama-pull --for=pull -n <namespace>
```

Public Satama projects pull anonymously, no secret needed. Robot accounts, CVE
scanning, signing, quota/billing and error table:
[references/satama-registry.md](references/satama-registry.md)

### Option C: DockerHub

```bash
docker tag <image-name> <dockerhub-username>/<image-name>:latest
docker push <dockerhub-username>/<image-name>:latest
```

**Placeholders:**
- `<image-name>`: Your Docker image name (e.g., `myapp`)
- `<namespace>`: Rahti project/namespace (e.g., `my-project`)

## Deploy via Web Console

1. Go to Rahti web console → your project
2. Click **Add → Container images**
3. In "Deploy Image":
   - Select "Deploy an existing Image from an Image Stream or Image registry"
   - Enter DockerHub image (`username/image:latest`) or choose from internal registry
4. Set **Target port** to match your app's listening port (e.g., 3000)
5. Set **Application** name and component **Name**
6. Rahti auto-generates a public HTTPS hostname

**Private DockerHub images:** Create an "Image pull secret" with registry `docker.io`, username and password before deploying.

**Deployment settings (after creation):**
- **Deployment strategy**: Rolling Update (recommended)
- **Auto deploy**: Enable "Auto deploy when new Image is available"
- **Environment Variables**: Add as Name/Value pairs in deployment settings

## Project-local deploy pattern (recommended for repeatable deploys)

For a repo you redeploy often, split **one-time declarative infra** from the **recurring image
loop**. This is cleaner than the web console and reproducible from git:

```
<repo>/openshift/
  manifests/            # declarative objects — `oc apply -f openshift/manifests/` ONCE
    00-imagestreams.yaml
    10-api-deployment.yaml   11-api-service.yaml
    20-web-deployment.yaml   21-web-service.yaml   22-web-route.yaml
  deploy.sh             # LEAN recurring loop: build → push → rollout (+ status)
```

- **One-time:** `oc apply -f openshift/manifests/` (objects) + `oc create secret generic … --from-literal=…` (credentials). Secrets are never committed; values come from a gitignored `.env.local`.
- **Recurring (every code change):** `./openshift/deploy.sh all` — `docker build` each image, push `:latest` + a timestamp tag, then patch a restart annotation and `oc rollout status`.
- The **`rahti-deploy` agent** just runs this `deploy.sh` end-to-end once an `oc` session exists (`Connect-Rahti.ps1`, or a personal login) — so the script is the source of truth; the agent is optional convenience. You can always deploy manually without it.

**Auto-rollout on push** — give each Deployment an image trigger so a new `:latest` push redeploys it (copy the format from any working Deployment via `oc get deploy <name> -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}'`):

```yaml
metadata:
  annotations:
    image.openshift.io/triggers: |
      [{"from":{"kind":"ImageStreamTag","name":"<app>:latest"},"fieldPath":"spec.template.spec.containers[?(@.name==\"<app>\")].image"}]
spec:
  template:
    spec:
      securityContext: {}          # NO runAsUser — the SCC injects an arbitrary UID
      containers:
        - name: <app>              # name MUST match the trigger's container selector
          image: image-registry.openshift-image-registry.svc:5000/<namespace>/<app>:latest
          imagePullPolicy: Always
```

The trigger rewrites `.image` to a resolved `@sha256` digest, so the live object won't show `:latest` — that's correct. A separate `restartedAt` patch in `deploy.sh` coexists fine (forces a rollout even when the digest is unchanged, e.g. to re-read a changed Secret — Secrets are **not** hot-reloaded).

### Two gotchas this pattern hits

1. **HTTP Basic Auth vs health probes.** If the app gates all paths behind Basic Auth (e.g. a Next.js `proxy.ts`/middleware), an `httpGet` liveness/readiness probe returns **401** and the pod never becomes Ready → rollout hangs. Use a **`tcpSocket`** probe instead (checks the port is accepting connections, immune to the gate), or exclude an ungated `/health` path from the auth matcher. Backends with an open `/health` are unaffected — use `httpGet /health` there.

2. **`oc create secret --from-env-file` keeps inline comments.** A line like `MODEL=gpt-5.6-sol   # note` stores the value as `gpt-5.6-sol   # note`, silently poisoning it. Prefer explicit **`--from-literal=KEY=value`** for each key (no parsing surprises), or sanitize the file first (strip ` #…` and blank/comment lines). Verify with `oc get secret <name> -o jsonpath='{.data.KEY}' | base64 -d`.

> Worked example of this pattern: a Next.js web behind Basic Auth (TCP probe, because the auth
> gate would 401 an HTTP probe) plus a FastAPI backend with an open `/health` (httpGet probe),
> secrets created with `--from-literal`, and one custom route on `*.2.rahtiapp.fi`.

## Common oc Commands

| Command | Description |
|---------|-------------|
| `oc project <namespace>` | Switch to namespace |
| `oc get pods -n <namespace>` | List pods |
| `oc get deployments -n <namespace>` | List deployments |
| `oc get services -n <namespace>` | List services |
| `oc get routes -n <namespace>` | List routes (URLs) |
| `oc logs deployment/<name> -n <namespace>` | View logs |
| `oc logs deployment/<name> -n <namespace> -f` | Follow logs |
| `oc logs deployment/<name> -n <namespace> --previous` | Previous pod logs |
| `oc describe deployment <name> -n <namespace>` | Deployment details |
| `oc get events -n <namespace> --sort-by='.lastTimestamp'` | Recent events |

For a whole-namespace health sweep (every deployment, pod, route and quota at
once, with a prioritised report) use the read-only [[rahti-audit]] skill
instead of running these one resource at a time.

## Verify Deployment

```bash
# Check pod status (wait 10-30s after push)
oc get pods -n <namespace> -l app=<app-name>

# Check logs
oc logs -f deployment/<deployment-name> -n <namespace>

# Get route URL
oc get route <route-name> -n <namespace> -o jsonpath='{.spec.host}'
```

## Troubleshooting

### Deployment not updating after push?

Check image trigger:
```bash
oc get deployment <deployment> -n <namespace> -o jsonpath="{.metadata.annotations.image\.openshift\.io/triggers}"
```

If `"paused":"true"` or empty, fix with:
```bash
oc annotate deployment/<deployment> image.openshift.io/triggers- -n <namespace>
oc set triggers deployment/<deployment> --from-image=<imagestream>:latest -c <container> -n <namespace>
```

### Manual image update (fallback)

```bash
LATEST=$(oc get imagestream <imagestream> -n <namespace> -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')
oc set image deployment/<deployment> <container>=${LATEST} -n <namespace>
```

### Pod crash / won't start?

```bash
# Check pod status
oc get pods -n <namespace> -l app=<app-name>

# Check events for errors
oc get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Check previous pod logs
oc logs deployment/<deployment> -n <namespace> --previous

# Check resource usage
oc adm top pods -n <namespace>
```

### 500 error on docker push?

ImageStream must exist before pushing:
```bash
# Check existing imagestreams
oc get is -n <namespace>

# Create if needed
oc create imagestream <name> -n <namespace>
```

### Permission denied writing files?

OpenShift runs containers with arbitrary UID but always group 0. For writable directories:

```dockerfile
# In Dockerfile
RUN mkdir -p /app/output && \
    chown -R 1001:0 /app/output && \
    chmod -R g+rwx /app/output
USER 1001
```

Key pattern: `chown 1001:0` + `chmod g+rwx` = any UID with group 0 can write.

### 504 Gateway Time-out on long requests?

The Route's HAProxy timeout defaults to **30s**. Long synchronous requests — LLM/vision calls, big
uploads, slow reports — get cut off at 30s and the browser sees a 504 (which the app may surface as a
generic "Request failed"). Raise it per-Route:

```bash
oc annotate route <route> haproxy.router.openshift.io/timeout=120s -n <namespace> --overwrite
```

Or declaratively in the Route manifest:

```yaml
metadata:
  annotations:
    haproxy.router.openshift.io/timeout: 120s
```

Confirm the request actually takes that long (`curl -w '%{time_total}'`) — a 504 at *exactly* ~30s is
the tell. For very long jobs, prefer an async job + poll over holding the request open.

## GitHub Integration (BuildConfig)

Automates deployment: `git push` → webhook → Rahti builds image → auto rollout.

### Known bug: "URL is valid but cannot be reached"

When creating a project directly from GitHub with SSH + Dockerfile strategy, Rahti 2 shows this error even when SSH is configured correctly. **Workaround:**
1. Create the project using a Builder Image first (e.g. a current Node.js UBI builder image)
2. After creation, edit the BuildConfig YAML to switch to Docker strategy:

```yaml
strategy:
  type: Docker
  dockerStrategy:
    dockerfilePath: Dockerfile
```

### Builder Image vs Custom Dockerfile

- **Builder Image** (simpler): Works for standard Node.js apps, no Dockerfile needed, faster setup
- **Custom Dockerfile** (flexible): Required for React/Vite, multi-stage builds, special dependencies — requires the two-step workaround above

### Setup via CLI (recommended for full control)

```bash
# 1. Create SSH key pair
ssh-keygen -t rsa -b 4096 -C "<project>@rahti" -f ./rahti_github_key

# 2. Add public key to GitHub repo → Settings → Deploy keys (read-only)

# 3. Create SSH secret in Rahti
oc create secret generic github-ssh-key \
  --type=kubernetes.io/ssh-auth \
  --from-file=ssh-privatekey=./rahti_github_key -n <namespace>
oc secrets link builder github-ssh-key -n <namespace>

# 4. Create webhook secret
oc create secret generic github-webhook-secret \
  --from-literal=WebHookSecretKey=$(openssl rand -hex 20) -n <namespace>

# 5. Create BuildConfig + ImageStream
oc apply -f buildconfig.yaml -n <namespace>

# 6. Get webhook URL and add to GitHub → Settings → Webhooks
oc describe bc/<buildconfig-name> -n <namespace> | grep -A2 "Webhook"
```

### Webhook URL format (generic)

```
https://api.2.rahti.csc.fi:6443/apis/build.openshift.io/v1/namespaces/<namespace>/buildconfigs/<buildconfig>/webhooks/<secret>/generic
```

Copy from Rahti UI: BuildConfig → Webhooks → "Copy URL with Secret"

GitHub webhook settings: Content type `application/json`, SSL enabled, trigger on push events only.

### BuildConfig YAML (Docker strategy)

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: <app-name>
spec:
  source:
    type: Git
    git:
      uri: git@github.com:<org>/<repo>.git
      ref: main
    sourceSecret:
      name: github-ssh-key
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: <app-name>:latest
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
  name: <app-name>
```

### Monitoring builds

```bash
oc get builds -n <namespace>              # List all builds
oc logs build/<build-name> -n <namespace> # Build logs
oc start-build <bc-name> -n <namespace>   # Trigger manually
```

## PostgreSQL / pgvector on Rahti

Self-hosted Postgres in the namespace uses community images (no CSC support) and
needs a PVC attached before any real data is written — without one the database
is lost on every pod restart. Reach the database over the Service DNS from pods in
the same namespace; never expose it through a Route.

Manifests, pgvector setup and gotchas: [references/postgresql.md](references/postgresql.md)

## OpenShift Binary Build (Alternative)

**Prefer GitHub webhook CI/CD** for automated deploys. Use binary build for quick testing:

```bash
# 1. Create BuildConfig (once)
oc new-build --name=<name> --binary --strategy=docker --to=<imagestream>:latest -n <namespace>

# 2. Build & push (from project root)
oc start-build <name> --from-dir=. --follow -n <namespace>
```

## CSC Aitta — LLM Inference API

> Need GPUs for training, fine-tuning or batch inference rather than an endpoint?
> That is Roihu, CSC's Slurm supercomputer — use the [[csc-roihu]] skill. Rahti has
> no GPUs, and Roihu cannot host a service.

Separate CSC service from Rahti. Aitta hosts curated LLMs (Llama 3.3 70B, gpt-oss-120b, Poro 2 70B, Gemma 3, Qwen3-VL, etc.) behind an **OpenAI-compatible API** — any OpenAI client works by overriding `baseURL`.

- Web UI / model catalog: <https://aitta.csc.fi/>
- API root: `https://aitta-api.csc.fi` (Aitta-native, HAL) — OpenAI-compatible base: `https://aitta-api.csc.fi/openai`
- Auth: `Authorization: Bearer <AITTA_API_TOKEN>` — token from <https://aitta-auth.csc.fi> (user-bound, ~90d).

Keep the token in your own env store (never in the repo): `AITTA_API_TOKEN`, `AITTA_API_BASE`, `AITTA_API_ROOT`, `AITTA_PROJECT_ID`, `AITTA_TOKEN_EXPIRES`.

Quick smoke test:
```bash
curl -H "Authorization: Bearer $AITTA_API_TOKEN" "$AITTA_API_ROOT/model" | jq
```

**Offline models** (most are) require `POST /model/{id}/preload` before the first chat completion — otherwise the request may time out.

Full reference (endpoints, model list snapshot, OpenAI SDK / AI SDK examples, gotchas): [references/aitta-llm-api.md](references/aitta-llm-api.md)

## Detailed Guides

- **Custom Routes/URLs:** See [references/routes.md](references/routes.md)
- **Environment Variables:** See [references/environment-vars.md](references/environment-vars.md)
- **Internal Services (Frontend-Backend):** See [references/internal-services.md](references/internal-services.md)
- **CSC Satama Registry (Harbor):** See [references/satama-registry.md](references/satama-registry.md)
- **PostgreSQL / pgvector:** See [references/postgresql.md](references/postgresql.md)
- **CSC Allas S3 Storage:** See [references/allas-s3.md](references/allas-s3.md)
- **CSC Aitta LLM API:** See [references/aitta-llm-api.md](references/aitta-llm-api.md)
- **Dockerfile Examples (OpenShift):** See [references/dockerfile-examples.md](references/dockerfile-examples.md)
