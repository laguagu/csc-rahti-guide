# Custom Routes (URLs)

Create custom URLs for your application by defining Route objects.

## Route YAML Template

```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: <route-name>
  namespace: <namespace>
  labels:
    app: <app-name>
    app.kubernetes.io/component: <app-name>
    app.kubernetes.io/instance: <app-name>
    app.kubernetes.io/name: <app-name>
    app.kubernetes.io/part-of: <project-name>
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: <custom-name>.2.rahtiapp.fi
  to:
    kind: Service
    name: <service-name>
    weight: 100
  port:
    targetPort: <port>-tcp
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

**Placeholders:**
- `<route-name>`: Name for the Route object
- `<namespace>`: Your project namespace
- `<app-name>`: Application name
- `<project-name>`: Project name (for grouping in UI)
- `<custom-name>`: Desired URL prefix (e.g., `my-app`)
- `<service-name>`: Service to route traffic to
- `<port>`: Port number (e.g., `3000`, `8080`)

## Create Route

```bash
# Verify correct project
oc project

# Create route from YAML file
oc create -f route.yaml
```

## Delete Route

```bash
oc delete route <route-name> -n <namespace>
```

## Multiple Routes

You can have multiple routes pointing to the same service with different hostnames. This is useful for:
- Transition periods when changing URLs
- Supporting multiple domains
- A/B testing

The `labels` block only affects grouping in the web console — it can be omitted.
`openshift.io/host.generated: "false"` is what tells OpenShift to honour your
`spec.host` instead of generating one.

## TLS Configuration

- `termination: edge` - TLS terminates at the router (recommended)
- `insecureEdgeTerminationPolicy: Redirect` - HTTP redirects to HTTPS
- All routes automatically get HTTPS on `*.2.rahtiapp.fi`

## Gotchas

- **`targetPort: <port>-tcp` must match the Service's port name.** That naming
  comes from `oc expose deployment/...`; a hand-written Service may name its port
  differently or not at all. Mismatch gives a 503 from the router with healthy
  pods. Check with `oc get svc <name> -o jsonpath='{.spec.ports}'` — a numeric
  `targetPort` also works.
- **Route timeout defaults to 30s** — see the 504 section in SKILL.md for the
  `haproxy.router.openshift.io/timeout` annotation and how to confirm the
  diagnosis.
