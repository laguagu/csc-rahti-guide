# 2. Deploying an application with Docker

> Building the image, pushing it to a registry, and starting the app on Rahti — both
> from the browser and from the command line.

## Contents

- [Overview](#overview)
- [1. Build the image](#1-build-the-image)
- [2. Choose a registry](#2-choose-a-registry)
  - [Option A: Rahti's internal registry](#option-a-rahtis-internal-registry)
  - [Option B: Satama (CSC's Harbor)](#option-b-satama-cscs-harbor)
  - [Option C: Docker Hub](#option-c-docker-hub)
- [3. Deploy from the browser](#3-deploy-from-the-browser)
- [4. Deploy from the command line (manifests)](#4-deploy-from-the-command-line-manifests)
- [Automatic restart on a new image](#automatic-restart-on-a-new-image)
- [A repeatable deploy script](#a-repeatable-deploy-script)
- [Binary build as an alternative](#binary-build-as-an-alternative)

## Overview

```
  Dockerfile ──► docker build ──► docker push ──► ImageStream ──► Deployment ──► Pod
                                                                       │
                                                          Service ─────┘
                                                             │
                                                          Route ──► https://…2.rahtiapp.fi
```

Four objects are almost always enough:

| Object | Role |
| --- | --- |
| **ImageStream** | Rahti's internal reference to the image and its tags |
| **Deployment** | Keeps the desired number of pods running, handles rolling updates |
| **Service** | A stable internal address for the pods (DNS name + load balancing) |
| **Route** | The public HTTPS address, pointing to the Service |

## 1. Build the image

```bash
# Basic command, run in the project root
docker build -t myapp .

# Without cache, if you suspect a stale layer
docker build --no-cache -t myapp .
```

Test locally before shipping to the cloud:

```bash
docker run -p 3000:3000 myapp
docker run --env-file .env -p 3000:3000 myapp
```

> **A Rahti-compatible Dockerfile:** don't run as root, don't hardcode a UID, and make
> writable directories writable by group 0. Ready-made templates (Next.js,
> Python/FastAPI, static site) are in the skill's
> [dockerfile-examples.md](../../.claude/skills/csc-rahti/references/dockerfile-examples.md).

> **Processor architecture:** Rahti runs `linux/amd64`. An image built on an Apple
> M-series machine defaults to `arm64` and won't start on Rahti. Use
> `docker build --platform linux/amd64 …`.

## 2. Choose a registry

| Registry | When |
| --- | --- |
| **Rahti's internal registry** `image-registry.apps.2.rahti.csc.fi` | Fast dev cycle within a single project. The default choice. |
| **Satama** `satama.csc.fi` | The image is shared across projects or clusters, or you need vulnerability scanning, signing, and long-lived robot accounts. |
| **Docker Hub** | A public image, or no CSC project involved at all. |

### Option A: Rahti's internal registry

```bash
# 1. Log in to the registry (requires a valid oc session)
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi

# 2. Tag
docker tag myapp \
  image-registry.apps.2.rahti.csc.fi/<project>/myapp:latest

# 3. Push
docker push image-registry.apps.2.rahti.csc.fi/<project>/myapp:latest
```

**The ImageStream must exist before you push**, otherwise the push fails with an HTTP
500 error:

```bash
oc get is -n <project>                        # list existing ones
oc create imagestream myapp -n <project>
```

![ImageStream list in the console](../images/rahti-imagestreams.jpg)

> **Shortcut for the first time:** push the image to Docker Hub first and deploy it on
> Rahti from there. Rahti creates the ImageStream automatically, after which you can
> switch to the internal registry.

For a CI pipeline, it's worth creating a dedicated account with push-only rights:

```bash
oc create serviceaccount pusher -n <project>
oc policy add-role-to-user system:image-pusher -z pusher -n <project>
docker login -u unused -p $(oc create token pusher --duration=8760h) \
  image-registry.apps.2.rahti.csc.fi
```

### Option B: Satama (CSC's Harbor)

Satama is CSC's own container registry, a service separate from Rahti. You log in with
a **CLI secret** (Satama UI → your username → *User Profile* → *CLI Secret*), not your
MyCSC password.

```bash
docker login satama.csc.fi -u <csc-username>      # paste the CLI secret
docker tag  myapp:1.0 satama.csc.fi/<satama-project>/myapp:1.0
docker push satama.csc.fi/<satama-project>/myapp:1.0
```

Pulling from a private Satama project requires a pull secret:

```bash
oc create secret docker-registry satama-pull \
  --docker-server=satama.csc.fi \
  --docker-username='robot$<project>+<name>' \
  --docker-password="$SATAMA_ROBOT_SECRET" -n <project>
oc secrets link default satama-pull --for=pull -n <project>
```

Public Satama projects can be pulled without a secret. For robot accounts, scanning,
tag immutability, and quotas, see
[satama-registry.md](../../.claude/skills/csc-rahti/references/satama-registry.md).

### Option C: Docker Hub

```bash
docker tag myapp <dockerhub-username>/myapp:latest
docker push <dockerhub-username>/myapp:latest
```

A private Docker Hub image needs an *image pull secret* in Rahti (registry `docker.io`,
username, and password/token). A public image needs nothing.

## 3. Deploy from the browser

The console's left menu is now a unified **Core platform** navigation; there's no
longer a separate Developer/Administrator view switch. A new app is added either from
the **+** quick menu at the top or from the project's **+Add** page.

![+Add page options](../images/rahti-add-page.jpg)

The quickest route: **+** (top) → *Container images*.

![Quick create menu](../images/rahti-quick-create.jpg)

**Deploy Image form:**

![Deploy Image form](../images/rahti-deploy-image.jpg)

- **Image name from external registry** — enter e.g. `user/app:latest` (Docker Hub) or
  `satama.csc.fi/project/app:1.0`
- **Image stream tag from internal registry** — pick a previously pushed image
- **Select project** — the target project
- **Application** — the logical group the component belongs to (shown in the Topology
  view)
- **Name** — the component's name, from which the Deployment, Service, and Route are
  derived

Scroll down to the **Advanced options** section:

![Deploy Image, Advanced options](../images/rahti-deploy-image-advanced.jpg)

- **Target port** — the port your app listens on (e.g. 3000 or 8080)
- **Create a route** — creates a public HTTPS address. Leave unchecked if the service
  should only be internal (e.g. a backend or a database).

Click **Create**. Rahti creates the Deployment, Service, and, if requested, the Route,
generates the address `<name>-<project>.2.rahtiapp.fi`, and handles TLS (edge
termination, HTTP redirected to HTTPS).

After deploying, the app shows up in the **Topology** view, grouped by application:

![Topology view](../images/rahti-topology.png)

## 4. Deploy from the command line (manifests)

Once you're deploying an app repeatedly, the browser form starts to get in the way: the
configuration isn't version-controlled. Recommended layout:

```
<repo>/openshift/
  manifests/            # declarative objects — run `oc apply -f` ONCE
    00-imagestreams.yaml
    10-api-deployment.yaml   11-api-service.yaml
    20-web-deployment.yaml   21-web-service.yaml   22-web-route.yaml
  deploy.sh             # repeatable loop: build → push → rollout
```

- **Once:** `oc apply -f openshift/manifests/` and secrets via
  `oc create secret generic … --from-literal=…`
- **On every code change:** `./openshift/deploy.sh`

A minimal Deployment + Service + Route:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      securityContext: {}          # NO runAsUser — the SCC assigns the UID
      containers:
        - name: myapp              # the name must match the image trigger
          image: image-registry.openshift-image-registry.svc:5000/<project>/myapp:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits:   { cpu: 500m, memory: 512Mi }
          readinessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
  ports:
    - name: http
      port: 3000
      targetPort: 3000
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp
spec:
  host: myapp.2.rahtiapp.fi
  to:
    kind: Service
    name: myapp
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

Note that inside the cluster, the image is referenced by
`image-registry.openshift-image-registry.svc:5000/...`, not by the public
`image-registry.apps.2.rahti.csc.fi` name.

## Automatic restart on a new image

A plain `docker push` doesn't restart the pod. Add an **image trigger** to the
Deployment, and the new `:latest` is picked up automatically:

```yaml
metadata:
  annotations:
    image.openshift.io/triggers: |
      [{"from":{"kind":"ImageStreamTag","name":"myapp:latest"},
        "fieldPath":"spec.template.spec.containers[?(@.name==\"myapp\")].image"}]
```

The trigger rewrites the `.image` field to an `@sha256` digest, so the live object
won't show `:latest`. That's correct behavior, not a bug.

The same from the command line:

```bash
oc set triggers deployment/myapp \
  --from-image=myapp:latest -c myapp -n <project>
```

If the deployment doesn't update after a push, see
[9. Troubleshooting](09-troubleshooting.md#the-deployment-doesnt-update-after-a-push).

## A repeatable deploy script

A `deploy.sh` that works in practice does four things:

```bash
#!/usr/bin/env bash
set -euo pipefail

NS=my-project
APP=myapp
REG=image-registry.apps.2.rahti.csc.fi
TAG=$(date +%Y%m%d-%H%M%S)

docker build --platform linux/amd64 -t "$APP" .
docker tag "$APP" "$REG/$NS/$APP:latest"
docker tag "$APP" "$REG/$NS/$APP:$TAG"
docker push "$REG/$NS/$APP:latest"
docker push "$REG/$NS/$APP:$TAG"

# Force a rollout even when the digest hasn't changed (e.g. a changed Secret)
oc patch deployment/"$APP" -n "$NS" -p \
  "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/restartedAt\":\"$(date -Iseconds)\"}}}}}"
oc rollout status deployment/"$APP" -n "$NS" --timeout=180s
```

> **Secrets don't update themselves.** A changed Secret isn't reflected in a running
> pod until it restarts — hence the `restartedAt` patch.

## Binary build as an alternative

If you don't want to run Docker locally, Rahti can build the image for you from source
code:

```bash
# Once
oc new-build --name=myapp --binary --strategy=docker \
  --to=myapp:latest -n <project>

# On every build, in the project root
oc start-build myapp --from-dir=. --follow -n <project>
```

This is handy for testing. For ongoing use, we recommend GitHub integration:
[3. GitHub integration →](03-github-integration.md)

---

**Previous:** [1. Getting started](01-getting-started.md) · **Next:** [3. GitHub integration →](03-github-integration.md)
