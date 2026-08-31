# LLM inference on Roihu

## Contents
- [Getting the weights there](#getting-the-weights-there)
- [Offline batch inference](#offline-batch-inference)
- [OpenAI-compatible server](#openai-compatible-server)
- [Containers](#containers)
- [Verifying a run actually used the GPU](#verifying-a-run-actually-used-the-gpu)

Two modes. Pick by whether something outside the job needs to talk to the model.

- **Offline batch** — one Python process loads the model, generates for a list of
  prompts, exits. This is the mode a supercomputer is built for: no idle GPU time.
- **OpenAI-compatible server** — `vllm serve` holds the model in memory and answers
  HTTP. Necessary when an existing program speaks the OpenAI API, but it bills for
  every wall-clock second and is only reachable from inside CSC.

## Getting the weights there

Compute nodes have no internet; login nodes do. So download first, run offline:

```bash
export HF_HOME=/scratch/project_XXXXXXX/$USER/hf     # never the default ~/.cache
module load python-vllm
hf download Qwen/Qwen2.5-1.5B-Instruct               # `huggingface-cli` also exists
```

For anything above a few GB run it detached and poll, so a dropped web terminal
doesn't kill the download:

```bash
nohup hf download <repo> > dl.log 2>&1 &
tail -2 dl.log; du -sh $HF_HOME
```

Gated models (Llama, some Mistral) need `HF_TOKEN` exported before the download.
Set `HF_HUB_OFFLINE=1` in the job script so a compute-node lookup fails fast with a
clear error instead of hanging on a timeout.

## Offline batch inference

```python
from vllm import LLM, SamplingParams

llm = LLM(model="Qwen/Qwen2.5-1.5B-Instruct",
          max_model_len=2048,
          gpu_memory_utilization=0.6)      # raise toward 0.9 for larger models

msgs = [[{"role": "user", "content": p}] for p in prompts]
outs = llm.chat(msgs, SamplingParams(temperature=0.7, max_tokens=256))
for o in outs:
    print(o.outputs[0].text.strip())
```

Pass the whole prompt list in one `chat()` call — vLLM batches them continuously,
which is where its throughput comes from. Load time (~40 s) dominates a small run,
so amortise it over as many prompts as possible.

Multi-GPU on one node: `LLM(..., tensor_parallel_size=4)` plus
`--gres=gpu:gh200:4`. A 96 GiB GH200 holds a 20B model in bf16 comfortably; 70B
needs the full 4-GPU node or quantisation.

## OpenAI-compatible server

```bash
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=02:00:00
module load python-vllm
export HF_HOME=/scratch/project_XXXXXXX/$USER/hf HF_HUB_OFFLINE=1
echo "SERVER_NODE=$(hostname)"
vllm serve <model> --port 8000 --max-model-len 4096
```

`squeue --me` shows which node it landed on. The server is then at
`http://<node>:8000/v1` — an OpenAI base URL with any key value, since vLLM does
not check it unless `--api-key` is set.

Reaching it depends on where the calling code runs:

| Caller | How |
|---|---|
| Another process in the same job | `http://localhost:8000/v1` |
| A login node, or an OOD Jupyter/VS Code session on a compute node | `http://<node>:8000/v1` directly — same network |
| A laptop | SSH tunnel: `ssh -L 8000:<node>:8000 <user>@roihu-gpu.csc.fi`, then `http://localhost:8000/v1`. Needs working SSH and a valid 24 h MyCSC certificate |

A tunnel is genuinely convenient for a developer iterating on their own laptop — the
model behaves exactly like any OpenAI endpoint. What it cannot be is *shared*: there
is no public URL, no route, and the job dies at its walltime (36 h maximum). So
"let me point my local script at a real model for the afternoon" is a good fit;
"our app calls this endpoint" is not — that is Aitta or a hosted provider.

Cost check before suggesting a server: 200 BU/GPU-hour, billed on wall time whether
or not requests arrive. A two-hour session on one GPU is 400 BU. Keep `--time` tight
and `scancel` the job the moment the experiment ends — an abandoned server silently
drains the project's whole GPU allocation overnight.

## Containers

CSC publishes Roihu-specific images in the public Satama project
`r_installation_aida` — including vLLM, PyTorch, TensorFlow and JAX builds. Use one
when the module's version is wrong for the model, or to pin an environment. Run it with
Apptainer/`tykky` rather than pip-installing into a venv — aarch64 wheels are patchy.

```bash
# Newest vLLM tag as of 2026-08: 0.19.1_cuda12.9_roihu
satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu

# Tags move — list the current ones without logging in (the project is public):
curl -s "https://satama.csc.fi/api/v2.0/projects/r_installation_aida/repositories/vllm/artifacts?with_tag=true"   | jq -r '.[].tags[].name'
```

The `csc-rahti` skill covers Satama authentication for private projects.

## Verifying a run actually used the GPU

`seff <jobid>` reports CPU and memory efficiency but **says nothing about the GPU**,
so it cannot answer this question. Put the check in the job script itself:

```bash
nvidia-smi --query-gpu=name,memory.total --format=csv   # before the workload
```

then `grep -E 'NVIDIA|GH200' job-*.out`. In vLLM's log the giveaway is the platform
line and the KV-cache size; a CPU fallback is dramatically slower and reports no
GPU blocks.

A silent CPU fallback is the most common way a "working" job wastes an hour of
billing, so check the first run of any new script. Low CPU efficiency in `seff`
(single digits) is normal and expected for a GPU job — the CPU is just feeding the
accelerator, not a sign anything is wrong.
