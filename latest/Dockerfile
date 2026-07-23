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
    gdebi-core gnupg2 git mercurial subversion tmux grep sed dpkg unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# git-credential-manager (arch-aware), then RStudio Server + Shiny Server.
# Posit ships a single jammy deb as the official artifact for Ubuntu 22/24;
# there are no arm64 server debs, so both are amd64-only.
RUN GCM_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    wget -q https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.7.3/gcm-linux-${GCM_ARCH}-2.7.3.deb \
         -O /tmp/gcm.deb && \
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

# Node.js 22, locales, terminal tools, s3fs
RUN apt-get update && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y locales lolcat neofetch figlet w3m-img imagemagick s3fs fuse nodejs socat bubblewrap && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt update && apt install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Go
RUN wget -q -c https://dl.google.com/go/go1.25.5.linux-${TARGETARCH}.tar.gz -O - | tar -xz -C /usr/local

# Build the iRODS MCP server (stdio MCP access to the CyVerse Data Store)
# https://github.com/idss-mesa/irods-mcp-server
# NOTE: the base image sets ENV HOME=/home/jovyan even for root, so keep the
# Go caches in /tmp or they land root-owned in jovyan's home
RUN git clone --depth 1 https://github.com/idss-mesa/irods-mcp-server /tmp/irods-mcp-server && \
    cd /tmp/irods-mcp-server && \
    CGO_ENABLED=0 GOPATH=/tmp/go GOCACHE=/tmp/go-cache /usr/local/go/bin/go build -o /usr/local/bin/irods-mcp-server ./cmd/main.go && \
    cd / && rm -rf /tmp/irods-mcp-server /tmp/go /tmp/go-cache

# Install GoCommands
# https://learning.cyverse.org/ds/gocommands/
RUN cd /usr/local/bin && \
    GOCMD_VER=$(curl -L -s https://raw.githubusercontent.com/cyverse/gocommands/main/VERSION.txt); \
    curl -L -s https://github.com/cyverse/gocommands/releases/download/${GOCMD_VER}/gocmd-${GOCMD_VER}-linux-${TARGETARCH}.tar.gz | tar zxvf -

ENV PATH=${PATH}:/usr/games

# install AWS CLI
RUN AWS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
    rm -rf awscliv2.zip aws

# Install mesa-mcp and mesa-ducklake (https://github.com/idss-mesa)
# into a dedicated venv, isolated from /opt/conda: users pip/mamba freely into
# the base env, and an upgrade of pydantic/duckdb/python-irodsclient there
# would silently break mesa-mcp. cyverse-login also hardcodes
# /opt/mesa/bin/python3 for iRODS password obfuscation.
RUN /opt/conda/bin/python3 -m venv /opt/mesa && \
    /opt/mesa/bin/pip install --no-cache-dir \
      git+https://github.com/idss-mesa/mesa-ducklake.git \
      git+https://github.com/idss-mesa/mesa-mcp.git && \
    ln -s /opt/mesa/bin/mesa-mcp /opt/mesa/bin/mesa-ducklake /usr/local/bin/

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
RUN npm config set prefix /home/jovyan/.npm-global && \
    npm install -g @anthropic-ai/claude-code @openai/codex @musistudio/claude-code-router && \
    npm cache clean --force

# Install Antigravity CLI (replaces deprecated Google Gemini CLI — deadline June 18 2026)
# https://antigravity.google/blog/introducing-google-antigravity-cli
# Binary: agy, installed to ~/.local/bin
RUN mkdir -p /home/jovyan/.cache/antigravity/staging && \
    curl -fsSL https://antigravity.google/cli/install.sh | bash

# Install OpenCode (https://opencode.ai/) — --no-modify-path avoids shell detection hang in Docker
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# Install VS Code (code-server); drop its ~100 MB install cache afterwards
RUN curl -fsSL https://code-server.dev/install.sh | sh && \
    rm -rf /home/jovyan/.cache/code-server

# Jupyter proxies: VS Code, RStudio (rsession), and Shiny cards in the Launcher
RUN python3 -m pip install --no-cache-dir jupyter-vscode-proxy \
        git+https://github.com/jupyterhub/jupyter-rsession-proxy@216d9e5e65f0a16af34cf1bafc418c4daa1e08d6 \
        jupyter-shiny-proxy

RUN mamba install -y -c conda-forge jupyter-server-proxy && \
    mamba clean -afy

# Configure bashrc. The base skel .bashrc already runs the conda shell hook,
# so conda is NOT re-sourced here. gocmd upgrade is time-boxed: an unguarded
# network call at every shell open would hang JupyterLab terminal spawns
# whenever egress is slow or blocked.
RUN echo ". /etc/profile.d/mesa-prompt.sh" >> ~/.bashrc && \
    echo '[ ! -z "$TERM" -a -r /etc/motd ] && /etc/motd' >> ~/.bashrc && \
    echo $'\n# upgrade GoCommands\ntimeout 10 sudo gocmd upgrade > /dev/null 2>&1 || true' >> ~/.bashrc

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
