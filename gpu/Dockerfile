# syntax=docker/dockerfile:1
# MESA JupyterLab — NVIDIA GPU variant. Adds CUDA 12.6 PyTorch (+ Hugging Face,
# Lightning, CuPy, TorchGeo), NVDashboard, Jupyter AI, Ollama and GPU tooling on
# top of the published CPU image; see ../README.md "GPU variant".
# Build context is gpu/ (make build-gpu). Nothing here edits the CPU image.
ARG BASE_IMAGE=harbor.cyverse.org/vice/mesa-jupyterlab:latest

# cuda-probe: tiny glibc-only helper used by mesa-gpu-env.sh and mesa-gpu-check
FROM ubuntu:24.04 AS cuda-probe
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
COPY --chmod=644 common/cuda-probe.c /src/cuda-probe.c
RUN gcc -O2 -Wall -o /cuda-probe /src/cuda-probe.c -ldl

FROM ${BASE_IMAGE}

LABEL org.label-schema.name="CyVerse VICE MESA JupyterLab (NVIDIA GPU)" \
      org.label-schema.description="MESA JupyterLab workbench with NVIDIA GPU support: CUDA 12.6 PyTorch, CuPy, Hugging Face, NVDashboard, Jupyter AI and a local Ollama LLM server for CyVerse VICE" \
      org.label-schema.url="https://cyverse.org" \
      org.label-schema.vcs-url="https://github.com/idss-mesa/jupyterlab" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.schema-version="1.0.0"

# The jupyter base already runs RUN under bash -o pipefail; restated so the
# pipes below (zstd | tar, the driver guard) behave the same if the base changes.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Each version ARG is declared just above the first RUN that uses it: an ARG is
# part of the cache key of every later RUN, so an Ollama or CUDA compat bump
# declared up here would re-run (and re-push) the 6.6 GB PyTorch and 1 GB ML
# layers. For the same reason PyTorch comes first, then CUDA compat and Ollama.

# Python layers go into the conda base env as jovyan (it owns /opt/conda), so the
# default "Python 3" kernel, terminals, VS Code (and any R session that installs
# reticulate) all get the GPU with no extra kernel to pick.
USER jovyan

# PyTorch, CUDA 12.6 build: runs natively on R535+ drivers (T4/A16/A100). Never
# plain `pip install torch` (PyPI's build is CUDA 13 and needs an R580+ driver).
# The +cuXXX local version follows TORCH_INDEX_URL, so moving to .../cu130 once
# every node is R580+ is a build-arg change. The whole base env is frozen as a
# constraints file: pip may add packages but can never change one the CPU image
# ships (numpy 2.5, pandas 3, numba 0.67, ...); a conflict fails the build.
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu126
ARG TORCH_VERSION=2.14.0
ARG TORCHVISION_VERSION=0.29.0
RUN cuda_tag="${TORCH_INDEX_URL##*/}" && \
    pip list --format=freeze > /tmp/base-env.txt && \
    pip install --no-cache-dir -c /tmp/base-env.txt --index-url "${TORCH_INDEX_URL}" \
        "torch==${TORCH_VERSION}+${cuda_tag}" "torchvision==${TORCHVISION_VERSION}+${cuda_tag}" && \
    rm -f /tmp/base-env.txt

# ML / LLM libraries and the JupyterLab GPU extensions, resolved against the
# frozen env, which now also pins torch/torchvision +cu126 (nothing can swap
# torch for the PyPI CUDA 13 build). Floors = versions verified on this base, so
# a future base cannot make pip backtrack to ancient releases silently.
# Left out on purpose (each would change a base package; see README "GPU variant"):
#   datasets                  needs fsspec<=2026.6.0 (base: 2026.7.0)
#   jupyter-ai[jupyternaut]   its litellm needs importlib-metadata<9 (base: 9.0.1)
#   numba-cuda, RAPIDS        need numpy<2.5 / pandas<3.0.4
RUN pip list --format=freeze > /tmp/base-env.txt && \
    pip install --no-cache-dir -c /tmp/base-env.txt --extra-index-url "${TORCH_INDEX_URL}" \
        "transformers>=5.17" "accelerate>=1.15" "peft>=0.21" "sentence-transformers>=6.1" \
        "safetensors>=0.8" "bitsandbytes>=0.50" "lightning>=2.6.6" "timm>=1.0.30" \
        "torchmetrics>=1.9" "torchgeo>=0.10" "cupy-cuda12x>=14.2" \
        "nvitop>=1.7" "nvidia-ml-py>=13" "huggingface_hub>=1.33" "ollama>=0.6" \
        "jupyterlab-nvdashboard==0.15.0" "jupyter-ai==3.2.0" && \
    pip check && \
    rm -f /tmp/base-env.txt

USER root

# One pin for the CUDA forward-compat driver: the apt package
# (cuda-compat-13-4) and its versioned path (MESA_CUDA_COMPAT_DIR, read by
# /etc/profile.d/mesa-gpu-env.sh) both derive from it, so a bump cannot leave
# the env pointing at a directory that does not exist.
ARG CUDA_COMPAT_VERSION=13.4
ENV MESA_CUDA_COMPAT_DIR=/usr/local/cuda-${CUDA_COMPAT_VERSION}/compat

# NVIDIA apt repo (CUDA forward-compat driver only — never driver packages), nvtop, zstd.
# cuda-compat stays at its versioned path ${MESA_CUDA_COMPAT_DIR} and is put on
# LD_LIBRARY_PATH per session only when the host driver predates R580
# (/etc/profile.d/mesa-gpu-env.sh). The NVIDIA runtime injects the host driver's
# libcuda/NVML; baking driver userspace would shadow it and break nvidia-smi.
# The guard greps to /dev/null, not grep -q: under pipefail an early grep -q
# exit SIGPIPEs dpkg and the if would silently pass.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl zstd nvtop && \
    curl -fsSL -o /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /tmp/cuda-keyring.deb && rm -f /tmp/cuda-keyring.deb && \
    apt-get update && apt-get install -y --no-install-recommends "cuda-compat-$(printf '%s' "${CUDA_COMPAT_VERSION}" | tr . -)" && \
    test -e "${MESA_CUDA_COMPAT_DIR}/libcuda.so.1" && \
    test ! -e /usr/local/cuda/compat && \
    if dpkg -l | grep -E '^ii +(nvidia-driver|nvidia-dkms|nvidia-utils|nvidia-compute-utils|libnvidia-(compute|gl|decode|encode|extra|fbc1|cfg1|common)|cuda-drivers)' >/dev/null; then \
        echo 'NVIDIA driver userspace must not be baked into the image' >&2; exit 1; fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ollama (pinned, sha256-checked; never install.sh, which bakes cuda-drivers into
# the image). The real binary is ollama.bin; /usr/local/bin/ollama is the wrapper.
ARG OLLAMA_VERSION=0.34.4
ARG OLLAMA_SHA256=c238986e61d40c0cc5f4a9b9e40b9eea104350b77efa34741fc134e105cb9533
RUN curl -fsSL -o /tmp/ollama.tar.zst "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst" && \
    echo "${OLLAMA_SHA256}  /tmp/ollama.tar.zst" | sha256sum -c - && \
    zstd -dc /tmp/ollama.tar.zst | tar -xf - -C /usr/local && rm -f /tmp/ollama.tar.zst && \
    mv /usr/local/bin/ollama /usr/local/bin/ollama.bin

# ---------------------------------------------------------------------------
# Scripts / config last, AFTER the heavy layers, so editing them rebuilds in
# seconds. common/ is shared verbatim by the five idss-mesa GPU images.
# Every COPY sets its mode (644 sourced/config, 755 executables) so a build
# from a checkout with a restrictive umask still gives jovyan working files.
# ---------------------------------------------------------------------------
COPY --from=cuda-probe --chmod=755 /cuda-probe /usr/local/bin/cuda-probe
COPY --chmod=644 common/mesa-gpu-env.sh /etc/profile.d/mesa-gpu-env.sh
COPY --chmod=755 common/ollama-wrapper.sh /usr/local/bin/ollama
COPY --chmod=755 common/mesa-ollama-start.sh /usr/local/bin/mesa-ollama-start
COPY --chmod=755 common/mesa-gpu-entrypoint.sh /usr/local/bin/mesa-gpu-entrypoint
COPY --chmod=755 common/mesa-gpu-check.sh /usr/local/bin/mesa-gpu-check
COPY --chmod=755 common/ollama-setup.sh /usr/local/bin/ollama-setup
COPY --chmod=755 common/motd-gpu.sh /etc/mesa/motd-gpu.sh
# JupyterLab-specific mesa-gpu-check section (NVDashboard, Jupyter AI MCP port)
COPY --chmod=644 gpu-check.d/50-jupyterlab.sh /etc/mesa/gpu-check.d/50-jupyterlab.sh
# apt refuses NVIDIA driver packages in a session too (sudo apt install
# cuda-drivers would shadow the injected host driver); see the file's header.
COPY --chmod=644 common/apt-no-nvidia-driver.pref /etc/apt/preferences.d/mesa-no-nvidia-driver

# Landing screen: the CPU splash (run by jovyan's .bashrc in interactive shells)
# becomes motd-base; /etc/motd now runs it, then the GPU panel.
RUN mv /etc/motd /etc/mesa/motd-base && \
    printf '#!/bin/bash\n/etc/mesa/motd-base\n/etc/mesa/motd-gpu.sh\n' > /etc/motd && chmod 755 /etc/motd

# JupyterLab terminals inherit the forward-compat env from the entrypoint;
# docker/kubectl exec shells do not, so interactive bash sources it too
# (a no-op when MESA_GPU_ENV_DONE is inherited).
RUN printf '\n# MESA GPU: CUDA forward-compat env for shells not started by the IDE (docker/kubectl exec)\nif [ -r /etc/profile.d/mesa-gpu-env.sh ]; then . /etc/profile.d/mesa-gpu-env.sh; fi\n' >> /etc/bash.bashrc

# NVIDIA_VISIBLE_DEVICES is deliberately NOT set: the device plugin / docker --gpus
# sets it, and baking "all" could expose every GPU on a node to a pod that did not
# request one. Ollama: one 16 GB GPU would get a 4096-token default context, too
# small for agents, hence 32768 with a q8_0 KV cache and one model at a time.
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    MESA_TORCH_PYTHON=/opt/conda/bin/python \
    OLLAMA_HOST=127.0.0.1:11434 OLLAMA_CONTEXT_LENGTH=32768 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
    OLLAMA_KEEP_ALIVE=5m OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 CUDA_CACHE_MAXSIZE=1073741824

USER jovyan

# Register the local Ollama server with OpenCode (an 'ollama' provider next to
# 'aiverde') and Codex (oss_provider = "ollama"). Run as jovyan so the configs
# stay owned by 1000:100 (and jovyan can delete the script from sticky /tmp).
COPY --chown=1000:100 --chmod=644 common/patch-agent-configs.py /tmp/patch-agent-configs.py
RUN python3 /tmp/patch-agent-configs.py \
        --opencode /home/jovyan/.config/opencode/opencode.json \
        --codex /home/jovyan/.codex/config.toml && \
    rm -f /tmp/patch-agent-configs.py

WORKDIR /home/jovyan/data-store

# mesa-gpu-entrypoint (CUDA forward-compat env, background Ollama) then the CPU
# image's own startup script, unchanged. The CPU image has no CMD.
ENTRYPOINT ["/usr/local/bin/mesa-gpu-entrypoint", "bash", "/bin/entry.sh"]
