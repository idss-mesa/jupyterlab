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
`:latest` to Harbor ([`harbor.yml`](.github/workflows/harbor.yml)). hadolint
lints the Dockerfile on PRs and trivy scans the published image weekly,
reporting to the repo Security tab ([`security.yml`](.github/workflows/security.yml)).

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
Makefile                        local build/push/run
.github/workflows/              harbor.yml (build+push), security.yml (hadolint + trivy)
```

## Resources

- [CyVerse VICE apps](https://learning.cyverse.org/vice/) · [GoCommands](https://learning.cyverse.org/ds/gocommands/) · [AI Verde](https://aiverde-docs.cyverse.ai/) · [jupyter/docker-stacks](https://github.com/jupyter/docker-stacks)
- MESA org: <https://github.com/idss-mesa>
