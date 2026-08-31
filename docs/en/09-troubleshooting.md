# 9. Troubleshooting

> From symptom to cause. Always start with the same three commands — don't guess.

## Contents

- [The first three commands](#the-first-three-commands)
- [Pod states and what they mean](#pod-states-and-what-they-mean)
- [The Deployment doesn't update after a push](#the-deployment-doesnt-update-after-a-push)
- [CrashLoopBackOff](#crashloopbackoff)
- [ImagePullBackOff / ErrImagePull](#imagepullbackoff--errimagepull)
- [Pod stuck in Pending](#pod-stuck-in-pending)
- [OOMKilled (exit 137)](#oomkilled-exit-137)
- [Permission denied when writing a file](#permission-denied-when-writing-a-file)
- [500 error on docker push](#500-error-on-docker-push)
- [504 Gateway Time-out](#504-gateway-time-out)
- [The app doesn't respond through the Route](#the-app-doesnt-respond-through-the-route)
- [Unauthorized / login expired](#unauthorized--login-expired)
- [False alarms](#false-alarms)
- [Whole-namespace status overview](#whole-namespace-status-overview)

## The first three commands

```bash
oc get pods -n <project>                                    # 1. what state is it in
oc logs deployment/<app> -n <project> --tail=50              # 2. what does the app say
oc get events -n <project> --sort-by=.lastTimestamp | tail   # 3. what does the cluster say
```

The pod's state tells you which direction to go: `Running` but misbehaving → check
logs. `Pending`/`CrashLoop`/`ImagePull` → check events and `oc describe`.

![Pod list in the console](../images/rahti-pods.jpg)

The same information is in the console: *Workloads → Pods → \<pod\> → Logs / Events*.

## Pod states and what they mean

| State | Meaning | Next command |
| --- | --- | --- |
| `Running` + `1/1` | Running and ready | — |
| `Running` + `0/1` | Running, but the readiness check isn't passing | `oc describe pod <pod>` |
| `Pending` | Not scheduled — quota, PVC, or resource request | `oc describe pod <pod>` |
| `CrashLoopBackOff` | Starting and crashing repeatedly | `oc logs <pod> --previous` |
| `ImagePullBackOff` | The image can't be pulled | `oc describe pod <pod>` |
| `Error` / `Completed` | The process finished (job, build) | Normal for jobs |
| `Terminating` for a long time | Shutdown is stuck | `oc delete pod <pod> --force` |

## The Deployment doesn't update after a push

The most common source of confusion: the image has been pushed, but the old code is
still running.

```bash
# 1. Did the new image arrive?
oc get is <imagestream> -n <project>
oc describe is <imagestream> -n <project> | head -30

# 2. Does an image trigger exist and is it enabled?
oc get deployment <app> -n <project> \
  -o jsonpath="{.metadata.annotations.image\.openshift\.io/triggers}"
```

If the output is empty or contains `"paused":"true"`:

```bash
oc annotate deployment/<app> image.openshift.io/triggers- -n <project>
oc set triggers deployment/<app> \
  --from-image=<imagestream>:latest -c <container> -n <project>
```

A quick fix without a trigger:

```bash
oc rollout restart deployment/<app> -n <project>
oc rollout status  deployment/<app> -n <project>
```

Or set the image manually:

```bash
LATEST=$(oc get is <imagestream> -n <project> \
  -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')
oc set image deployment/<app> <container>=${LATEST} -n <project>
```

**Also check the builds** if you're using a BuildConfig — a failed build means a new
image was never produced:

```bash
oc get builds -n <project>
```

## CrashLoopBackOff

```bash
oc logs deployment/<app> -n <project> --previous   # log from the previous attempt
oc describe pod <pod> -n <project>                  # exit code and events
```

The usual causes:

| Cause | Telltale sign |
| --- | --- |
| Missing environment variable | Log shows `undefined`, `KeyError`, `connection string is empty` |
| App listens on `127.0.0.1` | Starts normally, but the health check doesn't respond |
| Wrong port | `containerPort` ≠ the app's port |
| Needs root privileges | `permission denied`, `EACCES`, `mkdir failed` |
| Wrong architecture | `exec format error` → the image is arm64, amd64 is needed |
| OOM | Exit code 137 |

## ImagePullBackOff / ErrImagePull

```bash
oc describe pod <pod> -n <project> | grep -A5 Events
```

- **Private registry without a pull secret** → create a secret and link it:
  ```bash
  oc secrets link default <pull-secret> --for=pull -n <project>
  ```
- **Wrong tag** → check that the tag exists: `oc get is <name> -o yaml`
- **Wrong address** → from inside the cluster:
  `image-registry.openshift-image-registry.svc:5000/<project>/<image>`, from outside:
  `image-registry.apps.2.rahti.csc.fi/<project>/<image>`

## Pod stuck in Pending

```bash
oc describe pod <pod> -n <project> | tail -20
oc describe AppliedClusterResourceQuotas
```

Three typical causes:

1. **Quota exhausted.** The quota is shared across the whole computing project. Shut
   down unneeded apps or scale to zero: `oc scale deployment/<x> --replicas=0`
2. **The PVC can't get storage.** `oc get pvc -n <project>` — if the state is
   `Pending`, the size may exceed the quota (max 100 GiB / PVC).
3. **The resource request exceeds a limit.** A LimitRange defines the maximums; a
   `requests` value that's too large gets rejected.

## OOMKilled (exit 137)

The container exceeded its memory limit.

```bash
oc adm top pods -n <project>
oc set resources deployment/<app> -n <project> --limits=memory=2Gi --requests=memory=512Mi
```

Remember the ratio limit: `limits` may be at most 5× `requests` (check your project's
LimitRange). So just raising the ceiling without also raising the reservation can get
rejected.

## Permission denied when writing a file

Rahti gives the container a random UID, but the group is always **0**. Make writable
directories writable by group 0:

```dockerfile
RUN mkdir -p /app/output && \
    chown -R 1001:0 /app/output && \
    chmod -R g+rwX /app/output
USER 1001
```

The same applies to `.next`, `tmp`, and cache directories. If the app writes to the
root directory, redirect it to write to `/tmp` instead — that's always writable.

**Do not** try to fix this with a `runAsUser` setting in the manifest; the SCC rejects
it.

## 500 error on docker push

```
unknown: unexpected status from HEAD request to
https://image-registry.apps.2.rahti.csc.fi/v2/<project>/<image>/manifests/sha256:… : 500
```

The ImageStream is missing. Create it first:

```bash
oc create imagestream <image> -n <project>
```

Also check that you're logged in to the registry (with the `oc whoami -t` token) and
that the image is under 5 GiB.

## 504 Gateway Time-out

HAProxy's default timeout is 30 seconds. See
[04 Routes and networking](04-routes-and-networking.md#504-gateway-time-out-on-long-requests).

```bash
oc annotate route <route> haproxy.router.openshift.io/timeout=120s -n <project> --overwrite
```

## The app doesn't respond through the Route

Work from the outside in:

```bash
# 1. Does the Route exist and is it admitted?
oc get route <route> -n <project>

# 2. Does it point to the right service and port?
oc describe route <route> -n <project>

# 3. Does the Service respond?
oc get svc <service> -n <project> -o wide
oc get endpoints <service> -n <project>      # empty = the label selector doesn't match any pods

# 4. Does the pod respond directly?
oc port-forward deployment/<app> 8080:<port> -n <project>
curl -I http://localhost:8080
```

An empty `endpoints` list is very common: the Service's `selector` doesn't match the
pod's labels.

## Unauthorized / login expired

```
error: You must be logged in to the server (Unauthorized)
```

A personal token expires after about a day. First check who you are:

```bash
oc whoami
oc config current-context
```

If the context has switched back to your personal account even though you should be
using a service account, log in with it again. The permanent fix is a service account
with a long-lived token: [1. Getting started](01-getting-started.md#service-account-for-long-term-use).

## False alarms

These look like problems but aren't:

- **A restart count by itself is not an alarm.** A pod that's been running for months
  accumulates restarts from normal recycling. Weigh it against the pod's age: 40
  restarts over 90 days is not the same as 40 restarts in an hour.
- **HTTP 401/403 on a Route means the app is responding.** It's up and requires
  authentication. Only 5xx, connection errors, and timeouts are alarms.
- **The first request to a rarely used app can time out** (cold start). Try again
  before marking it as down.
- **Pods in `Completed` state are not failures** — they're finished job, cronjob, and
  build runs.
- **An empty `resourcequota`** is normal: the quota lives at the computing-project
  level. Use `oc describe AppliedClusterResourceQuotas`.
- **A live Deployment shows `@sha256:…` instead of `:latest`** — the image trigger has
  resolved the tag to a digest. That's how it's supposed to work.

## Whole-namespace status overview

When you want to know in one shot whether everything is up:

```bash
oc get all -n <project>
oc get events -n <project> --field-selector type=Warning --sort-by=.lastTimestamp
```

This repository also ships an **`rahti-audit` skill**, which gathers the same status
overview in a single run (deployments, pods, routes with their HTTP responses, warning
events, and quotas) and reports only the anomalies. See
[10. Agentic development](10-agentic-development.md).

---

**Previous:** [8. Allas S3](08-allas-s3.md) · **Next:** [10. Agentic development →](10-agentic-development.md)
