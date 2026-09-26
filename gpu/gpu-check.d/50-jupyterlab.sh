# shellcheck shell=bash disable=SC2154
# /etc/mesa/gpu-check.d/50-jupyterlab.sh — JupyterLab section of mesa-gpu-check.
# Sourced by mesa-gpu-check (bash, set -u): uses its hdr/ok/bad/warn/info helpers
# and $have_gpu. Checks what the running Jupyter server sees, not a fresh process.
hdr "JupyterLab (NVDashboard, Jupyter AI)"
_jl_url="http://127.0.0.1:${JUPYTER_PORT:-8888}"
if curl -fsS -m 3 "$_jl_url/api/status" >/dev/null 2>&1; then
    # NVDashboard's server extension probes NVML once, when the server starts
    _jl_acc=$(curl -fsS -m 5 "$_jl_url/nvdashboard/accelerators/check" 2>/dev/null)
    case "$_jl_acc" in
        *'"has_gpu": true'*)
            ok "NVDashboard sees $(printf '%s' "$_jl_acc" | grep -oE '"ngpus": [0-9]+' | grep -oE '[0-9]+') GPU(s) (left sidebar: GPU Dashboards)" ;;
        *'"has_gpu": false'*)
            if [ "$have_gpu" = 1 ]; then
                bad "NVDashboard sees no GPU although nvidia-smi does (Jupyter server started before the GPU was visible?)"
            else
                info "NVDashboard: no GPU"
            fi ;;
        *) warn "NVDashboard endpoint $_jl_url/nvdashboard/accelerators/check did not answer (extension not loaded?)" ;;
    esac
    # Jupyter AI's MCP server (notebook tools for agents) must stay on loopback.
    # Wildcard binds (0.0.0.0 / ::) are checked first: they need no loopback
    # listener to be reachable from the whole pod network.
    if grep -qiE '^ *[0-9]+: (00000000|00000000000000000000000000000000):0BB9 [0-9A-F:]+ 0A' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
        warn "Jupyter AI MCP server listens on all interfaces (port 3001)"
    elif grep -qiE '^ *[0-9]+: (0100007F|00000000000000000000000001000000):0BB9 [0-9A-F:]+ 0A' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
        ok "Jupyter AI MCP server on localhost:3001 (loopback only)"
    else
        info "Jupyter AI MCP server not listening on port 3001"
    fi
else
    info "Jupyter server not answering on $_jl_url (checks skipped)"
fi
unset _jl_url _jl_acc
