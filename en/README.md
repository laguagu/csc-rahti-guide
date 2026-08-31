# CSC Rahti 2 Handbook

> Deploying applications to **CSC's Rahti 2 container cloud** (OpenShift/OKD) three ways:
> from the browser, from the command line, and with an AI coding agent. Includes four
> agent skills that teach Claude Code, Copilot, Cursor or Codex to use CSC's environments
> correctly — and a tested example app you can have running in five minutes.

🇫🇮 [Suomeksi](../README.md) &nbsp;·&nbsp;
📄 [Guide as PDF](../docs/pdf/csc-rahti-guide-en.pdf) &nbsp;·&nbsp;
📚 [Official CSC documentation](https://docs.csc.fi/cloud/rahti/)

---

## Where to start

| You want to… | Go here |
| --- | --- |
| see something working right now | [Five minutes](#five-minutes) below |
| understand what you are doing | [Chapter 1: Getting started](../docs/en/01-getting-started.md) |
| do it in the browser | [Chapter 2: Deploy from the browser](../docs/en/02-deploying.md#3-deploy-from-the-browser) |
| fix a broken app | [Chapter 9: Troubleshooting](../docs/en/09-troubleshooting.md) |
| let an agent do the work | [Chapter 10: Agentic development](../docs/en/10-agentic-development.md) |
| pass the guide on to someone | [PDF in English](../docs/pdf/csc-rahti-guide-en.pdf) · [in Finnish](../docs/pdf/csc-rahti-opas-fi.pdf) |

---

## Five minutes

The repo ships [`examples/hello-rahti`](../examples/hello-rahti/) — a dependency-free
example app that satisfies every Rahti constraint. **These commands were run as-is
against Rahti 2**, so they work.

```bash
git clone https://github.com/laguagu/csc-rahti-guide
cd csc-rahti-guide/examples/hello-rahti

# 1. Log in — in the console: your name → Copy login command
oc login https://api.2.rahti.csc.fi:6443 --token=sha256~<your-token>
oc project <your-project>

# 2. ImageStream BEFORE the push, or the push fails with HTTP 500
oc create imagestream hello-rahti

# 3. Build and push
docker build --platform linux/amd64 -t hello-rahti .
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi
docker tag  hello-rahti image-registry.apps.2.rahti.csc.fi/<your-project>/hello-rahti:latest
docker push image-registry.apps.2.rahti.csc.fi/<your-project>/hello-rahti:latest

# 4. Deployment, Service and a public HTTPS address
oc new-app --image-stream=hello-rahti
oc expose deployment/hello-rahti --port=8080
oc create route edge hello-rahti --service=hello-rahti --insecure-policy=Redirect

# 5. Address and smoke test
oc get route hello-rahti -o jsonpath='{.spec.host}{"\n"}'
```

<img src="../docs/images/hello-rahti-live.jpg" alt="hello-rahti running on Rahti" width="620">

The app prints its pod name and the UID it was assigned — proof that the container
started, the Service found the pod and the Route answers. Clean up afterwards:

```bash
oc delete route/hello-rahti svc/hello-rahti deployment/hello-rahti is/hello-rahti
```

> **Step 4 is what breaks most guides.** `oc new-app` creates only a Deployment, not a
> Service. Without the `oc expose` line, creating the route fails with *"you need to
> provide a route port via --port when exposing a non-existent service"*.

---

## Contents

| # | Chapter | What's in it |
| --- | --- | --- |
| 1 | [Getting started](../docs/en/01-getting-started.md) | Access and MFA, projects, the `oc` tool, service accounts, quotas, security restrictions, when **not** to use Rahti |
| 2 | [Deploying an application](../docs/en/02-deploying.md) | Building images, registries (Rahti / Satama / Docker Hub), deploying from the console and from manifests, image triggers, deploy script |
| 3 | [GitHub integration](../docs/en/03-github-integration.md) | BuildConfig, SSH keys, webhooks, the known SSH bug, `main` vs. `master` |
| 4 | [Routes and networking](../docs/en/04-routes-and-networking.md) | Service DNS, routes, custom URLs, TLS, the 504 timeout, IP allow-listing, custom domains |
| 5 | [Environment variables](../docs/en/05-environment-variables.md) | Build time vs. runtime, secrets, ConfigMaps, rotation, pitfalls |
| 6 | [Frontend and backend](../docs/en/06-frontend-and-backend.md) | React (Vite) + Node.js three ways, CORS, health probes, ports |
| 7 | [Database](../docs/en/07-database.md) | PostgreSQL + pgvector, persistent storage, pgAdmin, backups |
| 8 | [Allas S3](../docs/en/08-allas-s3.md) | Object storage, S3 credentials, boto3 and AWS SDK, the path-style requirement |
| 9 | [Troubleshooting](../docs/en/09-troubleshooting.md) | CrashLoopBackOff, ImagePullBackOff, OOMKilled, 504, "the deploy didn't update", false alarms |
| 10 | [Agentic development](../docs/en/10-agentic-development.md) | Installing and using the skills, UI vs. CLI vs. agent, safety rules |

---

## Agent skills

A [skill](https://support.claude.com/en/articles/12512176-what-are-skills) is a markdown
file that tells an AI agent how to do something correctly. Nothing to install, no API
key — and the same file works for Claude, Copilot, Cursor and Codex.

| Skill | For | Mode |
| --- | --- | --- |
| [`csc-rahti`](../.claude/skills/csc-rahti/) | Rahti deployment, images, routes, secrets, the **Satama** registry, **Allas**, the **Aitta** LLM API | read + write |
| [`rahti-audit`](../.claude/skills/rahti-audit/) | Whole-namespace status overview in one run | **read-only** |
| [`csc-roihu`](../.claude/skills/csc-roihu/) | Roihu supercomputer: Slurm, GH200 GPUs, running your own LLMs | read + write |
| [`csc-lumi`](../.claude/skills/csc-lumi/) | LUMI: AMD MI250X, ROCm | read + write |

```bash
# Clone the repo — Claude Code reads .claude/skills/ automatically
git clone https://github.com/laguagu/csc-rahti-guide && cd csc-rahti-guide && claude

# OR copy them into your personal folder, available in every project
cp -r .claude/skills/csc-rahti ~/.claude/skills/
```

Then describe the task in plain language:

```
Deploy this Next.js app to Rahti in project my-project, port 3000
Check whether anything is broken in Rahti
The app returns 504 when a query takes over half a minute — fix it
```

> **An agent cannot complete CSC's MFA.** Log in yourself with `oc login` first, or use a
> [service account](../docs/en/01-getting-started.md#service-account-for-long-term-use)
> whose token lasts as long as you choose.

Installing for other agents, syncing skills across machines and the safety rules:
[chapter 10](../docs/en/10-agentic-development.md).

---

## What's in the repo

```
README.md · en/README.md      landing pages in Finnish and English
docs/fi/ · docs/en/           chapters 1–10 in both languages
docs/pdf/                     the same guides as shareable PDFs
docs/images/                  screenshots from the Rahti console
examples/hello-rahti/         tested example application
.claude/skills/               four agent skills
scripts/                      link checking and PDF generation
```

---

## Key addresses

| Service | Address |
| --- | --- |
| Rahti console | <https://console.rahti.csc.fi> |
| Rahti API | `https://api.2.rahti.csc.fi:6443` |
| Container registry | `image-registry.apps.2.rahti.csc.fi` |
| Application URLs | `*.2.rahtiapp.fi` |
| Satama (container registry, Harbor) | <https://satama.csc.fi/harbor/projects> |
| Allas (object storage) | <https://allas.csc.fi> |
| Aitta (LLM API) | <https://aitta.csc.fi> |
| MyCSC (projects and access) | <https://my.csc.fi> |
| CSC documentation | <https://docs.csc.fi/cloud/rahti/> |
| Service Desk | servicedesk@csc.fi |

---

## For contributors

```bash
pnpm install
pnpm run check:links     # verifies every internal link and anchor
pnpm run test:skills     # runs the csc-rahti skill's PowerShell tests
pnpm run build:pdf       # rebuilds the guides in docs/pdf/
```

PDFs are rendered with Chrome or Edge (`CHROME_PATH` overrides the location) and are
committed so the guide can be shared as a single file. Re-run `build:pdf` whenever you
edit a chapter.

---

## About

This is a **community guide**, not official CSC documentation. Where the two disagree,
[docs.csc.fi](https://docs.csc.fi/cloud/rahti/) is right.

The screenshots were taken from the Rahti 2 console in August 2026 and the commands were
run against the real environment. The console gets redesigned from time to time — if the
guide and your screen disagree, follow the menu names rather than the pixels.

Corrections and additions are welcome as issues and pull requests.
License: [MIT](../LICENSE). The Haaga-Helia mark on the PDF cover pages is the property
of Haaga-Helia University of Applied Sciences.
