# Environment Variables

## Build-time vs Runtime

| Type | When Set | Example | Secret? |
|------|----------|---------|---------|
| `NEXT_PUBLIC_*` | Build-time (Dockerfile) | Baked into JS bundle | No |
| Without prefix | Runtime (oc set env) | Read when pod starts | Can be |

## Build-time Variables (Next.js)

For Next.js apps, `NEXT_PUBLIC_*` variables are embedded during `docker build`.

Create `.env.production` in your project:
```bash
NEXT_PUBLIC_API_URL=https://api.example.com
NEXT_PUBLIC_APP_NAME=MyApp
```

These are **public** and visible in the browser.

## Build-time Variables (Vite)

Vite uses `VITE_*` prefix (similar to Next.js `NEXT_PUBLIC_*`):

```bash
VITE_API_URL=https://api.example.com
VITE_APP_NAME=MyApp
```

These are embedded during `docker build` and visible in browser.

## Runtime Variables

Set secret or dynamic values directly in OpenShift:

```bash
# Set single variable
oc set env deployment/<deployment> -n <namespace> \
  SECRET_KEY=your-secret-value

# Set multiple variables
oc set env deployment/<deployment> -n <namespace> \
  DATABASE_URL=postgresql://... \
  API_SECRET=your-api-secret

# From file
oc set env deployment/<deployment> -n <namespace> --from=configmap/<configmap-name>
```

## List Environment Variables

```bash
oc set env deployment/<deployment> -n <namespace> --list
```

## Remove Variable

```bash
oc set env deployment/<deployment> -n <namespace> SECRET_KEY-
```

Note the `-` at the end removes the variable.

## Best Practices

1. **Never commit secrets** to `.env.production`
2. Use `NEXT_PUBLIC_*` only for truly public values
3. Set API keys and secrets via `oc set env`
4. Use ConfigMaps for non-secret configuration
5. Use Secrets for sensitive data

## Example: Next.js with Supabase

**Build-time (.env.production):**
```bash
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

**Runtime (oc set env):**
```bash
oc set env deployment/myapp -n gaik \
  SUPABASE_SERVICE_KEY=your-service-role-key
```
