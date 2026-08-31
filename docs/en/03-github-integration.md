# 3. GitHub integration (BuildConfig and webhooks)

> `git push` → webhook → Rahti builds the image → the app updates. No local Docker, no
> manual pushes.

## Contents

- [When this is worth it](#when-this-is-worth-it)
- [Builder Image or your own Dockerfile](#builder-image-or-your-own-dockerfile)
- [A known error: "URL is valid but cannot be reached"](#a-known-error-url-is-valid-but-cannot-be-reached)
- [Step 1: SSH key for GitHub](#step-1-ssh-key-for-github)
- [Step 2: BuildConfig](#step-2-buildconfig)
- [Step 3: Webhook](#step-3-webhook)
- [Tracking builds](#tracking-builds)
- [Pitfalls](#pitfalls)

## When this is worth it

| Approach | Good | Bad |
| --- | --- | --- |
| **Local docker push** ([chapter 2](02-deploying.md)) | Fast, full control, works offline | Requires Docker, manual |
| **BuildConfig + webhook** (this chapter) | Automatic, no local Docker needed, the build is logged in the cluster | The build consumes the project's quota, slower, errors are debugged from the build logs |
| **GitHub Actions → docker push** | Familiar pipeline, tests in the same place | Requires a Rahti token in the CI secrets |

## Builder Image or your own Dockerfile

**Builder Image (S2I)** — Rahti packages your source code into a ready-made runtime. No
Dockerfile, quick to get started, sufficient for a typical Node.js or Python app.

**Your own Dockerfile (Docker strategy)** — full control, multi-stage builds,
necessary for e.g. a Vite/React frontend. Requires the workaround described below.

> Builder image versions go out of date. Pick an up-to-date UBI-based version from the
> list; a Node.js 18 builder that's years old no longer gets security updates.

## A known error: "URL is valid but cannot be reached"

When you try to create a project directly with *Import from Git* using an SSH URL and
the Dockerfile strategy, Rahti shows the error **"URL is valid but cannot be reached"**
even though the SSH key is correctly set up in both GitHub and Rahti.

**Workaround:**

1. First create the app with a **Builder Image** (the form proceeds despite the error)
2. Then edit the BuildConfig (*Builds → BuildConfigs → Actions → Edit BuildConfig* or
   the YAML directly) to the Docker strategy:

```yaml
strategy:
  type: Docker
  dockerStrategy:
    dockerfilePath: Dockerfile
```

Alternatively, create the BuildConfig entirely from the command line, so the form's
validation bug doesn't get in the way (see step 2).

## Step 1: SSH key for GitHub

A public repository just needs an HTTPS URL — no key required. For a private one:

```bash
# 1. Create a key pair (empty passphrase — Rahti has no way to prompt for one)
ssh-keygen -t ed25519 -C "rahti-deploy" -f ./rahti_github_key

# 2. Add the public key to GitHub:
#    repo → Settings → Deploy keys → Add deploy key → paste rahti_github_key.pub
#    Leave "Allow write access" off — the build only needs read access.

# 3. Import the private key into Rahti as a secret
oc create secret generic github-ssh-key \
  --type=kubernetes.io/ssh-auth \
  --from-file=ssh-privatekey=./rahti_github_key -n <project>

oc secrets link builder github-ssh-key -n <project>

# 4. Remove the private key from disk
rm rahti_github_key
```

In the browser, the same thing is done in the *Import from Git* form under **Show
advanced Git options → Source Secret → Create new Secret** (type *SSH key*). Paste the
entire key, including the `BEGIN` and `END` lines.

## Step 2: BuildConfig

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myapp
spec:
  source:
    type: Git
    git:
      uri: git@github.com:<org>/<repo>.git
      ref: main                      # see Pitfalls!
    sourceSecret:
      name: github-ssh-key
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: myapp:latest
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
  name: myapp
```

```bash
# Webhook secret first
oc create secret generic github-webhook-secret \
  --from-literal=WebHookSecretKey=$(openssl rand -hex 20) -n <project>

oc apply -f buildconfig.yaml -n <project>
```

## Step 3: Webhook

1. **Get the URL from Rahti:** *Builds → BuildConfigs → \<name\> → Webhooks →
   **Copy URL with Secret***

   From the command line:

   ```bash
   oc describe bc/myapp -n <project> | grep -A2 "Webhook"
   ```

   Format:

   ```
   https://api.2.rahti.csc.fi:6443/apis/build.openshift.io/v1/namespaces/<project>/buildconfigs/<bc>/webhooks/<secret>/github
   ```

   > The generic (non-GitHub) endpoint ends in `/generic`. Choose the type based on
   > where your code lives: GitHub, GitLab, Bitbucket, or Generic.

2. **Add the webhook in GitHub:** repo → *Settings → Webhooks → Add webhook*
   - **Payload URL:** the copied address
   - **Content type:** `application/json`
   - **Secret:** the same secret as in the URL
   - **SSL verification:** Enable
   - **Which events:** *Just the push event*
   - **Active:** ✓

3. **Test it:** make a change, push it, and check whether a build starts.

## Tracking builds

```bash
oc get builds -n <project>                  # all builds
oc logs build/<build-name> -n <project>     # logs for one build
oc logs -f bc/myapp -n <project>            # follow the latest build
oc start-build myapp -n <project>           # start manually
```

## Pitfalls

**Branch name.** Rahti's BuildConfig defaults to the `master` branch, GitHub's default
is `main`. If the `ref` field isn't set, pushes to `main` are silently ignored with no
error message. Set `spec.source.git.ref: main` — or in the browser, *Show advanced Git
options → Git reference*.

**A failed build is a silent failure.** A crashed build doesn't break the running app:
no new image is produced, and the pod just keeps running the old code. The pod shows
`Ready 1/1` and the route returns 200 — but the code change doesn't show up. Always
check `oc get builds` when "the deploy didn't go through."

**The build consumes quota.** The build pod reserves CPU and memory from the same
computing project quota as your apps. If the quota is full, the build stays `Pending`.

**Build pods pile up.** Every run leaves behind a `<app>-<n>-build` pod.
`Completed`/`Succeeded` is normal, `Failed` is a genuine finding. Clean up old ones as
needed:

```bash
oc delete pods -n <project> --field-selector=status.phase==Succeeded
```

**Pulling a private image.** If the BuildConfig pushes to Satama or pulls a base image
from a private registry, link the pull secret to the `builder` service account too:

```bash
oc secrets link builder <pull-secret> -n <project>
```

---

**Previous:** [2. Deploying](02-deploying.md) · **Next:** [4. Routes and networking →](04-routes-and-networking.md)

**Sources:** [CSC: Webhooks](https://docs.csc.fi/cloud/rahti/tutorials/basic/webhooks/) ·
[CSC: Deploy from Git](https://docs.csc.fi/cloud/rahti/tutorials/basic/deploy-from-git/)
