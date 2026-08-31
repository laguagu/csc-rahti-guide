# 5. Environment variables and secrets

> The single most common mistake in Rahti projects is mixing up a build-time variable
> with a runtime one. It leads either to a broken build or to an API key leaking into
> the browser.

## Contents

- [Build time vs. runtime](#build-time-vs-runtime)
- [Setting runtime values](#setting-runtime-values)
- [Secrets (Secret)](#secrets-secret)
- [ConfigMap for non-secret configuration](#configmap-for-non-secret-configuration)
- [Pitfalls](#pitfalls)
- [Viewing variables in the console](#viewing-variables-in-the-console)

## Build time vs. runtime

| Variable type | When it's set | Where it ends up |
| --- | --- | --- |
| `NEXT_PUBLIC_*`, `VITE_*`, `REACT_APP_*` | `docker build` | **Baked into the JS bundle — visible to every visitor of the page** |
| Everything else | When the pod starts (`oc set env`, Secret) | Server side only |

Two consequences:

1. **A secret with the `NEXT_PUBLIC_` prefix is public.** It's in the browser's source
   code. If an API key has ended up there, it has to be rotated.
2. **A runtime variable that the build needs will break the build.** For example,
   Next.js's `next build` renders the pages and fails if the configuration requires a
   key that isn't there. The fix is to give the build an empty placeholder and supply
   the real value only at runtime:

```dockerfile
# The build accepts an empty value; the real one comes from the Secret when the pod starts
ARG DATABASE_URL=""
ENV DATABASE_URL=$DATABASE_URL
RUN npm run build
```

## Setting runtime values

```bash
# Individual values
oc set env deployment/app -n <project> \
  NODE_ENV=production BACKEND_URL=http://backend-api:8000

# All of a Secret's keys at once
oc set env deployment/app --from=secret/app-env -n <project>

# From a ConfigMap
oc set env deployment/app --from=configmap/app-config -n <project>

# List current values
oc set env deployment/app -n <project> --list

# Remove (note the trailing dash)
oc set env deployment/app -n <project> OLD_VARIABLE-
```

Every `oc set env` automatically triggers a rolling update.

## Secrets (Secret)

Passwords, API keys, and tokens belong in a Secret — not in the Deployment's `env`
block, and not in version control.

```bash
# Recommended: one key at a time, no parsing surprises
oc create secret generic app-env \
  --from-literal=DATABASE_URL='postgresql://user:password@postgres:5432/db' \
  --from-literal=OPENAI_API_KEY='sk-...' \
  -n <project>

# Or from a gitignored file (read Pitfalls first!)
oc create secret generic app-env --from-env-file=.env.local -n <project>

# Wire it into the Deployment
oc set env deployment/app --from=secret/app-env -n <project>
```

A single key for just one specific variable:

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: app-env
        key: DATABASE_URL
```

Checking the value (worth doing right after creating it):

```bash
oc get secret app-env -n <project> -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

Updating and rotating:

```bash
oc create secret generic app-env \
  --from-literal=OPENAI_API_KEY='sk-new' \
  --dry-run=client -o yaml | oc apply -f -

oc rollout restart deployment/app -n <project>
```

## ConfigMap for non-secret configuration

```bash
oc create configmap app-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=FEATURE_X=true -n <project>

oc set env deployment/app --from=configmap/app-config -n <project>
```

A ConfigMap's contents are visible to everyone with read access to the project — it's
not a secret, just structured configuration.

## Pitfalls

**`--from-env-file` preserves trailing comments on a line.** The line

```ini
MODEL=gpt-5.6-sol   # fastest
```

stores the value as `gpt-5.6-sol   # fastest`, and the app breaks in a confusing way.
Use `--from-literal` instead, or clean up the file first. Always check with
`base64 -d`.

**Secrets don't update on the fly.** A changed Secret isn't reflected in a running
pod. Only `oc rollout restart` brings in the new values.

**Quoting.** A password containing special characters should be wrapped in single
quotes so the shell doesn't interpret them: `--from-literal=PW='p@$$w0rd!'`.

**`.env` in version control.** Make sure `.gitignore` includes `.env` and
`.env.local`. If a secret has already been committed, removing it from history isn't
enough — the key has to be rotated.

**A Kubernetes Secret isn't encrypted, only base64-encoded.** Anyone with read access
to the project can see the value. Restrict project permissions to only those who need
them (*User Management → RoleBindings*).

## Viewing variables in the console

*Workloads → Deployments → \<app\> → Environment*:

![The Deployment's Environment tab](../images/rahti-env-vars.jpg)

In the screenshot, `BACKEND_URL` is a plain value and the rest are pulled from a
Secret — the Secret's name and key are visible, the value isn't. This is exactly how
secrets should be displayed.

---

**Previous:** [4. Routes and networking](04-routes-and-networking.md) · **Next:** [6. Frontend and backend →](06-frontend-and-backend.md)
