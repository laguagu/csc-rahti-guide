---
name: csc-lumi
description: Run jobs on LUMI, the EuroHPC supercomputer hosted by CSC — Slurm batch jobs on AMD MI250X GPUs, ROCm and PyTorch containers, the LUMI software stack and EasyBuild, /scratch and /flash Lustre storage, GPU-hour allocations, and the Open OnDemand web interface at www.lumi.csc.fi. Use whenever the user mentions LUMI, MI250X, ROCm, HIP, `standard-g`, `small-g`, `dev-g`, `lumi-workspaces`, `lumi-allocations`, `/project/project_46*`, `/flash`, singularity or .sif containers on LUMI, or wants to train, fine-tune or batch-infer a model "on LUMI" — even if they only say "EuroHPC", "AMD GPU" or name a partition. Not for CSC's own Roihu supercomputer (use csc-roihu — different login, different GPUs, different modules) and not for Rahti container hosting (use csc-rahti).
compatibility: Requires plain SSH (a CSC-account or MyAccessID-registered key, no certificate step) to lumi.csc.fi, or the Open OnDemand web interface as a fallback. No bundled scripts; all commands run in the LUMI login shell.
---

# LUMI

LUMI is a EuroHPC supercomputer in Kajaani, operated by CSC. To a Finnish user it looks
like a second CSC supercomputer, and that resemblance is the main hazard: the login flow,
the GPUs, the software stack and the billing all differ from Roihu, so recipes do not
carry over. Route by vendor — **LUMI is AMD, Roihu is NVIDIA.**

| | LUMI | Roihu |
|---|---|---|
| GPU | AMD MI250X, ROCm/HIP | NVIDIA GH200, CUDA |
| Login | plain SSH key | SSH key **plus a 24 h MyCSC certificate** |
| Software | LUMI stack, singularity containers | Lmod modules |
| Allocation | GPU-hours per project | billing units (BU) |
| Project id | `project_46XXXXXXX` (9 digits) | `project_2XXXXXX` (7 digits) |

PyTorch is fine here — it ships for ROCm and `torch.cuda.*` is the same API — but a
CUDA-only wheel from PyPI is not.

## Access

```bash
ssh <csc-username>@lumi.csc.fi        # lands on a uan* user access node
```

**No certificate.** This is the most useful single difference from Roihu: the same
private key that needs a daily MyCSC-signed certificate for `roihu-gpu` logs into LUMI on
its own. So a failure here means the key is not registered — it never means the
certificate expired.

Key management depends on the account type, and `lumi-workspaces` says which applies:

```
- Account is a CSC account, key management through MyCSC (my.csc.fi).
```

A MyAccessID account registers keys at <https://mms.myaccessid.org> instead.

Without SSH, the web interface works over HTTPS:
<https://www.lumi.csc.fi/pun/sys/dashboard/> — shell, Jupyter, VS Code and desktop, each
launched as a Slurm job.

## Orient before doing anything

```bash
lumi-workspaces        # storage quotas AND the state of the allocation, in one command
lumi-allocations       # CPU / GPU / storage used against granted
sinfo -s               # partitions
```

Run `lumi-workspaces` first. It prints the project name, every quota, the days left
before data removal and the share of the allocation already spent — everything needed to
decide whether a plan fits.

## Storage

| Path | Typical quota | Purpose |
|---|---|---|
| `/users/$USER` | 20 GB | home. Never put model weights here |
| `/project/project_46XXXXXXX` | 50 GB | installed software, containers |
| `/scratch/project_46XXXXXXX` | 50 TB | datasets, weights, job output |
| `/flash/project_46XXXXXXX` | 2 TB | NVMe, for IO-bound work |

Quotas are per grant and vary, so read the real numbers from `lumi-workspaces` rather
than trusting this table. **Scratch is removed on a schedule** — `lumi-workspaces` prints
the days remaining — so anything that must survive belongs in /project, LUMI-O object
storage, or off-site.

Point `HF_HOME`, `SINGULARITY_CACHEDIR` and `TMPDIR` at /scratch. Their defaults live
under the 20 GB home, and the second model download fills it.

## Partitions

| Partition | Nodes | Max time | GPUs |
|---|---:|---|---|
| `debug` | 10 | 30 min | — |
| `dev-g` | 49 | 3 h | `gpu:mi250:8` |
| `small` / `small-g` | 305 / 199 | 3 d | `-g` has 8 |
| `standard` / `standard-g` | 1723 / 2728 | 2 d | `-g` has 8 |
| `largemem` | 6 | 1 d | — |
| `interactive` | 6 | 8 h | — |

Prove a script on `dev-g`: three hours is plenty, the queue is short, and it bills the
same as anywhere else. `small*` partitions allocate node fractions; `standard*` give
whole nodes and bill whole nodes.

**"8 GPUs" means 8 GCDs, not 8 cards.** A LUMI-G node holds four MI250X modules and each
presents two Graphics Compute Dies, so Slurm and ROCm both count eight independent
devices with their own memory. Request them with `--gpus-per-node=N`, and read "GPU" as
GCD in every allocation and billing figure.

## Batch job

This exact script has been run on this system (job 21351156, COMPLETED in 1 min):

```bash
#!/bin/bash
#SBATCH --account=project_46XXXXXXX
#SBATCH --partition=dev-g
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=7
#SBATCH --gpus-per-node=1
#SBATCH --time=00:10:00
#SBATCH --output=job-%j.out

set -euo pipefail
SIF=/appl/local/containers/sif-images/lumi-pytorchv0-rocm-6.2.4-python-3.12-pytorch-v2.7.1.sif

srun singularity exec -B /scratch/project_46XXXXXXX "$SIF" python my_script.py
```

```bash
sbatch job.sh                                            # -> Submitted batch job 21351156
squeue --me
sacct -j <id> --format=JobID,Elapsed,State,AllocTRES%40 -X
```

It printed `torch 2.7.1+rocm6.2.4`, `AMD Instinct MI250X`, and a working matmul on the
device. A one-GPU job with 7 cores is accounted as `billing=14,cpu=14,gres/gpu=1`.

## Software: reach for a container first

CSC ships prebuilt ROCm containers, and using one is the shortest path to a working
PyTorch. They are already on the filesystem, so there is nothing to pull:

```bash
ls /appl/local/containers/sif-images/
```

Present on the system, newest PyTorch first:

```
lumi-pytorchv0-rocm-6.2.4-python-3.12-pytorch-v2.7.1.sif     -> torch 2.7.1+rocm6.2.4
lumi-pytorch-rocm-6.2.3-python-3.12-pytorch-v2.5.1.sif
lumi-pytorch-rocm-6.2.1-python-3.12-pytorch-<date>-vllm-*.sif   vLLM builds
lumi-jax-*   lumi-tensorflow-*   lumi-rocm-*   lumi-mpi4py-*
```

Bind the paths the job needs (`-B /scratch/project_46XXXXXXX`); a container sees little
beyond /users by default, and a job that cannot find its dataset usually just needs
the bind.

Modules exist as well — the `LUMI/25.03` and `LUMI/25.09` software stacks, and
`rocm/6.3.4` — but for Python ML work the containers are better maintained and spare you
building ROCm wheels by hand. Lmod here is 8.7.55; select a stack with
`module load LUMI/25.09`.

## Billing

Allocations are granted per project in three currencies, all shown by
`lumi-allocations`:

```
CPU (core/hours) | GPU (gpu/hours) | Storage (TB/hours)
```

GPU hours count GCD-hours, so a full LUMI-G node for an hour is 8 GPU hours. Slurm bills
wall time, not utilisation, so an idle allocation costs what a saturated one does.
Storage is billed too, which is easy to forget: a 50 TB scratch directory consumes the
storage allocation whether or not anything reads it.

## Gotchas

- **`sinfo` with a wide format can stall on a login node.** It is a very large cluster.
  Write to a file — `sinfo -h -o "%P %D %l %G" > /tmp/si.txt` — instead of piping a big
  format string through a slow terminal.
- **`module` does not exist in a non-interactive SSH command.** `ssh lumi 'module list'`
  fails with "command not found"; use `ssh lumi 'bash -lc "module list"'`, and in batch
  scripts source the init explicitly.
- **Compute nodes have no internet.** Download weights and datasets on the login node,
  then run with `HF_HUB_OFFLINE=1` so a lookup fails loudly rather than hanging until the
  job times out.
- **CUDA-only wheels do not work.** Check for a ROCm build before planning around a
  library; `bitsandbytes`, `flash-attn` and friends need ROCm-specific versions.
- **Home is 20 GB and everything defaults into it.** The HF cache especially.
- **Do not mix up project numbers.** LUMI projects are nine digits starting `46`; Roihu
  and Puhti are seven starting `2`. A LUMI number will not authenticate on Roihu.

## Choosing LUMI vs Roihu vs Rahti vs Aitta

| Need | Use |
|---|---|
| Large-scale training, many GPU-hours, an AMD-compatible stack | **LUMI** |
| Smaller GPU jobs, CUDA-only code, NVIDIA GH200 | **Roihu** (`csc-roihu`) |
| An always-on model endpoint an app can call | **Aitta** (`csc-rahti`) |
| A web app, API or database that must stay up | **Rahti** (`csc-rahti`) |

The deciding questions are lifetime and vendor. LUMI and Roihu both end when the job
ends, and the choice between them is CUDA versus ROCm plus how many GPU-hours the work
needs. Neither hosts a service.
