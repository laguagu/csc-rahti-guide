# 3. GitHub integration (BuildConfig and webhooks)

> `git push` → webhook → Rahti builds the image → the app updates. No local Docker, no
> manual pushes.

## Contents

- [When this is worth it](#when-this-is-worth-it)
- [Builder Image or your own Dockerfile](#builder-image-or-your-own-dockerfile)
- [Warning: "URL is valid but cannot be reached"](#warning-url-is-valid-but-cannot-be-reached)
  - [Fastest route: skip the form entirely](#fastest-route-skip-the-form-entirely)
- [Step 1: Credentials for a private repository](#step-1-credentials-for-a-private-repository)
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
necessary for e.g. a Vite/React frontend. Works from both the browser and the command
line.

> Builder image versions go out of date. Pick an up-to-date UBI-based version from the
> list; a Node.js 18 builder that's years old no longer gets security updates.

## Warning: "URL is valid but cannot be reached"

When you enter a private repository's address into the *Import from Git* form, a red
**"URL is valid but cannot be reached"** appears below the field. This is **not a bug**.
Rahti tries to read the repository anonymously before you've supplied credentials, which
naturally fails for a private repo. CSC documents this as expected behaviour.

Continue as normal and supply credentials under **Show advanced Git options → Source
Secret → Create new Secret**. There are two options:

| Method | Authentication type | When to use |
| --- | --- | --- |
| **Personal access token** | Basic Authentication | The simplest option. In GitHub: *Settings → Developer settings → Personal access tokens*, with `repo` scope. |
| **SSH key** | SSH Key | When you want a repo-scoped deploy key rather than an account-wide token. Instructions below. |

> Older guides — including earlier versions of this repo — described this as a bug that
> forced you to first create the app with a Builder Image and swap the strategy
> afterwards. **The workaround is not needed.** The Docker strategy from Git works,
> which was verified by running `oc new-build` against a public repository with the
> Docker strategy and the `--context-dir` flag — it built an image in 39 seconds.

### Fastest route: skip the form entirely

From the command line you don't need to fight the form's validation at all:

```bash
# Public repository, Dockerfile in a subdirectory
oc new-build https://github.com/<org>/<repo>   --strategy=docker   --context-dir=<path/to/dockerfile>   --name=<app> -n <project>

# Follow the build
oc logs -f bc/<app> -n <project>
```

For a private repository, create the secret and link it to the `builder` account first
(see step 1), after which the same `oc new-build` works with the SSH URL.

## Step 1: Credentials for a private repository

A public repository needs nothing extra: the HTTPS URL is enough. For a private one,
choose a token or an SSH key.

### Option A: personal access token (simplest)

1. In GitHub: *Settings → Developer settings → Personal access tokens*, with `repo`
   scope
2. Bring the token into Rahti:

```bash
oc create secret generic github-token   --from-literal=username=<github-username>   --from-literal=password=<token>   --type=kubernetes.io/basic-auth -n <project>

oc secrets link builder github-token -n <project>
```

In the browser this is the same as *Source Secret → Create new Secret → Basic
Authentication*.

> The token is account-wide, so give it the narrowest possible scopes and an expiry
> date. If you want access limited to a single repository, use an SSH key instead.

### Option B: SSH key (repo-scoped deploy key)

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

> In our own test, `oc new-build` without a `ref` used the repository's default branch,
> which was `main`. The trap therefore most likely hits a BuildConfig created through the
> browser. The fix is the same either way: set `ref` explicitly and you never have to
> guess.

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
