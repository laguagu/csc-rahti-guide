# Internal Service Communication

Connect frontend to backend within the Rahti cluster without exposing the backend publicly.

## Service DNS Format

```
<service-name>.<namespace>.svc.cluster.local
```

Or simply within same namespace:
```
<service-name>
```

## Frontend-Backend Pattern

**Architecture:**
```
[Internet] --> [Frontend Route] --> [Frontend Pod]
                                          |
                                          v (internal)
                                    [Backend Service]
                                          |
                                          v
                                    [Backend Pod]
```

**Frontend calls backend via internal URL:**
```
http://<backend-service>.<namespace>.svc.cluster.local:<port>
```

## Configuration

### Backend Deployment

1. Deploy backend (e.g., FastAPI on port 8000)
2. Create Service (no Route needed for internal-only)

```bash
# Expose deployment as internal service
oc expose deployment/<backend-deployment> --port=8000 -n <namespace>
```

### Frontend Configuration

Set backend URL as environment variable:

```bash
oc set env deployment/<frontend-deployment> -n <namespace> \
  BACKEND_URL=http://<backend-service>.<namespace>.svc.cluster.local:8000
```

Or in Next.js server-side code:
```typescript
const backendUrl = process.env.BACKEND_URL || 'http://backend-api.gaik.svc.cluster.local:8000'
const response = await fetch(`${backendUrl}/api/data`)
```

## Example

Frontend "report-creator" calling backend "python-api" in namespace "gaik":

```bash
# Backend service exposes port 8000
oc expose deployment/python-api --port=8000 -n gaik

# Frontend uses internal URL
oc set env deployment/report-creator -n gaik \
  API_URL=http://python-api.gaik.svc.cluster.local:8000
```

## Verify Internal Connectivity

```bash
# Exec into frontend pod
oc exec -it deployment/<frontend> -n <namespace> -- sh

# Test connection to backend
curl http://<backend-service>:8000/health
```

## Benefits

- **Security:** Backend not exposed to internet
- **Performance:** Internal network, no external routing
- **Simplicity:** No TLS needed for internal traffic
