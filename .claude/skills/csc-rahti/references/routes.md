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

## Example

For app "myapp" on port 3000 in namespace "gaik":

```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: myapp-custom
  namespace: gaik
  labels:
    app: myapp
    app.kubernetes.io/component: myapp
    app.kubernetes.io/instance: myapp
    app.kubernetes.io/name: myapp
    app.kubernetes.io/part-of: myapp
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: myapp-custom.2.rahtiapp.fi
  to:
    kind: Service
    name: myapp
    weight: 100
  port:
    targetPort: 3000-tcp
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

## TLS Configuration

- `termination: edge` - TLS terminates at the router (recommended)
- `insecureEdgeTerminationPolicy: Redirect` - HTTP redirects to HTTPS
- All routes automatically get HTTPS on `*.2.rahtiapp.fi`

## Route Timeout

Default route timeout is 30 seconds. For long-running requests (AI processing, file uploads, etc.):

```bash
oc annotate route <route-name> -n <namespace> --overwrite \
  haproxy.router.openshift.io/timeout=300s
```

**Symptoms of timeout issues:**
- 504 Gateway Timeout
- Backend logs show 200 OK but frontend gets error
