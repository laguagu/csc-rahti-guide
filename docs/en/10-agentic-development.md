# 10. Agentic development: skills for working with Rahti

> This repository includes four **agent skills** that teach an AI agent (Claude Code,
> Codex, Cursor, etc.) to use CSC's environments correctly. A skill is just a markdown
> file — nothing to install, no API key.

## Contents

- [What a skill is](#what-a-skill-is)
- [The repository's skills](#the-repositorys-skills)
- [Installation](#installation)
- [Usage](#usage)
- [UI vs. CLI vs. agent](#ui-vs-cli-vs-agent)
- [What the agent can't do](#what-the-agent-cant-do)
- [Safety rules](#safety-rules)
- [Editing the skills](#editing-the-skills)
- [Skills across multiple machines](#skills-across-multiple-machines)
- [Further reading](#further-reading)

## What a skill is

A skill is a folder containing `SKILL.md` and, optionally, additional files:

```
csc-rahti/
├── SKILL.md              # instructions for the agent + a description of when to use it
├── references/           # deeper reference docs, read only when needed
│   ├── routes.md
│   ├── authentication.md
│   └── …
├── scripts/               # runnable helper scripts
└── tests/                 # tests for the scripts
```

At the top of `SKILL.md` is a YAML block whose `description` field tells the agent
**when** it's worth loading the skill. The agent reads the descriptions continuously,
but only reads the full content once it's relevant — that way even dozens of skills
don't fill up the context window.

The practical benefit: without the skill, the agent guesses Rahti's details wrong
(outdated console navigation, `runAsUser` in a manifest, a forgotten ImageStream). With
the skill, it knows the house conventions.

## The repository's skills

| Skill | For | When it triggers |
| --- | --- | --- |
| **[csc-rahti](../../.claude/skills/csc-rahti/)** | Rahti deployment, images, routes, secrets, Satama, Allas, the Aitta LLM API | "deploy to Rahti", "oc", "rahtiapp.fi", "imagestream", "satama" |
| **[rahti-audit](../../.claude/skills/rahti-audit/)** | Read-only status overview of a whole namespace | "is production okay", "audit Rahti", "crashloop" |
| **[csc-roihu](../../.claude/skills/csc-roihu/)** | The Roihu supercomputer: Slurm, GH200 GPUs, modules | "sbatch", "run on GPU", "supercomputer" |
| **[csc-lumi](../../.claude/skills/csc-lumi/)** | LUMI: AMD MI250X, ROCm, the LUMI software stack | "LUMI", "ROCm", "MI250X" |

The division of labor is deliberate: `rahti-audit` is **read-only** and must never fix
anything; `csc-rahti` makes changes. That way "check what's broken" can never
accidentally alter production.

A quick guide to choosing between CSC services:

| Need | Service | Skill |
| --- | --- | --- |
| Stand up a web app or API | Rahti | csc-rahti |
| Train a model or run a large batch job on NVIDIA GPUs | Roihu | csc-roihu |
| The same on AMD GPUs, with a EuroHPC quota | LUMI | csc-lumi |
| A ready-made LLM endpoint without your own GPU | Aitta | csc-rahti (Aitta section) |

## Installation

### Option 1: clone the repository (easiest)

When you open this repository with Claude Code, the skills are available right away —
they live in `.claude/skills/`, which Claude Code reads on a per-project basis.

```bash
git clone <this-repo-url>
cd csc-rahti-guide
claude
```

### Option 2: copy them for personal use (all projects)

Copy the skills you want into your personal skills folder, and they'll be available in
every project:

```bash
# macOS / Linux
cp -r .claude/skills/csc-rahti ~/.claude/skills/
cp -r .claude/skills/rahti-audit ~/.claude/skills/
```

```powershell
# Windows PowerShell
Copy-Item -Recurse .claude\skills\csc-rahti  "$HOME\.claude\skills\"
Copy-Item -Recurse .claude\skills\rahti-audit "$HOME\.claude\skills\"
```

Check the result in Claude Code with the `/skills` command.

### Option 3: shared `.agents/skills` folder

Some agent tools read skills from `.agents/skills/` (the
[agentskills.io](https://agentskills.io) convention). The same `SKILL.md` works for
both, so there's no need to duplicate files — make a link instead:

```bash
# macOS / Linux
mkdir -p ~/.agents/skills
ln -s ~/.claude/skills/csc-rahti ~/.agents/skills/csc-rahti
```

```powershell
# Windows: a directory junction (does not require administrator rights)
New-Item -ItemType Junction -Path "$HOME\.agents\skills\csc-rahti" `
         -Target "$HOME\.claude\skills\csc-rahti"
```

> **Claude Code does not read `.agents/skills`** — for it, `~/.claude/skills/` or the
> project's `.claude/skills/` is enough. The link is there for other tools, and points
> that way round so that the Claude Code path stays the original.
>
> If your tool reads its instructions from an `AGENTS.md` file, add a line there
> pointing to this repository's `docs/` folder and skills.

### Dependencies

The skills themselves require nothing, but the commands they recommend do:

| Tool | For | Check |
| --- | --- | --- |
| `oc` | all Rahti operations | `oc version --client` |
| `docker` or `podman` | building images | `docker --version` |
| PowerShell 7 | the `csc-rahti` and `rahti-audit` scripts | `pwsh --version` |
| `openstack` | Allas credentials | `openstack --version` |

## Usage

**Invoke it by name** (Claude Code, slash command):

```
/csc-rahti How do I get an address like demo.2.rahtiapp.fi for my app?
```

**Or just describe the task** — the skill triggers on its own based on its
description:

```
Deploy this Next.js app to Rahti in the project my-project,
port 3000, and set up a route for it.
```

```
Check whether anything is broken in Rahti.
```

```
gaik-demo returns a 504 when a query takes more than half a minute. Fix it.
```

A typical agent workflow for Rahti:

1. **Log in yourself** — the agent can't get through MFA (see below). Run `oc login`
   or `Connect-Rahti.ps1`.
2. **Give it the task.** The agent reads the skill, checks the current state with
   `oc get` commands, and proposes changes.
3. **Review the proposal** before approving any write commands.
4. **Let it run the deploy** and read the `oc rollout status` output.

## UI vs. CLI vs. agent

| Task | Recommendation | Why |
| --- | --- | --- |
| First-time exploration | **UI** | You see what objects get created |
| A one-off demo deployment | **UI** | Fastest, no files needed |
| Repeated deployment | **CLI + manifests** | Version-controlled, repeatable |
| Quick change to an environment variable | **UI** or `oc set env` | Both trigger a rollout |
| Creating secrets | **CLI** | `--from-literal` is precise; the form doesn't show the result |
| Reading logs | **UI** for light use, `oc logs -f` for serious use | The UI truncates long logs |
| Production status overview | **Agent** (`rahti-audit`) | Ten commands in one run, reports only the anomalies |
| Troubleshooting | **Agent + CLI** | The agent knows the right order to check things; you decide the fix |
| Raising quotas, permissions | **UI + Service Desk** | Requires a human |

Rule of thumb: **UI for learning and one-off tasks, CLI for repeatable work, agent for
speeding up routine tasks.** An agent doesn't replace understanding what it's doing —
that's why it's worth reading chapters 1–9 even if you let an agent do the work.

## What the agent can't do

- **Get through CSC's MFA.** A personal login is always a human task. The agent can
  use an already-created service account, but it can't create the first credential
  without you having logged in.
- **Fetch a token from the web console.** *Copy login command* requires a browser
  session.
- **Raise a quota or grant Rahti permissions** — those go through MyCSC and the
  Service Desk.
- **Know project-specific limits without checking.** Have it run
  `oc describe limitranges` instead of trusting default assumptions.

## Safety rules

The skills are written according to these rules, and the same rules apply to you:

1. **Tokens are never printed.** Not to chat, not to logs, not to a commit. Scripts
   pass the token straight to `oc`.
2. **Secrets stay out of the repository.** Service account tokens are stored in a
   separate env directory, not in the skill and not in the project.
3. **Read-only stays read-only.** `rahti-audit` never runs `oc delete`, `oc scale`, or
   `oc apply` — even when the fix looks obvious.
4. **Write commands against production are confirmed.** `oc delete`, `oc scale
   --replicas=0`, and `oc apply` are things worth reading before approving.
5. **Least privilege.** `view` for auditing, `edit` for deployment, `admin` only if
   managing permissions is actually needed.

## Editing the skills

The skills are deliberately readable markdown — adapt them to your own environment:

- Swap the `<namespace>` placeholders for your own project's name if you only work in
  one.
- Add your own organization's conventions to the `references/` folder.
- Keep the `description` field descriptive: it determines whether the skill triggers
  at the right time.
- The scripts are tested — if you change them, run the tests:

```powershell
pwsh -NoProfile -Command "& '.claude/skills/csc-rahti/tests/RahtiCredentials.Tests.ps1'"
```

**Do not** commit project-specific namespaces, credentials, customer names, or tokens
into a skill if the repository is public.

## Skills across multiple machines

If you work across multiple machines, don't copy skills from one machine to another —
they'll drift apart within a week. Keep one folder as the single source of truth and
link to it:

```powershell
# A folder that syncs between machines (OneDrive, Dropbox, a git repo…)
$src = "$HOME\OneDrive\agents-setup\skills"

# Claude Code reads this path
New-Item -ItemType Junction -Path "$HOME\.claude\skills" -Target $src
```

```bash
# macOS / Linux
ln -s ~/Sync/agents-setup/skills ~/.claude/skills
```

The same folder can serve several tools at once: one source, many links. Secrets don't
belong in this folder — keep them separate (e.g. `agents-setup/env/`), so that sharing
skills never shares tokens along with them.

A git repo as the sync folder is the best option for a team: changes are reviewable
and the history is visible.

## Further reading

**Skills in general**

- [What are Skills?](https://support.claude.com/en/articles/12512176-what-are-skills) — Anthropic's overview
- [Claude Code: Skills](https://code.claude.com/docs/en/skills) — the `SKILL.md` format, frontmatter fields, and lookup paths
- [agentskills.io](https://agentskills.io) — the tool-agnostic specification this repository's skills follow

**Packaging skills for wider distribution**

If skills start to pile up and you want to share them across an organization, the next
step is packaging them as a plugin — skills, tools, and configuration bundled as one
installable unit:

- [Agent plugins: package your skills, tools and more](https://developers.googleblog.com/agent-plugins-package-your-skills-tools-and-more/) — what a plugin contains and when it's worth it
- [Claude Code: Plugins](https://code.claude.com/docs/en/plugins) — plugin structure and installation

> As of this writing, the `agent-plugins.org` specification page doesn't respond with
> a valid TLS certificate (the browser warns you), so the links above are the working
> sources.

**Why isn't this repo packaged as a plugin?** It was considered and rejected, for three
reasons:

1. A Claude Code plugin reads skills from `skills/` at the plugin root, not from
   `.claude/skills/`. The skills would have to be either moved, which would stop a plain
   clone from loading them, or duplicated, which lets two copies drift apart.
2. The plugin format is Claude Code specific. It does nothing for a Copilot, Cursor or
   Codex user, and the whole point of this repo is that one file serves all of them.
3. `cp -r` is not a real obstacle for anyone.

If distribution ever grows, packaging is worth doing then. The calculation changes once
a tool-independent specification is settled enough that one package serves every agent.

**CSC's own documentation**

- [Rahti](https://docs.csc.fi/cloud/rahti/) · [Satama](https://docs.csc.fi/cloud/satama/) · [Allas](https://docs.csc.fi/data/Allas/)
- [Roihu](https://docs.csc.fi/computing/systems-roihu/) · [LUMI](https://docs.lumi-supercomputer.eu/) · [Aitta](https://aitta.csc.fi/)

---

**Previous:** [9. Troubleshooting](09-troubleshooting.md) · **Back:** [Home](../../en/README.md)
