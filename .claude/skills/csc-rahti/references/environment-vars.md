# Environment Variables on Rahti

## The split that causes most bugs

| Type | Set when | Where it ends up |
|------|----------|------------------|
| `NEXT_PUBLIC_*` / `VITE_*` | `docker build` | Baked into the JS bundle — **public, visible in the browser** |
| Everything else | Pod start (`oc set env`, Secret) | Server-side only |

A secret placed behind a `NEXT_PUBLIC_`/`VITE_` prefix is published to every
visitor. A runtime-only variable that the build needs will fail the build
instead — for that case use the ARG-placeholder pattern in
[allas-s3.md](allas-s3.md#dockerfile-arg-placeholders-nextjs-specific).

## Injecting runtime values

```bash
# From a gitignored file (fastest for many keys)
oc create secret generic <app>-env --from-env-file=.env.local -n <namespace>
oc set env deployment/<app> --from=secret/<app>-env -n <namespace>

# Individual values
oc set env deployment/<app> -n <namespace> DATABASE_URL=postgresql://... API_SECRET=...

# From a ConfigMap (non-secret config)
oc set env deployment/<app> -n <namespace> --from=configmap/<name>

# Inspect / remove (trailing dash removes)
oc set env deployment/<app> -n <namespace> --list
oc set env deployment/<app> -n <namespace> SECRET_KEY-
```

## Gotchas

- **`--from-env-file` keeps inline comments.** `MODEL=gpt-5.6-sol  # note` stores
  the trailing comment as part of the value. Prefer `--from-literal=KEY=value`,
  or strip comments first. Verify:
  `oc get secret <name> -o jsonpath='{.data.KEY}' | base64 -d`
- **Secrets are not hot-reloaded.** After updating a Secret the running pods keep
  the old values until `oc rollout restart deployment/<app> -n <namespace>`.
- **Rotation:** `oc create secret ... --dry-run=client -o yaml | oc apply -f -`,
  then restart the rollout.
