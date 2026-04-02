---
name: csc-rahti
description: CSC Rahti 2 (OpenShift) deployment. Use when deploying Docker images to Rahti, configuring routes, setting environment variables, or connecting frontend to backend services.
---

# CSC Rahti 2 Deployment

CSC Rahti 2 is a container cloud based on Red Hat OpenShift. This skill helps with common deployment workflows.

## Prerequisites

**User must authenticate manually:**
1. Go to [Rahti 2 Console](https://rahti.csc.fi)
2. Click username (top right) > "Copy login command"
3. Click "Display Token" and copy the `oc login` command
4. Run the command in terminal

**Agent cannot:**
- Access credentials or run `oc login`
- Access Rahti web console

**Security (multi-tenant):**
- Containers cannot run as root
- Privileged mode disabled
- Arbitrary UID assignment (container may run as any UID)

**Key URLs:**
- Console: `https://rahti.csc.fi`
- Image Registry: `image-registry.apps.2.rahti.csc.fi`
- Route domain: `*.2.rahtiapp.fi`
- Egress IP: `86.50.229.150` (for firewall rules — verify current value at rahti.csc.fi docs)

## Resource Limits (CSC Defaults)

| Resource | Default | Max |
|----------|---------|-----|
| CPU request | 100m | - |
| CPU limit | 500m | 4 cores |
| Memory request | 500Mi | - |
| Memory limit | 1Gi | 16Gi |
| Max limit/request ratio | 5x | - |

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

**Placeholders:**
- `<image-name>`: Your Docker image name (e.g., `myapp`)
- `<namespace>`: Rahti project/namespace (e.g., `gaik`)

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

## GitHub Webhook CI/CD (Recommended)

Automates deployment: `git push` → GitHub webhook → Rahti builds image → auto rollout.

### Setup

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
oc describe bc/<buildconfig-name> -n <namespace> | grep -A2 "GitHub"
```

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

## PostgreSQL on Rahti

```bash
# Create secret
oc create secret generic postgresql-secrets \
  --from-literal=POSTGRESQL_USER=<user> \
  --from-literal=POSTGRESQL_PASSWORD=<password> -n <namespace>

# Apply manifests (PVC + Deployment + Service + ConfigMap)
oc apply -f postgresql/ -n <namespace>

# Port-forward for local access (run db:tunnel scripts)
oc port-forward service/postgresql 5432:5432 -n <namespace>
```

Image: `image-registry.openshift-image-registry.svc:5000/openshift/postgresql:16-el9`

## OpenShift Binary Build (Alternative)

**Prefer GitHub webhook CI/CD** for automated deploys. Use binary build for quick testing:

```bash
# 1. Create BuildConfig (once)
oc new-build --name=<name> --binary --strategy=docker --to=<imagestream>:latest -n <namespace>

# 2. Build & push (from project root)
oc start-build <name> --from-dir=. --follow -n <namespace>
```

## Detailed Guides

- **Custom Routes/URLs:** See [references/routes.md](references/routes.md)
- **Environment Variables:** See [references/environment-vars.md](references/environment-vars.md)
- **Internal Services (Frontend-Backend):** See [references/internal-services.md](references/internal-services.md)
- **CSC Allas S3 Storage:** See [references/allas-s3.md](references/allas-s3.md)
- **Dockerfile Examples (OpenShift):** See [references/dockerfile-examples.md](references/dockerfile-examples.md)
