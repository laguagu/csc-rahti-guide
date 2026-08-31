# Open OnDemand — the web interface

<https://www.roihu.csc.fi/pun/sys/dashboard/>. Logs in with the CSC account over
HTTPS, so it works where SSH does not (blocked port 22, no signed certificate yet).

## What is there

**Shells** — a real terminal in a browser tab:

- `/pun/sys/dashboard/apps/show/ood-shell-gpu` → `roihu-gpu.csc.fi` (aarch64)
- `/pun/sys/dashboard/apps/show/ood-shell-cpu` → `roihu-cpu.csc.fi` (x86)
- "Compute node shell" submits a small job and drops you on a compute node

**Interactive apps** — Jupyter, VS Code, RStudio, Desktop, MATLAB, Marimo,
TensorBoard, MLflow, Accelerated Visualization. Each one is a Slurm job under the
hood: you pick partition, GPUs and walltime in a form, and OOD proxies the app's
port back through HTTPS. This is the only way to reach a port on a compute node
without an SSH tunnel, and it is why "run the notebook on a GPU node" is usually
easier than serving a model.

**Utilities** — Home Directory file browser (upload/download), Disk quotas, Project
view, Active Jobs, Cloud storage configuration.

Apps are lazily initialised: the first visit to some URLs shows "App has not been
initialized" with an *Initialize App* button, which restarts the per-user NGINX and
drops active websocket connections. Save work in other OOD tabs before clicking it.

## Driving the web terminal as an agent

The terminal is a canvas, not a DOM — output can only be read by screenshotting.
That makes naive "one command, one screenshot" loops expensive and error-prone.
What works:

- **`clear;` before every command.** Output then starts at the top of a blank screen
  and one screenshot captures all of it, instead of hunting through scrollback.
- **Compose aggressively.** Chain the whole check into one line — `sacct ...; tail
  -5 out; du -sh $HF_HOME` — rather than three round trips.
- **Write files with a quoted heredoc**, `cat > job.sh <<'EOF' ... EOF`. The quoted
  delimiter stops the shell expanding `$USER` and backticks while typing. Verify
  afterwards: `wc -l job.sh` and, for Python, `python -c "import ast;
  ast.parse(open('run.py').read());print('syntax OK')"` — a truncated or mangled
  heredoc is the most likely failure and is invisible otherwise.
- **Never run anything long in the foreground.** A download or a `tail -f` blocks the
  tab. Use `nohup … > log 2>&1 &`, then poll the log.
- **Poll with `squeue --me` plus `tail`,** not by waiting blindly. `gputest` jobs
  usually start in seconds, so a 30–60 s wait is enough before the first check.
- **Grep the output file for the few lines that matter** rather than screenshotting
  a 500-line vLLM startup log.

If the environment blocks a browser action, say so and hand the command to the
user rather than looking for a way around it — these are real compute jobs on a
billed account.

## Files in and out

The Home Directory app uploads and downloads files through the browser, which is
the practical route when SSH (and therefore `scp`/`rsync`) is unavailable. It is
fine for scripts and results, painful for datasets — for those use Allas
(`a3s.fi`, covered in the `csc-rahti` skill) or fix SSH.
