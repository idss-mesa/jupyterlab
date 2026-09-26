# MESA JupyterLab — CyVerse VICE Datascience Workbench

A [JupyterLab](https://jupyterlab.readthedocs.io/) data-science environment for the **MESA** project, built to run as a [CyVerse Discovery Environment (VICE)](https://cyverse.org/discovery-environment) app. It layers the MESA agentic stack — four AI coding-agent CLIs wired to CyVerse [AI Verde](https://aiverde-docs.cyverse.ai/) LLMs, MESA [MCP](https://modelcontextprotocol.io/) servers, and CyVerse Data Store tooling — on top of the [Project Jupyter datascience-notebook](https://quay.io/repository/jupyter/datascience-notebook) (Python + R + Julia), with RStudio Server, Shiny, and VS Code reachable from the JupyterLab Launcher.

![harbor](https://github.com/idss-mesa/jupyterlab/actions/workflows/harbor.yml/badge.svg) ![platforms](https://img.shields.io/badge/platforms-linux%2Famd64-blue) ![registry](https://img.shields.io/badge/registry-harbor.cyverse.org%2Fvice%2Fmesa--jupyterlab-0a7bbb)

## What's inside

| Category | Tools |
| --- | --- |
| **IDEs** | JupyterLab (port 8888), RStudio Server (`/rstudio` Launcher card), Shiny Server, VS Code (code-server) — via [jupyter-server-proxy](https://github.com/jupyterhub/jupyter-server-proxy) |
| **AI agent CLIs** | Claude Code (`claude`), OpenAI Codex (`codex`), OpenCode (`opencode`), Antigravity (`agy`), Claude Code Router (`ccr`) |
| **MCP servers** | `irods` (CyVerse Data Store), `mesa` ([mesa-mcp](https://github.com/idss-mesa/mesa-mcp) + [mesa-ducklake](https://github.com/idss-mesa/mesa-ducklake)), `formation` ([formation-mcp](https://github.com/idss-mesa/formation-mcp), CyVerse DE), `filesystem` — pre-registered for every agent CLI |
| **AI Verde** | `aiverde-setup` helper wires OpenCode + Claude Code (via `ccr`) to `https://llm-api.cyverse.ai` |
| **CyVerse data** | GoCommands (`gocmd`), iRODS config, `s3fs`/OSN mounts (`osn-mount.sh`), AWS CLI |
| **Dev** | GitHub CLI (`gh`), Git Credential Manager, Go 1.25, Node.js 22 |
| **Science** | Python 3.13 + R + Julia datascience stack (NumPy/SciPy/pandas, tidyverse, …), MiniConda/Mamba |

Base image: `quay.io/jupyter/datascience-notebook:latest` (Ubuntu 24.04, user `jovyan`). JupyterLab on port **8888**; working dir `/home/jovyan/data-store`.

## Run it

```bash
docker run --rm -p 8888:8888 -e IPLANT_USER=$USER harbor.cyverse.org/vice/mesa-jupyterlab:latest
```

Then open <http://localhost:8888/lab> (no token — VICE's ingress handles auth) and RStudio at <http://localhost:8888/rstudio/>. `IPLANT_USER` is injected by VICE; locally, pass your CyVerse username so `entry.sh` can write the iRODS config.

On VICE, the app runs in the Discovery Environment with your Data Store mounted under `~/data-store`.

## DE tool settings

These live in the Discovery Environment, not in this repo, and must match the image. Change them only together with the Dockerfile.

| Setting | Value |
| --- | --- |
| DE app | **MESA JupyterLab** (`cc56cf46-86f7-11f1-9793-008cfa5ae3e1`) |
| DE tool | `mesa-jupyterlab` (`bcf2ada4-86f7-11f1-9195-008cfa5ae3e1`) |
| Image | `harbor.cyverse.org/vice/mesa-jupyterlab:latest` |
| Type | interactive |
| Container port | **8888** |
| Working directory | **should be** `/home/jovyan/data-store` (currently unset in the DE; needs a DE admin to fix) (the Data Store CSI mount point; must match the Dockerfile `WORKDIR`) |
| UID | 1000 |
| Entrypoint override | none (the image's own startup script does the MESA per-user setup) |
| Max CPU | default (upstream `vice/jupyter/datascience`: 16 cores) |
| Memory limit | 16 GiB (upstream 32 GiB) |

JupyterLab listens on 8888, tokenless; VICE's ingress handles auth.

## Sign in to CyVerse

```bash
cyverse-login          # your CyVerse username + password
```

Writes the standard iRODS credential files (`~/.irods/`) so GoCommands, the `mesa`
and `formation` MCP servers, and the agents all act as **you** — with write/own
access to your home and shared collections. Without it you get anonymous, public
read-only access.

For the hosted CyVerse Data Store MCP, **Claude Code** registers **two** servers:
`irods` points at the anonymous
[public endpoint](https://mcp-public.cyverse.ai/mcp) (public data under
`/iplant/home/shared`, no sign-in) and works out of the box; `irods-auth` points
at the [authenticated endpoint](https://mcp.cyverse.ai/mcp), which uses CyVerse's
pre-registered OAuth client (`mcp-client`). Sign in to `irods-auth` once per
session to reach your private home collection:

```bash
claude mcp login irods-auth --no-browser   # opens a kc.cyverse.org URL; paste the redirect back
```

For private-collection access under OpenCode, Codex, and Antigravity, rely on
`cyverse-login`: the bundled **local** `mesa`/iRODS MCP servers and `gocmd` read
your `~/.irods` credentials directly (no OAuth) and act as you. Restart an agent
after logging in so its MCP servers pick up the credentials.

## Connect AI Verde LLMs

Each user authenticates with their **own** institutional identity — no API key is baked into the image. Inside a JupyterLab terminal:

```bash
aiverde-setup          # paste your key from chat.cyverse.ai → Course → API Key
```

It validates the key against `/v1/models`, lists your models, and writes `~/.config/aiverde/env` (chmod 600). Then:

- **OpenCode** — uses the `aiverde` provider directly.
- **Claude Code** — uses `ccr` for non-Anthropic models (`ccr code`), or the native `ANTHROPIC_BASE_URL` env path if your course serves Anthropic models.
- **Codex** — *not* wired to AI Verde: Codex dropped Chat Completions support and AI Verde does not serve the Responses API. It runs on its own OpenAI auth.

## GPU variant (`:gpu`)

`harbor.cyverse.org/vice/mesa-jupyterlab:gpu` is the same workbench with an NVIDIA GPU. [`gpu/Dockerfile`](gpu/Dockerfile) only adds layers on top of `:latest` (build context `gpu/`). Everything above still applies.

| Adds | Details |
| --- | --- |
| **PyTorch (CUDA 12.6)** | `torch 2.14.0+cu126`, `torchvision 0.29.0+cu126` in the conda base env, so the default **Python 3** kernel, terminals and anything else using `/opt/conda/bin/python` see the GPU |
| **ML libraries** | transformers, accelerate, peft, sentence-transformers, safetensors, bitsandbytes, Lightning, timm, torchmetrics, TorchGeo, CuPy (`cupy-cuda12x`), `huggingface_hub` (`hf`), `ollama` Python client |
| **JupyterLab** | [NVDashboard](https://github.com/rapidsai/jupyterlab-nvdashboard) 0.15 (**GPU Dashboards** in the left sidebar); [Jupyter AI](https://github.com/jupyterlab/jupyter-ai) 3.2 chat, which picks up the installed OpenCode CLI as the `@OpenCode` persona and serves notebook tools to agents over MCP on `localhost:3001` (loopback only) |
| **Local LLMs** | [Ollama](https://ollama.com) 0.34.4, started in the background on `127.0.0.1:11434` (loopback only, no models baked in); `ollama-setup`; OpenCode and Codex pre-wired to it |
| **GPU tools** | `nvidia-smi` (from the host driver), `nvtop`, `nvitop`, `mesa-gpu-check`, a GPU panel on the terminal landing screen, NVIDIA CUDA 13.4 forward-compat libraries |

The GPU image is about **22.8 GB** uncompressed (CPU `:latest`: 12.4 GB). Most of the difference is PyTorch plus its CUDA wheels (6.6 GB), Ollama (2.2 GB), the ML libraries (1.0 GB) and the CUDA compat driver + nvtop (0.5 GB).

**Left out on purpose.** Each of these would change a package that the CPU image ships. The build freezes the CPU env as pip constraints, so a conflict fails the build instead of silently downgrading numpy/pandas/numba:

| Package | Why |
| --- | --- |
| `datasets` | needs `fsspec<=2026.6.0` (base: 2026.7.0). Install it yourself with `pip install datasets`, which downgrades fsspec for that analysis only |
| `jupyter-ai[jupyternaut]` (Jupyternaut persona) | two downgrades: its LiteLLM needs `importlib-metadata<9` (base: 9.0.1), and its `langgraph-sdk` needs `websockets<17` (pip would take websockets 17.1 down to 16.1.1) |
| numba-cuda, RAPIDS | need `numpy<2.5` / `pandas<3.0.4` |

Once LiteLLM accepts importlib-metadata 9 and langgraph-sdk accepts websockets 17, add `[jupyternaut]` to the `jupyter-ai` line in `gpu/Dockerfile`. Then point Jupyternaut at the local Ollama with a server config file. These are the `JupyternautExtension` traitlets in jupyter-ai-jupyternaut 0.1.0; this config has not been tested in this image:
`{"JupyternautExtension": {"initial_language_model": "ollama_chat/qwen3.5:9b", "model_parameters": {"ollama_chat/qwen3.5:9b": {"api_base": "http://127.0.0.1:11434"}}}}`.

### Run it locally

```bash
docker run --rm --gpus all -p 127.0.0.1:8888:8888 -e IPLANT_USER=$USER harbor.cyverse.org/vice/mesa-jupyterlab:gpu   # or: make run-gpu
```

Then open <http://localhost:8888/lab>. The port is bound to loopback because JupyterLab has no token or password outside VICE (VICE's cas-proxy does the auth) and `jovyan` has passwordless `sudo`; on a remote GPU server, tunnel to it (`ssh -L 8888:127.0.0.1:8888 <gpu-host>`) instead of publishing it on all interfaces. It also starts without a GPU: everything runs on the CPU, and `mesa-gpu-check` says why there is no GPU.

### Local LLMs (Ollama)

```bash
ollama-setup                                   # pulls qwen3.5:9b (first time only) and prints the commands below
ollama launch claude --model qwen3.5:9b        # Claude Code on the local model
codex --oss --local-provider ollama -m qwen3.5:9b
opencode -m ollama/qwen3.5:9b
```

No API key is needed and nothing leaves the pod. Models that fit one 16 GB GPU (A16/T4): `qwen3.5:9b` (default: coding agents and tool calling), `gpt-oss:20b`, `gemma4:12b`, `qwen3:4b` (`ollama-setup --help`). Models live in `~/.ollama/models`, which is container-local and gone when the analysis ends. Keep them out of `~/data-store`. From Python, use `import ollama` or the OpenAI-compatible API at `http://127.0.0.1:11434/v1`. The context window is 32k tokens, with one model loaded at a time. `ollama stop <model>` frees its GPU memory for PyTorch.

**Jupyter AI chat on the local model.** `@OpenCode` starts on OpenCode's default model, AI Verde's `aiverde/js2/gpt-oss-120b`. That model reads its key from `LLM_API_KEY`, which `aiverde-setup` sets only for new terminals, not for the already-running Jupyter server that starts OpenCode, so in the chat it fails with an authentication error. The local model needs no key:

1. Run `ollama-setup` in a terminal.
2. In the chat, choose `ollama/qwen3.5:9b` in `@OpenCode`'s model picker. The choice is saved with that `.chat` file.

To make the local model the default instead, set `"model": "ollama/qwen3.5:9b"` in `~/.config/opencode/opencode.json`. Jupyter AI keeps one OpenCode process running, so this edit reaches the chat only after the Jupyter server restarts; terminal `opencode` picks it up right away. Expect a slow first reply, because OpenCode sends a long agent prompt: over ACP, the protocol Jupyter AI uses, a one-word reply took 174 s with the model not yet loaded and 78 s with it loaded, on a T4.

### Check the GPU

```bash
mesa-gpu-check            # driver, libcuda, forward-compat, PyTorch matmul + cuDNN, Ollama, NVDashboard
mesa-gpu-check --ollama   # also runs qwen3:0.6b (~0.5 GB) and asserts it is 100% on the GPU
```

### CUDA and driver compatibility

- **Never bakes NVIDIA driver libraries.** The NVIDIA container runtime injects the host driver (`nvidia-smi`, `libcuda`). The build fails if a driver package sneaks in, and an apt pin (`/etc/apt/preferences.d/mesa-no-nvidia-driver`) stops `sudo apt install cuda-drivers` / `nvidia-driver-*` / `libnvidia-*` from shadowing the host driver in a session; CUDA toolkit packages (`cuda-toolkit-12-x`) stay installable. To install driver packages on purpose, `sudo rm` that file first.
- **PyTorch cu126** runs natively on any driver ≥ R525, which covers the DE's A16 nodes and older T4/A100 hosts. It never uses PyPI's default `torch`, which is the CUDA 13 build and needs R580+.
- **Ollama 0.34.4** needs R550+ for its CUDA 12 runner and R580+ for CUDA 13; other CUDA 13 software needs R580+. On older data-center drivers (e.g. R535), `/etc/profile.d/mesa-gpu-env.sh` enables NVIDIA's CUDA 13.4 forward-compat driver (`/usr/local/cuda-13.4/compat`) per session, including `docker exec` / `kubectl exec` bash shells (via `/etc/bash.bashrc`). It does so only when the host's CUDA API is < 13 and the compat driver initialises. R580+ hosts and GPUs without forward-compat support keep the host driver.
- To opt out, set `MESA_DISABLE_CUDA_COMPAT=1`. To skip the background Ollama server, set `MESA_OLLAMA_AUTOSTART=0`. Both are read once at container start, before `entry.sh` sources your `~/.env*` files, so setting them there has no effect: on VICE set them as environment variables on the DE app (locally, `docker run -e`).
- `NVIDIA_DRIVER_CAPABILITIES=compute,utility`. `NVIDIA_VISIBLE_DEVICES` is left to the DE / `docker --gpus`.
- Version pins are build args in `gpu/Dockerfile` (`TORCH_INDEX_URL`, `TORCH_VERSION`, `TORCHVISION_VERSION`, `OLLAMA_VERSION`/`OLLAMA_SHA256`, `CUDA_COMPAT_VERSION`). `CUDA_COMPAT_VERSION` (13.4) is the single compat pin: it sets both the `cuda-compat-13-4` package and `MESA_CUDA_COMPAT_DIR` (`/usr/local/cuda-13.4/compat`), and the build fails if that directory has no `libcuda.so.1`.
- To move to CUDA 13 builds once every node is R580+, build with `--build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130`.

### Build & publish from a GPU server

The GPU image is built on any x86-64 Docker host (`docker build` never uses the GPU), for example the A100 build server. It is then smoke-tested on that host's GPU and pushed:

```bash
git clone https://github.com/idss-mesa/jupyterlab && cd jupyterlab
docker login harbor.cyverse.org        # robot or user account with push rights to vice/
make pull-base build-gpu               # layer gpu/ on the published :latest
GPU=0 make test-gpu                    # T1-T8 smoke test on GPU 0 (GPU=all for every GPU)
make push-gpu                          # harbor.cyverse.org/vice/mesa-jupyterlab:gpu
```

- **Needs:** Docker with buildx, ~40 GB free disk and network access; `make test-gpu` also needs an NVIDIA GPU + [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/).
- **Test coverage:** `gpu/test-gpu.sh` checks the static image (host `libcuda`, no baked driver), a VICE-like start as uid 1000, `mesa-gpu-check --ollama`, CUDA code in the default `python3` kernel run through the live Jupyter server, NVDashboard, a start without a GPU, the apt pin (skipped, not failed, when `apt-get update` fetches no package lists), the forward-compat env in `docker exec bash -i` shells, and `nvitop` on the user's `PATH`.
- **Local CPU build:** `make build build-gpu` layers onto a fresh local CPU build instead of the published one.
- **CI alternative, no GPU test:** Actions → **harbor-gpu** → *Run workflow* ([`harbor-gpu.yml`](.github/workflows/harbor-gpu.yml), manual only). It builds on the digest of `:<base_tag>` and pushes `:<tag>` (defaults `latest` → `gpu`).

### DE tool settings (GPU)

The GPU app is a copy of the **MESA JupyterLab** app that points at a separate GPU tool. [`gpu/de-tool.json`](gpu/de-tool.json) is the Terrain admin tool-import body (`POST /terrain/admin/tools`). The GPU fields and the `/dev/shm` device are admin-only.

| Setting | Value |
| --- | --- |
| DE tool | `mesa-jupyterlab-gpu` (not created yet) |
| Image | `harbor.cyverse.org/vice/mesa-jupyterlab:gpu` |
| Container port / working dir / UID | **8888** / `/home/jovyan/data-store` / 1000. The working dir is set explicitly in `de-tool.json`; the CPU tool should match but is currently unset (see above) |
| GPUs | `min_gpus` = `max_gpus` = **1** (with `min_gpus` unset, a launch defaults to 0 GPUs) |
| GPU model | `gpu_models: ["NVIDIA-A16"]` |
| Shared memory | device `{"host_path": "/dev/shm", "container_path": "4Gi"}`: a 4 GiB RAM-backed `/dev/shm` for PyTorch DataLoader workers (counts against memory) |
| CPU / memory | 4–8 cores / 16–32 GiB |
| Network mode | **Required:** `bridge` (Terrain's default `none` gives an analysis that runs but never serves) |
| Skip /tmp mount | **Required:** `true` |
| VICE proxy | **Required:** `interactive_apps` = cas-proxy (`discoenv/cas-proxy`, `cas_url` `https://olson.cyverse.org/cas`, `cas_validate` `validate`); JupyterLab has no token, so cas-proxy is its only login |
| PIDs limit | `pids_limit` 1024 (GPU tool) |
| Entrypoint override | none (the image's `mesa-gpu-entrypoint` runs the CPU `entry.sh`) |

The CPU table above predates the network-mode, /tmp-mount and VICE-proxy rows, so it does not list them; set them on the GPU tool as shown (`de-tool.json` does).

## Build

The build context is `latest/`:

```bash
make build             # linux/amd64 → harbor.cyverse.org/vice/mesa-jupyterlab:latest
make run               # local smoke test on port 8888
make push
```

> **Building amd64 on Apple Silicon:** install the newer QEMU first or emulated
> package installs can fail with `cannot allocate memory`:
> ```bash
> docker run --privileged --rm tonistiigi/binfmt:latest --install amd64
> ```
> Prefer a native x86 host or CI for amd64. The Dockerfile copies all
> config/asset files *after* the heavy layers, so editing configs rebuilds in
> seconds. RStudio Server and Shiny Server ship amd64-only debs, so an arm64
> build succeeds but their Launcher cards won't work.

**CI:** pushes to `main` touching `latest/` — plus a weekly Sunday rebuild that
tracks the upstream base image and agent-CLI releases — build and push
`:latest` to Harbor ([`harbor.yml`](.github/workflows/harbor.yml)). `:gpu` is
not rebuilt automatically; see [GPU variant](#gpu-variant-gpu). hadolint lints
both Dockerfiles on PRs, and trivy scans the published `:latest` and `:gpu`
images weekly, reporting to the repo Security tab (until `:gpu` is first pushed,
its scan is skipped with a warning) ([`security.yml`](.github/workflows/security.yml)).

## Layout

```
latest/
  Dockerfile                    image definition (datascience-notebook + MESA agentic stack)
  entry.sh                      container entrypoint (iRODS config, dotfile import, S3 mounts, launches JupyterLab)
  jupyter_notebook_config.json  tokenless Jupyter server config (VICE ingress handles auth)
  rserver.conf                  RStudio Server config for jupyter-rsession-proxy
  01-custom                     MESA ANSI splash screen (/etc/motd)
  mesa-prompt.sh                shell prompt (/etc/profile.d)
  osn-mount.sh                  s3fs mounts for OSN/S3 buckets
  configs/                      agent-CLI configs + aiverde-setup / cyverse-login helpers
gpu/                            NVIDIA GPU variant (:gpu), layered on :latest
  Dockerfile                    CUDA forward-compat, Ollama, PyTorch cu126 + ML libs, NVDashboard, Jupyter AI
  common/                       GPU scripts shared verbatim by the five idss-mesa GPU images
                                (cuda-probe, mesa-gpu-env/-entrypoint/-check, ollama wrapper + setup, motd panel,
                                apt pin against NVIDIA driver packages)
  gpu-check.d/50-jupyterlab.sh  JupyterLab section of mesa-gpu-check (NVDashboard, Jupyter AI MCP port)
  test-gpu.sh                   GPU smoke test (make test-gpu)
  de-tool.json                  DE admin tool-import body for mesa-jupyterlab-gpu
Makefile                        local build/push/run (+ pull-base/build-gpu/test-gpu/push-gpu/run-gpu)
.github/workflows/              harbor.yml (build+push), harbor-gpu.yml (manual GPU build+push),
                                security.yml (hadolint + trivy, :latest and :gpu)
```

## Resources

- [CyVerse VICE apps](https://learning.cyverse.org/vice/) · [GoCommands](https://learning.cyverse.org/ds/gocommands/) · [AI Verde](https://aiverde-docs.cyverse.ai/) · [jupyter/docker-stacks](https://github.com/jupyter/docker-stacks)
- MESA org: <https://github.com/idss-mesa>
