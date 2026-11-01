# https://quay.io/repository/jupyter/datascience-notebook
FROM quay.io/jupyter/datascience-notebook:latest

LABEL org.label-schema.name="CyVerse VICE MESA JupyterLab" \
      org.label-schema.description="JupyterLab datascience workbench (Python/R/Julia) with RStudio, VS Code, agentic AI CLIs, and MESA MCP servers for CyVerse VICE" \
      org.label-schema.url="https://cyverse.org" \
      org.label-schema.vcs-url="https://github.com/idss-mesa/jupyterlab" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.schema-version="1.0.0"

USER root

# Target architecture set by buildx: amd64 or arm64
ARG TARGETARCH

# ---------------------------------------------------------------------------
# Pinned, checksum-verified downloads (2026-10 security review). Bump the
# version AND its hash together: a mismatch fails the build.
# ---------------------------------------------------------------------------
ARG GO_VERSION=1.27.3
ARG GO_SHA256_AMD64=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG GO_SHA256_ARM64=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49
ARG NODE_VERSION=22.23.4
ARG GOCMD_VERSION=v0.12.5
ARG GOCMD_SHA256_AMD64=af551f8cb2f3f5df63fb3a8eb1bf605c7f27e50ec10283a5375190239db9f57a
ARG GOCMD_SHA256_ARM64=2741c2a2c894ad156b63ea7ca16f5e7931662bd16e6331d4fbcfea904cc76143
ARG GCM_VERSION=2.7.3
ARG GCM_SHA256_X64=a5431e1b6f25aa8b424e747d880f86e74c739ad52e72c924a7b1a25d87ac7e72
ARG GCM_SHA256_ARM64=f5995901ef3a2ffc4442e4a9a92c8dfdc8f1df1affe8ef1d037b7ad3302b923b
ARG AWSCLI_VERSION=2.38.5
ARG AWSCLI_SHA256_X86_64=5def7d1b7e55d892f9a381bb2cb2081a685712464be0d36d5d706af0ac48d0d3
ARG AWSCLI_SHA256_AARCH64=07711a936e9d271045ab937d2c2c5390c25f419e4ba9e25adb9e996031e3f6be
ARG DUCKDB_SHA256_AMD64=c6507206baf7793c6013dbd82368469a45f20dc0e17a6f92f204602f652ed2bc
ARG DUCKDB_SHA256_ARM64=859e1875d2a9515fbb4bf8871061437a14af82320da68c753f094c4b776348fe
ARG CLAUDE_CODE_VERSION=2.1.310
ARG CODEX_VERSION=0.164.0
ARG CCR_VERSION=3.1.3
ARG MCP_FS_VERSION=2.0.1
ARG OPENCODE_VERSION=1.19.4
ARG CODE_SERVER_VERSION=4.143.1

# Add sudo to user
ARG LOCAL_USER=jovyan

# Create group 1000 if it doesn't exist (CyVerse VICE may assign this GID)
RUN getent group 1000 || groupadd -g 1000 jovyan-group && \
    usermod -a -G 1000 jovyan

RUN apt-get update && \
    apt-get install -y sudo && \
    echo "jovyan ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV TZ=America/Phoenix
ENV LANG=C.UTF-8
ENV LC_ALL="en_US.UTF-8"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# System dependencies: union of the mesa-cli base and the RStudio/Shiny build
# deps from cyverse-vice/jupyterlab-datascience. gettext provides envsubst
# (entry.sh). tini is NOT downloaded: the docker-stacks base ships it via apt.
RUN apt-get update && \
    apt-get install -y \
    lsb-release apt-transport-https ca-certificates curl wget bzip2 \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    libfreetype6-dev libssl-dev pkg-config psmisc libx11-dev gcc libclang-dev \
    gettext less software-properties-common apt-utils glances htop nano \
    gdebi-core gnupg2 git mercurial subversion tmux grep sed dpkg unzip xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# git-credential-manager (arch-aware), then RStudio Server + Shiny Server.
# Posit ships a single jammy deb as the official artifact for Ubuntu 22/24;
# there are no arm64 server debs, so both are amd64-only.
RUN GCM_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    GCM_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GCM_SHA256_ARM64" || echo "$GCM_SHA256_X64") && \
    curl -fsSL -o /tmp/gcm.deb "https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/gcm-linux-${GCM_ARCH}-${GCM_VERSION}.deb" && \
    echo "${GCM_SHA256}  /tmp/gcm.deb" | sha256sum -c - && \
    apt-get update && \
    apt-get install -y /tmp/gcm.deb && \
    if [ "$TARGETARCH" = "amd64" ]; then \
      wget -q https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2026.07.1-147-amd64.deb \
           -O /tmp/rstudio-server.deb && \
      wget -q https://download3.rstudio.org/ubuntu-20.04/x86_64/shiny-server-1.5.23.1030-amd64.deb \
           -O /tmp/shiny-server.deb && \
      gdebi -n /tmp/rstudio-server.deb && \
      gdebi -n /tmp/shiny-server.deb ; \
    fi && \
    rm -f /tmp/*.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Locales, terminal tools, s3fs
RUN apt-get update && \
    apt-get install -y locales lolcat fastfetch figlet w3m-img imagemagick s3fs fuse socat bubblewrap && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt update && apt install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Node.js from the official tarball, verified against nodejs.org's SHASUMS256.txt
# (replaces the unpinned `curl deb.nodesource.com/setup_22.x | bash`)
RUN NODE_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz$" | sed 's|  .*|  /tmp/node.tar.xz|' | sha256sum -c - && \
    tar -xJ -C /usr/local --strip-components=1 --exclude='*/CHANGELOG.md' --exclude='*/LICENSE' --exclude='*/README.md' -f /tmp/node.tar.xz && \
    rm -f /tmp/node.tar.xz && node --version && npm --version

# Install Go (pinned + sha256; Go >= 1.25.7 fixes CVE-2025-68121 in every binary built here)
RUN GO_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GO_SHA256_ARM64" || echo "$GO_SHA256_AMD64") && \
    curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" && \
    echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - && \
    tar -xz -C /usr/local -f /tmp/go.tgz && rm -f /tmp/go.tgz

# Build the iRODS MCP server (stdio MCP access to the CyVerse Data Store)
# https://github.com/idss-mesa/irods-mcp-server
# NOTE: the base image sets ENV HOME=/home/jovyan even for root, so keep the
# Go caches in /tmp or they land root-owned in jovyan's home
RUN git clone --depth 1 https://github.com/idss-mesa/irods-mcp-server /tmp/irods-mcp-server && \
    cd /tmp/irods-mcp-server && \
    CGO_ENABLED=0 GOPATH=/tmp/go GOCACHE=/tmp/go-cache /usr/local/go/bin/go build -o /usr/local/bin/irods-mcp-server ./cmd/main.go && \
    cd / && rm -rf /tmp/irods-mcp-server /tmp/go /tmp/go-cache

# Install GoCommands (pinned + sha256; it is NOT self-upgraded from ~/.bashrc any more)
# https://learning.cyverse.org/ds/gocommands/
RUN GOCMD_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GOCMD_SHA256_ARM64" || echo "$GOCMD_SHA256_AMD64") && \
    curl -fsSL -o /tmp/gocmd.tgz "https://github.com/cyverse/gocommands/releases/download/${GOCMD_VERSION}/gocmd-${GOCMD_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    echo "${GOCMD_SHA256}  /tmp/gocmd.tgz" | sha256sum -c - && \
    tar -xz -C /usr/local/bin -f /tmp/gocmd.tgz && rm -f /tmp/gocmd.tgz && gocmd --version

ENV PATH=${PATH}:/usr/games

# install AWS CLI (pinned + sha256)
RUN AWS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    AWS_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$AWSCLI_SHA256_AARCH64" || echo "$AWSCLI_SHA256_X86_64") && \
    curl -fsSL -o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" && \
    echo "${AWS_SHA256}  /tmp/awscliv2.zip" | sha256sum -c - && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Install mesa-mcp and mesa-ducklake (https://github.com/idss-mesa)
# into a dedicated venv, isolated from /opt/conda: users pip/mamba freely into
# the base env, and an upgrade of pydantic/duckdb/python-irodsclient there
# would silently break mesa-mcp. cyverse-login also hardcodes
# /opt/mesa/bin/python3 for iRODS password obfuscation.
# Pinned to release tags: DuckDB 2.0 (mesa-ducklake >= 0.2) writes catalogs
# DuckDB 1.x cannot open, and a changed ref also invalidates this layer's cache.
# The [ducklake] extra enforces mesa-mcp's mesa-ducklake>=0.2 floor; the
# assertion fails the build if the venv Python or DuckDB is too old.
ARG MESA_DUCKLAKE_REF=v0.2.0
ARG MESA_MCP_REF=v0.2.0
RUN /opt/conda/bin/python3 -m venv /opt/mesa && \
    /opt/mesa/bin/pip install --no-cache-dir \
      "mesa-ducklake @ git+https://github.com/idss-mesa/mesa-ducklake@${MESA_DUCKLAKE_REF}" \
      "mesa-mcp[ducklake] @ git+https://github.com/idss-mesa/mesa-mcp@${MESA_MCP_REF}" && \
    /opt/mesa/bin/python -c "import sys, duckdb; from importlib.metadata import version as v; assert sys.version_info >= (3, 11), sys.version; assert duckdb.__version__.startswith('2.'), duckdb.__version__; print('mesa-mcp', v('mesa-mcp'), 'mesa-ducklake', v('mesa-ducklake'), 'duckdb', duckdb.__version__)" && \
    ln -s /opt/mesa/bin/mesa-mcp /opt/mesa/bin/mesa-ducklake /usr/local/bin/

# DuckDB 2.0 for users: the `duckdb` CLI on PATH and duckdb in the base conda Python.
# Same major as /opt/mesa, so catalogs mesa-ducklake writes (DuckDB 2-only)
# open here too.
ARG DUCKDB_VERSION=2.0.0
RUN DUCKDB_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64) && \
    DUCKDB_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$DUCKDB_SHA256_ARM64" || echo "$DUCKDB_SHA256_AMD64") && \
    curl -fsSL -o /tmp/duckdb.tgz "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb-cli-linux-${DUCKDB_ARCH}.tar.gz" && \
    echo "${DUCKDB_SHA256}  /tmp/duckdb.tgz" | sha256sum -c - && \
    tar -xz -C /usr/local/bin -f /tmp/duckdb.tgz duckdb && rm -f /tmp/duckdb.tgz && \
    duckdb --version | grep "^v${DUCKDB_VERSION} " && \
    /opt/conda/bin/pip install --no-cache-dir "duckdb==${DUCKDB_VERSION}" && \
    chown -R "$(stat -c %u:%g /opt/conda)" /opt/conda/lib/python3*/site-packages/duckdb* && \
    /opt/conda/bin/python -c "import duckdb; assert duckdb.__version__ == '${DUCKDB_VERSION}', duckdb.__version__"

# Configure FUSE for non-root users and create OSN directory
RUN echo "user_allow_other" >> /etc/fuse.conf && \
    chmod 644 /etc/fuse.conf && \
    mkdir -p /osn && \
    chmod 755 /osn && \
    chown 1000:100 /osn

# set the ENV for the credential type
ENV GCM_CREDENTIAL_STORE=cache

USER jovyan

# Install Claude Code, OpenAI Codex, and Claude Code Router via npm
# (npm install is preferred over claude.ai/install.sh for Docker builds)
# ccr (claude-code-router) lets Claude Code talk to AI Verde's non-Anthropic
# models; see aiverde-setup and https://github.com/musistudio/claude-code-router
# Versions are pinned (ARGs above); the filesystem MCP server is installed here so the
# agent configs run it directly instead of `npx -y` fetching the newest release at
# every agent start.
RUN npm config set prefix /home/jovyan/.npm-global && \
    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" "@openai/codex@${CODEX_VERSION}" \
        "@musistudio/claude-code-router@${CCR_VERSION}" "@modelcontextprotocol/server-filesystem@${MCP_FS_VERSION}" && \
    npm cache clean --force && \
    test -x /home/jovyan/.npm-global/bin/mcp-server-filesystem

# Install Antigravity CLI (replaces deprecated Google Gemini CLI — deadline June 18 2026)
# https://antigravity.google/blog/introducing-google-antigravity-cli
# Binary: agy, installed to ~/.local/bin
RUN mkdir -p /home/jovyan/.cache/antigravity/staging && \
    curl -fsSL https://antigravity.google/cli/install.sh | bash

# Install OpenCode (https://opencode.ai/) — --no-modify-path avoids shell detection hang in Docker
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path --version "${OPENCODE_VERSION}" && \
    /home/jovyan/.opencode/bin/opencode --version | grep -F "${OPENCODE_VERSION}"

# Install VS Code (code-server); drop its ~100 MB install cache afterwards
# (install.sh picks the .deb on Ubuntu: code-server lands in /usr/bin)
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version "${CODE_SERVER_VERSION}" && \
    code-server --version | grep -F "${CODE_SERVER_VERSION}" && \
    rm -rf /home/jovyan/.cache/code-server

# Jupyter proxies: VS Code, RStudio (rsession), and Shiny cards in the Launcher
RUN python3 -m pip install --no-cache-dir jupyter-vscode-proxy \
        git+https://github.com/jupyterhub/jupyter-rsession-proxy@216d9e5e65f0a16af34cf1bafc418c4daa1e08d6 \
        jupyter-shiny-proxy

RUN mamba install -y -c conda-forge jupyter-server-proxy && \
    mamba clean -afy

# Configure bashrc. The motd only prints in interactive shells. The base skel
# .bashrc already runs the conda shell hook, so conda is NOT re-sourced here.
# No per-shell `sudo gocmd upgrade`: gocmd is pinned at build time (a root-run
# self-updater on every terminal open was a supply-chain path).
RUN echo ". /etc/profile.d/mesa-prompt.sh" >> ~/.bashrc && \
    echo 'if [[ $- == *i* ]] && [ -r /etc/motd ]; then /etc/motd; fi' >> ~/.bashrc

# set path for Go, NPM globals, OpenCode, and Antigravity CLI
ENV PATH="/home/jovyan/.local/bin:/home/jovyan/.npm-global/bin:/home/jovyan/.opencode/bin:/usr/local/go/bin:${PATH}"

# open port 8888 for JupyterLab
EXPOSE 8888

# Pre-create the working dir and iRODS dir as jovyan: WORKDIR would create a
# missing dir root-owned, which breaks jupyter lab when run outside VICE
RUN mkdir -p /home/jovyan/.irods /home/jovyan/data-store

#set working directory
WORKDIR /home/jovyan/data-store

# tmux config: hide the status bar, enable mouse-wheel scrollback
RUN printf 'set-option -g status off\nset -g mouse on\n' >> /home/jovyan/.tmux.conf

# formation (CyVerse Discovery Environment / Formation API — launch apps, manage
# analyses) is a hosted, OAuth-protected remote MCP at
# https://de.cyverse.org/formation/mcp, registered directly in the agent configs
# (opencode.json, claude.json, antigravity). No local binary is built; each user
# authenticates in-agent with their own CyVerse (Keycloak) login.

# ---------------------------------------------------------------------------
# Config / assets last, AFTER the heavy layers, so editing the splash, the
# shell prompt, entry.sh, aiverde-setup, or any agent-CLI config rebuilds in
# seconds and does NOT invalidate the expensive install caches.
# ---------------------------------------------------------------------------

# Jupyter server config (tokenless, VICE ingress handles auth) and RStudio
# config for jupyter-rsession-proxy (upstream cyverse-vice shipped rserver.conf
# in the repo but never COPY'd it — fixed here).
COPY jupyter_notebook_config.json /opt/conda/etc/jupyter/jupyter_notebook_config.json
COPY rserver.conf /etc/rstudio/rserver.conf

# System assets (root-owned). --chmod sets the mode without a separate RUN
# (needed because USER is jovyan here and these live in root-owned paths).
COPY --chmod=755 01-custom /etc/motd
COPY mesa-prompt.sh /etc/profile.d/mesa-prompt.sh
COPY --chmod=755 entry.sh /bin/entry.sh
COPY --chmod=755 osn-mount.sh /usr/local/bin/osn-mount.sh
COPY --chmod=755 configs/aiverde-setup.sh /usr/local/bin/aiverde-setup
COPY --chmod=755 configs/cyverse-login.sh /usr/local/bin/cyverse-login
# Replace the mesa-mcp symlink (from the venv install) with a shim that strips
# empty MESA_MCP_* vars before launching the server. mesa-ducklake stays a symlink.
# Remove the symlink FIRST: COPY writes THROUGH a symlink to its target, which
# would overwrite the real /opt/mesa/bin/mesa-mcp and make the shim exec itself.
RUN sudo rm -f /usr/local/bin/mesa-mcp
COPY --chmod=755 configs/mesa-mcp-shim.sh /usr/local/bin/mesa-mcp

# Pre-load the irods / mesa / formation / filesystem MCP servers for every
# agent CLI (Claude Code, Codex, OpenCode, Antigravity).
COPY --chown=1000:100 configs/claude.json /home/jovyan/.claude.json
COPY --chown=1000:100 configs/codex-config.toml /home/jovyan/.codex/config.toml
COPY --chown=1000:100 configs/opencode.json /home/jovyan/.config/opencode/opencode.json
COPY --chown=1000:100 configs/antigravity-mcp_config.json /home/jovyan/.gemini/config/mcp_config.json

# COPY --chown does not chown the parent dirs it auto-creates, so ~/.config
# is left root-owned and jovyan cannot create ~/.config/aiverde at runtime
# (aiverde-setup). Restore ownership of jovyan's config tree.
RUN sudo chown -R 1000:100 /home/jovyan/.config /home/jovyan/.codex /home/jovyan/.gemini

ENTRYPOINT ["bash", "/bin/entry.sh"]
