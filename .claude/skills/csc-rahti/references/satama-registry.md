# CSC Satama — Container Image Registry (Harbor)

## Contents
- [Satama vs Rahti internal registry](#satama-vs-rahti-internal-registry)
- [Getting access](#getting-access)
- [CLI login](#cli-login)
- [Push an image](#push-an-image)
- [Robot accounts (CI and agents)](#robot-accounts-ci-and-agents)
- [Pulling Satama images into Rahti / OpenShift](#pulling-satama-images-into-rahti--openshift)
- [Project features worth enabling](#project-features-worth-enabling)
- [Quota and billing](#quota-and-billing)
- [Troubleshooting](#troubleshooting)

Satama is CSC's own container image registry, built on Harbor. It is a **separate
service from Rahti** — Rahti's integrated registry
(`image-registry.apps.2.rahti.csc.fi`) is not deprecated, and neither replaces the
other. Satama is the better choice when images must be shared across services,
projects or CI systems, scanned for vulnerabilities, signed, or kept under
retention/immutability policy.

- Web UI: <https://satama.csc.fi> (project list: <https://satama.csc.fi/harbor/projects>)
- Registry host for docker/podman: `satama.csc.fi`
- Image path: `satama.csc.fi/<satama-project>/<image>:<tag>`
- Docs: <https://docs.csc.fi/cloud/satama/>

## Satama vs Rahti internal registry

| | Rahti internal registry | Satama |
|---|---|---|
| Scope | One Rahti namespace/cluster | Any CSC project, any cluster, laptops, CI |
| Auth | `oc whoami -t` (short-lived) | CLI secret or robot account (long-lived) |
| Extras | ImageStreams, build triggers | CVE scanning, SBOM, signing, retention, audit log |
| Billing | Rahti quota | Cloud BU per stored GiB (see below) |

Rule of thumb: **Rahti registry for the fast inner deploy loop inside one
namespace; Satama when the image outlives or leaves that namespace.**

## Getting access

Requires a CSC user account with MFA, and a CSC project that has Satama enabled
(MyCSC → project → *Apply for Satama access*). On first login only the public
`library` project is visible; other enabled CSC projects appear after ~15 min and
are named `project_<number>`.

Roles inside a Satama project: Limited Guest (pull only) → Guest (pull, retag) →
Developer (push+pull) → Maintainer (+scan, delete) → Project Admin (full).
Grant Developer only to accounts that actually push.

## CLI login

Docker/Podman (any OCI tool) work directly. The password is **not** the MyCSC
password — generate a **CLI secret** in the web UI: username (top right) → *User
Profile* → *CLI Secret* → *Generate New Secret*.

```bash
docker login satama.csc.fi -u <csc-username>   # paste CLI secret as password
podman login satama.csc.fi -u <csc-username>
```

## Push an image

```bash
docker build -t <image>:<tag> .
docker tag  <image>:<tag> satama.csc.fi/<satama-project>/<image>:<tag>
docker push satama.csc.fi/<satama-project>/<image>:<tag>
```

Tag with something immutable (`v1.4.2`, a date, or the git SHA) rather than
`latest` for anything that reaches production — `latest` is overwritten and
destroys reproducibility. Keep a moving `latest` only for the dev loop.

## Robot accounts (CI and agents)

Project → *Robot Accounts* → *New Robot Account*. Choose name, expiry (or never)
and the exact permissions (push / pull / delete). **The secret is shown once and
cannot be retrieved again** — store it in the private env store, never in a repo.

```bash
docker login satama.csc.fi -u '<robot-account-name>' -p "$SATAMA_ROBOT_SECRET"
```

The robot name Harbor generates contains a `$` (project-scoped robots look like
`robot$<project>+<name>`). Copy the name verbatim from the UI and **single-quote
it in shells** so the `$` is not expanded.

## Pulling Satama images into Rahti / OpenShift

**Public Satama project** — no credentials needed; pods pull anonymously.
Anonymous *push* is never allowed.

**Private Satama project** — create a pull secret and attach it to the service
account that pulls:

```bash
oc create secret docker-registry satama-pull \
  --docker-server=satama.csc.fi \
  --docker-username='robot$<project>+<name>' \
  --docker-password="$SATAMA_ROBOT_SECRET" \
  -n <namespace>

oc secrets link default satama-pull --for=pull -n <namespace>
```

Then reference the image directly in the Deployment:

```yaml
image: satama.csc.fi/<satama-project>/<image>:<tag>
```

To keep OpenShift image triggers and `oc rollout` ergonomics, mirror it into an
ImageStream instead:

```bash
oc import-image <name>:<tag> \
  --from=satama.csc.fi/<satama-project>/<image>:<tag> \
  --reference-policy=local --scheduled --confirm -n <namespace>
```

`--scheduled` makes OpenShift re-import periodically, so a new push to Satama
rolls out without a manual step (combine with the
`image.openshift.io/triggers` annotation described in SKILL.md).

## Project features worth enabling

- **Vulnerability scanning** — automatic scan on push; review before promoting an
  image to production.
- **Deployment security** — block deploys of images that fail a severity
  threshold, and/or require a cosign/Notation signature.
- **Tag retention policy** — auto-prune old tags so the storage quota does not
  creep up (storage is what Satama bills for).
- **Tag immutability** — prevents overwriting released tags. Expect
  `denied: ... immutable` when re-pushing a protected tag; publish a new tag.
- **Audit logs** and **SBOM generation** — per project, in the UI.

## Quota and billing

Default quota for a new Satama project is 50 GB; more on request via
servicedesk@csc.fi. Billing is on **stored volume only** (Cloud BU per GiB-hour) —
network transfer is not billed. Check the current rate in
<https://docs.csc.fi/cloud/satama/billing_and_quota/> before estimating cost, and
use retention policies to keep the stored set small.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `unauthorized: authentication required` | Session token expired. Log out and back in to the Satama web UI, regenerate the CLI secret if needed, then `docker login` again. Prefer CLI secret over the MyCSC password. |
| `denied: requested access to the resource is denied` | Not a member of the project, or role below Developer. Also appears when pushing to a project that does not exist. |
| `repository does not exist` | Wrong project or image path — verify the exact path in the web UI before pulling. |
| Push rejected on an existing tag | Tag immutability policy is on. Push a new tag. |
| Pod `ImagePullBackOff` from `satama.csc.fi` | Private project without a pull secret, or the secret is not linked to the pulling service account (`oc secrets link default satama-pull --for=pull`). |

Known issues list: <https://docs.csc.fi/cloud/satama/known_issues/>
