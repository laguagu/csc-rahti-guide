# CSC Rahti 2 Handbook

Practical instructions for deploying applications on **CSC's Rahti 2 container cloud**
(OpenShift/OKD) — from the web console, from the command line, and with an AI coding
agent. Includes four ready-made **agent skills** that teach Claude Code and other coding
agents how to use CSC's environments correctly.

🇫🇮 [Suomenkielinen versio](../README.md) · 📚 [Official CSC documentation](https://docs.csc.fi/cloud/rahti/)

---

## 🚀 Quick start

An app running in five commands (assumes Rahti access is in place and `oc` and Docker are
installed):

```bash
# 1. Log in — in the console: your name → Copy login command
oc login https://api.2.rahti.csc.fi:6443 --token=sha256~<your-token>

# 2. Build the image (amd64, also on Apple Silicon)
docker build --platform linux/amd64 -t myapp .

# 3. Log in to the Rahti registry and create the ImageStream
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi
oc create imagestream myapp

# 4. Tag and push
docker tag myapp image-registry.apps.2.rahti.csc.fi/<project>/myapp:latest
docker push image-registry.apps.2.rahti.csc.fi/<project>/myapp:latest

# 5. Deploy and open a public HTTPS address
oc new-app --image-stream=myapp
oc create route edge --service=myapp --insecure-policy=Redirect
oc get route myapp -o jsonpath='{.spec.host}{"\n"}'
```

New to Rahti? Start with [1. Getting started](../docs/en/01-getting-started.md).

<img src="../docs/images/rahti-add-page.jpg" alt="The +Add view in the Rahti console" width="720">

---

## 📖 Contents

| # | Chapter | What's in it |
| --- | --- | --- |
| 1 | [**Getting started**](../docs/en/01-getting-started.md) | Access, MFA login, projects, the `oc` tool, service accounts, quotas, security restrictions |
| 2 | [**Deploying an application**](../docs/en/02-deploying.md) | Building images, registries (Rahti / Satama / Docker Hub), deploying from the console and from manifests, image triggers, deploy script |
| 3 | [**GitHub integration**](../docs/en/03-github-integration.md) | BuildConfig, SSH keys, webhooks, the "URL is valid but cannot be reached" workaround, main vs. master |
| 4 | [**Routes and networking**](../docs/en/04-routes-and-networking.md) | Service DNS, routes, custom URLs, TLS, the 504 timeout, IP allow-listing, custom domains |
| 5 | [**Environment variables**](../docs/en/05-environment-variables.md) | Build time vs. runtime, secrets, ConfigMaps, rotation, pitfalls |
| 6 | [**Frontend and backend**](../docs/en/06-frontend-and-backend.md) | React (Vite) + Node.js three ways, CORS, health probes, ports |
| 7 | [**Database**](../docs/en/07-database.md) | PostgreSQL + pgvector, persistent storage, pgAdmin over port-forward, backups |
| 8 | [**Allas S3**](../docs/en/08-allas-s3.md) | Object storage, getting S3 credentials, boto3 and AWS SDK, the path-style requirement |
| 9 | [**Troubleshooting**](../docs/en/09-troubleshooting.md) | CrashLoopBackOff, ImagePullBackOff, OOMKilled, 504, "the deploy didn't update", false alarms |
| 10 | [**Agentic development**](../docs/en/10-agentic-development.md) | Installing and using the skills, UI vs. CLI vs. agent, safety rules |

---

## 🤖 Agent skills

The repository ships four skills in [`.claude/skills/`](../.claude/skills/). They are
plain markdown: no software to install, no API key.

| Skill | For | Mode |
| --- | --- | --- |
| [`csc-rahti`](../.claude/skills/csc-rahti/) | Rahti deployment, images, routes, secrets, the Satama registry, Allas, the Aitta LLM API | read + write |
| [`rahti-audit`](../.claude/skills/rahti-audit/) | Whole-namespace status overview in one run | **read-only** |
| [`csc-roihu`](../.claude/skills/csc-roihu/) | Roihu supercomputer: Slurm, GH200 GPUs | read + write |
| [`csc-lumi`](../.claude/skills/csc-lumi/) | LUMI: AMD MI250X, ROCm | read + write |

**Three ways to install them:**

```bash
# 1. Clone the repo — Claude Code reads .claude/skills/ automatically
git clone <repo-url> && cd csc-rahti-guide && claude

# 2. Copy them to your personal skills folder, available in every project
cp -r .claude/skills/csc-rahti ~/.claude/skills/

# 3. Shared .agents/skills path for other agent tools (Claude Code does not read it)
ln -s ~/.claude/skills/csc-rahti ~/.agents/skills/csc-rahti
```

Windows instructions and the reasoning behind each option:
[10. Agentic development](../docs/en/10-agentic-development.md).

Usage:

```
/csc-rahti Create a route for this app at demo.2.rahtiapp.fi
Check whether anything is broken in Rahti
```

> **An agent cannot complete CSC's MFA.** Log in yourself with `oc login` before handing
> a task to an agent — or use a service account
> ([how](../docs/en/01-getting-started.md#service-account-for-long-term-use)).

---

## 🗂️ Repository layout

```
.
├── README.md                  Finnish version
├── en/README.md               ← you are here
├── docs/
│   ├── fi/                    chapters 1–10 in Finnish
│   ├── en/                    chapters 1–10 in English
│   └── images/                screenshots from the Rahti console
└── .claude/skills/
    ├── csc-rahti/             SKILL.md + references/ + scripts/ + tests/
    ├── rahti-audit/
    ├── csc-roihu/
    └── csc-lumi/
```

---

## 🔗 Key addresses

| Service | Address |
| --- | --- |
| Rahti console | <https://console.rahti.csc.fi> |
| Rahti API | `https://api.2.rahti.csc.fi:6443` |
| Container registry | `image-registry.apps.2.rahti.csc.fi` |
| Application URLs | `*.2.rahtiapp.fi` |
| Satama (Harbor) | <https://satama.csc.fi> |
| Allas | <https://allas.csc.fi> |
| MyCSC (projects and access) | <https://my.csc.fi> |
| CSC documentation | <https://docs.csc.fi/cloud/rahti/> |
| Service Desk | servicedesk@csc.fi |

---

## 🛠️ Repository tooling

```bash
pnpm install
pnpm run check:links     # verifies every internal link and anchor
pnpm run test:skills     # runs the csc-rahti skill's PowerShell tests
pnpm run format          # prettier

node scripts/build-pdf.mjs        # printable PDF in both languages → build/
node scripts/build-pdf.mjs en     # English only
```

PDFs are generated on demand and deliberately not committed — they would go stale the
moment a chapter changes. PDF generation needs a local Chrome or Edge (point
`CHROME_PATH` elsewhere if it is installed in a non-standard location).

---

## ℹ️ About

This is a **community guide**, not official CSC documentation. Where the two disagree,
[docs.csc.fi](https://docs.csc.fi/cloud/rahti/) is always right.

The screenshots were taken from the Rahti 2 console in August 2026. The console gets
redesigned from time to time — if the guide and your screen disagree, follow the menu
names rather than the pixels.

Corrections and additions are welcome as issues and pull requests.

License: [MIT](../LICENSE).
