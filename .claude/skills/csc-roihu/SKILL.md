---
name: csc-roihu
description: Run jobs on CSC's Roihu supercomputer — Slurm batch jobs, GH200 GPU inference and training, vLLM/PyTorch modules, the Open OnDemand web interface at roihu.csc.fi, billing units, scratch/projappl storage, and the ARM-vs-x86 login node split. Use this whenever the user mentions Roihu, CSC supercomputing, sbatch/squeue/sacct/srun, Slurm partitions like gputest or gpumedium, GH200, `module load`, `/scratch/project_*`, CSC billing units, or wants to run an LLM, fine-tune a model, or do heavy GPU compute "on CSC" — even if they only say "supertietokone", "HPC", "aja tää GPU:lla", or name a module. Also use it to decide between Roihu, Rahti and Aitta. Not for CSC Rahti/OpenShift container deployments (use csc-rahti) — Roihu is batch compute, not a hosting platform.
compatibility: Requires SSH plus a daily MyCSC-signed certificate to reach roihu-cpu.csc.fi / roihu-gpu.csc.fi, or the Open OnDemand web interface as a fallback. The bundled certificate-matching script (scripts/) is PowerShell (Windows); the same steps work manually with `ssh-keygen` elsewhere.
---

# CSC Roihu

Roihu is CSC's Slurm supercomputer: 486 AMD Turin CPU nodes (x86) and 132 NVIDIA
GH200 GPU nodes (ARM). It is **batch compute you rent by the second**, not a place
to host a service. That distinction drives almost every decision below.

## Access

Two login nodes with **different CPU architectures**. Anything compiled — including
Python virtualenvs, conda envs and pip wheels — works on one and not the other:

| Host | Arch | Use for |
|---|---|---|
| `roihu-cpu.csc.fi` | x86-64 | CPU jobs, x86 builds |
| `roihu-gpu.csc.fi` | aarch64 (Grace) | **all GPU jobs**, ARM builds |

They share one filesystem, so files move freely; binaries do not.

### Getting a shell

**There is no bare `roihu.csc.fi` login host.** That name resolves — it serves the
web interface — but it does not answer SSH, so `ssh user@roihu.csc.fi` hangs until
it times out. The hostname, not the network, is the usual cause of that timeout.
Always connect to `roihu-cpu.csc.fi` or `roihu-gpu.csc.fi`.

**SSH additionally needs a MyCSC-signed certificate, valid 24 h** — an uploaded
public key alone is not enough, which is unusual among CSC systems. The user does
this; an agent cannot:

1. <https://my.csc.fi> → Profile → SSH public keys → add `~/.ssh/id_ed25519.pub`
   (up to an hour to activate the first time)
2. Same page → ⋮ menu on the key → **Sign and download SSH certificate**
3. Save it next to the private key as `~/.ssh/id_ed25519-cert.pub` — OpenSSH picks
   up `<keyname>-cert.pub` automatically, no config needed
4. `ssh <csc-username>@roihu-gpu.csc.fi`

Repeat steps 2–3 daily. The certificate is bound to that specific public key, so
every machine needs its own signed certificate (or a copy of the same keypair).

**A CLI alternative avoids the daily download entirely.** CSC's certificate helper
tool signs from the terminal and writes `<key>-cert.pub` straight to the right
place, so there is no file to find, rename or mix up:

```
python csc_cert.py -u <csc-username> ~/.ssh/id_ed25519.pub
```

It prints a login URL, takes a 6-digit code back from the browser, and asks for the
key passphrase — so it is interactive and cannot be fully automated, but it is one
command instead of a web session. Get it from
<https://github.com/CSCfi/certificate-helper-tool/releases>. Prefer this when the
user is renewing daily; the MyCSC download path below is the fallback.

Because MyCSC signs each registered key separately, an account with several
machines downloads several files called `cert.pub`, `cert (1).pub` … that are
indistinguishable by name, and installing the wrong one fails as `Permission
denied (publickey)` with no clue that the certificate was at fault. On Windows,
[scripts/Install-CscCertificate.ps1](scripts/Install-CscCertificate.ps1) matches
them by fingerprint, installs the right one and verifies the connection:

```powershell
$env:CSC_USERNAME = '<csc-username>'
& "$HOME\.claude\skills\csc-roihu\scripts\Install-CscCertificate.ps1"
```

Elsewhere, do the same by hand — `ssh-keygen -lf ~/.ssh/id_ed25519.pub` and
`ssh-keygen -lf cert.pub` print the fingerprint; the matching pair belongs
together, and `ssh-keygen -Lf` shows the validity window.

Diagnose failures by which layer breaks — they need completely different fixes:

| Symptom | Cause | Fix |
|---|---|---|
| Connection timed out, or `Network is unreachable` | wrong hostname, or port 22 blocked by the local network | use `roihu-gpu.csc.fi`; if that also fails while `github.com:22` works, the network blocks it → use the web terminal |
| `Permission denied (publickey)` | no certificate, or it expired | re-sign in MyCSC (steps 2–3) |

`roihu.csc.fi` answers on 443 and refuses 22, so probing *that* host proves nothing
about the network and reads exactly like a firewall. Probe a login node, and probe a
second SSH host to tell "this host" from "this network" apart.

Verify the layers separately rather than guessing:
`Test-NetConnection roihu-gpu.csc.fi -Port 22` (or `nc -vz`) proves reachability;
only then is an auth error meaningful.

When SSH is unavailable, the web terminal works over HTTPS instead:

- Dashboard: <https://www.roihu.csc.fi/pun/sys/dashboard/> (Open OnDemand)
- GPU shell: `/pun/sys/dashboard/apps/show/ood-shell-gpu` → lands on `roihu-gpu`
- CPU shell: `/pun/sys/dashboard/apps/show/ood-shell-cpu`

Driving the web terminal from a browser tool is workable but slow — see
[references/open-ondemand.md](references/open-ondemand.md) for the technique that
keeps it cheap (heredocs, background jobs, `clear` before every command).

## Orient before doing anything

**`csc-projects` and `csc-workspaces` do not exist on Roihu.** They are Puhti and
Mahti tools; on Roihu they are absent from `PATH`, from a login shell and from
`/appl/bin`, so a script that opens with them fails at the first line. Use these
instead — all four work over a plain non-interactive `ssh host "…"`:

```bash
id -Gn | tr ' ' '\n' | grep '^project_'      # which projects you are actually in
sacctmgr -n show assoc user=$USER format=Account%20,QOS   # Slurm accounts you can bill
lfs quota -hg project_XXXXXXX /scratch       # scratch usage against the quota
sinfo -o '%20P %5D %14F %10m %20G %10l'      # partitions, free nodes, GRES, time limit
```

`ls -d /scratch/project_*` is not an answer to "which projects are mine" — that
directory is world-readable and lists every project on the machine. Membership comes
from `id -Gn`; writability confirms it (`[ -w /scratch/project_X ]`).

Never guess the project number — jobs need `--account=project_XXXXXXX` and a wrong
one fails or bills the wrong budget. BU budgets are not visible from the command line
on Roihu; check them in MyCSC.

## Storage

| Path | Default quota | Purpose |
|---|---|---|
| `$HOME` | 15 GiB | dotfiles, tiny scripts. Fills up fast — never put model weights here |
| `/projappl/project_XXXXXXX` | 15 GiB | installed software, containers |
| `/scratch/project_XXXXXXX` | 250 GiB | datasets, model weights, job output |

Point `HF_HOME`, `TMPDIR` and any cache at scratch. The default HF cache is
`~/.cache/huggingface`, which will blow the 15 GiB home quota on the second model.

**Scratch is automatically cleaned — files untouched for 180 days are deleted.**
`csc-workspaces` prints the exact policy and current usage. Anything that must
survive belongs in projappl, Allas, or off-site.

## Partitions and what they cost

| Partition | Max time | Notes |
|---|---|---|
| `test` / `gputest` | 15 min | near-zero queue, ideal for a smoke test |
| `interactive` / `gpuinteractive` | 36 h / 12 h | interactive sessions |
| `small` / `medium` / `large` | 72 h / 36 h / 36 h | CPU |
| `gpumedium` / `gpularge` | 36 h | GPU, up to 4 / 10 nodes |
| `longrun` / `hugemem` | 10 d / 36 h | long or 6 TiB-memory CPU jobs |

GPU nodes have 4× GH200; each GPU has **96 GiB HBM** and 120 GiB Grace memory.
Request GPUs with `--gres=gpu:gh200:N` (N ≤ 4 per node).

**Billing units:**

```
GPU BU  = numGPUs * 200 BU/GPU-hour * runtime
CPU BU  = max(0.75 BU/core-h * cores, 0.375 BU/GiB-h * mem) * runtime
```

The CPU line covers the core-billed partitions (`small`, `longrun`, `interactive`,
`test`). Two exceptions bill differently and are easy to underestimate: `hugemem`
is `max(12 BU/core-h * cores, 0.25 BU/GiB-h * mem)`, and the node-allocated
`medium` / `large` bill **288 BU per node-hour** regardless of how much of the node
the job uses. Reserved disaggregated or local scratch adds 0.02 BU/GiB-hour.

CSC is free of charge for Finnish academic use — no invoice arrives. BUs are still a
real constraint though: they are a rationed grant per project, and at 200 BU per
GPU-hour a 1 000 BU allocation is **five GPU-hours**. More can be requested for free
in MyCSC (project → resources), which takes time but no money, so treat a small
budget as a scheduling problem rather than a hard wall.

Slurm bills wall time, not utilisation — an idle server costs the same as a
saturated one. Translate any multi-hour plan into GPU-hours for the user before
running it, and check the current rates at
<https://docs.csc.fi/computing/hpc-billing/> rather than trusting these numbers.

## Batch job template

```bash
#!/bin/bash
#SBATCH --account=project_XXXXXXX
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=00:15:00
#SBATCH --output=job-%j.out

module load python-vllm          # or python-pytorch, tykky, ...
export HF_HOME=/scratch/project_XXXXXXX/$USER/hf
srun python my_script.py
```

Submit and follow:

```bash
sbatch job.sh                    # -> "Submitted batch job 657882"
squeue --me                      # ST=PD pending, R running; NODELIST shows the node
tail -f job-657882.out
sacct -j 657882 --format=JobID,Elapsed,State,AllocTRES%60
seff 657882                      # efficiency — did it actually use the GPU?
```

Omit `--mem` on GPU partitions: Slurm allocates memory proportional to the GPU
count and will override a smaller request (you get ~217 GiB per GPU regardless).

## Running LLMs

`module load python-vllm` gives a working vLLM on the GH200 nodes. Offline batch
inference is the mode that fits a supercomputer; an OpenAI-compatible server is
possible but has real caveats around cost and reachability.

Read [references/llm-inference.md](references/llm-inference.md) for both patterns,
model downloading, and how to reach a server from outside.

## Interactive work

- **Attach to a running job:** `srun --jobid=<id> --overlap --pty bash` — direct SSH
  into compute nodes is not configured on Roihu.
- **Interactive allocation:** `srun -A project_X -p gpuinteractive --gres=gpu:gh200:1 -t 1:00:00 --pty bash`
- **OOD apps** (Jupyter, VS Code, RStudio, Desktop, TensorBoard, MLflow) launch as
  Slurm jobs on compute nodes and are the easiest way to get a GPU + an editor +
  a browser-reachable UI in one step, with no SSH and no tunnel.

## Choosing Roihu vs LUMI vs Rahti vs Aitta

Users often ask for the wrong one. Route on *lifetime* first, then on vendor:

| Need | Use | Why |
|---|---|---|
| Train, fine-tune, evaluate, batch-infer over a dataset | **Roihu** | NVIDIA GH200, CUDA, ends when the job ends |
| The same, but at scale or where AMD/ROCm is fine | **LUMI** (`csc-lumi`) | MI250X, GPU-hour allocations, its own login and software stack |
| A model endpoint your app calls, from anywhere, whenever | **Aitta** (`aitta-api.csc.fi`) | OpenAI-compatible, always on, no job to babysit — see the `csc-rahti` skill |
| A web app, API or database that must stay up | **Rahti** | container cloud, public HTTPS routes, no GPUs |

Roihu and LUMI are both batch compute and neither hosts a service. Pick between them on
CUDA versus ROCm and on how many GPU-hours the project actually has: they are separate
grants, separate project numbers (`project_2XXXXXX` against `project_46XXXXXXX`) and
separate logins — LUMI needs no certificate at all.

Roihu can serve an API, but only inside a time-limited job, only reachable from the
CSC network, and at 200 BU/GPU-hour. That is fine for a day of experiments and wrong
for anything a colleague or a deployed app depends on.

## Gotchas

- **`vllm serve` shutdown prints `ERROR ... Engine core proc EngineCore died
  unexpectedly`.** This is normal teardown noise after a successful run. Check the
  exit state with `sacct`, not the last line of the log.
- **aarch64 on GPU nodes.** Many PyPI wheels have no ARM build. Prefer the provided
  modules or a container (`tykky`, or the CSC-built vLLM image in Satama) over
  `pip install` into a fresh venv.
- **Compute nodes have no internet.** Login nodes do. Download models, datasets and
  packages on the login node, then run with `HF_HUB_OFFLINE=1` so a failed lookup
  errors loudly instead of hanging.
- **`--mem` is silently overridden on GPU partitions** (`sbatch: Overriding job
  --mem=65536 request with --mem=217086`). Not an error.
- **vLLM startup costs ~40 s** before the first token. Batch many prompts into one
  `llm.chat(...)` call rather than one job per prompt — the GPU-hour is already paid.
- **`gputest` is 15 min hard.** A job that needs 20 min dies at 15 with no output
  unless the script writes incrementally. Use it to prove the script runs, then
  resubmit to `gpumedium`.
- **Billing lags.** `csc-projects` can still show 0 BU used right after a job
  finishes. Don't conclude the job was free.
- **A working session says nothing about tomorrow.** The certificate expires 24 h
  after signing, so `Permission denied (publickey)` on a setup that worked
  yesterday means "re-sign", not "something broke". Check with
  `ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub` before debugging anything else.
