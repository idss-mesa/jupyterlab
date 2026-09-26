#!/usr/bin/env bash
# GPU smoke test for the MESA JupyterLab GPU image (see ../README.md "GPU variant").
#
#   gpu/test-gpu.sh [IMAGE]          default harbor.cyverse.org/vice/mesa-jupyterlab:gpu
#   GPU=1 gpu/test-gpu.sh IMAGE      GPU=<index> or GPU=all (default 0)
#
# Needs an NVIDIA GPU, nvidia-container-toolkit (docker run --gpus) and network
# access (T3 pulls qwen3:0.6b, ~0.5 GB). Exits non-zero if any test fails.
#   T1 static      nvidia-smi, host-injected libcuda, no baked driver, agent configs
#   T2 start       VICE-like start (uid 1000, default entrypoint): JupyterLab answers,
#                  clean server log, extensions OK
#   T3 gpu-check   mesa-gpu-check --ollama (CUDA, compat, torch, Ollama 100% GPU)
#   T4 app         code run in the default python3 kernel THROUGH the running server
#                  (torch CUDA matmul + CuPy); NVDashboard extension, REST + websocket
#   T5 no-GPU      starts without --gpus; JupyterLab answers; mesa-gpu-check reports
#                  the missing GPU (non-zero) without crashing
#   T6 apt pin     /etc/apt/preferences.d/mesa-no-nvidia-driver (644); after apt-get
#                  update (throwaway root container) driver packages have no
#                  candidate while the CUDA toolkit still does (SKIP, not FAIL,
#                  when apt-get update fetches no package lists: no network)
#   T7 exec shell  `docker exec bash -i` (non-login, not started by the IDE) gets the
#                  same CUDA forward-compat env as the running Jupyter server
#   T8 nvitop      on PATH for uid 1000 in an interactive shell
set -uo pipefail

IMAGE=${1:-harbor.cyverse.org/vice/mesa-jupyterlab:gpu}
GPU=${GPU:-0}
if [ "$GPU" = all ]; then gpu_args=(--gpus all); else gpu_args=(--gpus "device=$GPU"); fi
name=mesa-gpu-jupyterlab-test-$$
logdir=$(mktemp -d "${TMPDIR:-/tmp}/mesa-gpu-jupyterlab-test.XXXXXX")

cleanup() { docker rm -f "$name-gpu" "$name-nogpu" >/dev/null 2>&1 || true; }
trap cleanup EXIT

names=() states=() details=()
record() { # name PASS|FAIL|SKIP detail (only FAIL fails the run)
    names+=("$1"); states+=("$2"); details+=("$3")
    printf '[%s] %-24s %s\n' "$2" "$1" "$3"
}

# wait_http CONTAINER PORT -> 0 when /api/status answers 200 within 300 s and the
# container is still running
wait_http() {
    local c=$1 port=$2 code=
    for _ in $(seq 1 150); do
        [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] || return 1
        code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$port/api/status" || true)
        [ "$code" = 200 ] && return 0
        sleep 2
    done
    return 1
}

echo "== MESA JupyterLab GPU test: $IMAGE (GPU=$GPU); logs in $logdir"

# ---- T1: static checks in a throwaway container -----------------------------
out=$(docker run --rm "${gpu_args[@]}" --entrypoint bash "$IMAGE" -c '
set -e
nvidia-smi -L
lib=$(ldconfig -p | awk "/libcuda.so.1 /{print \$NF; exit}")
real=$(readlink -f "$lib")
drv=$(sed -nE "s/.*Kernel Module( for [a-z0-9_]+)?[[:space:]]+([0-9]+\.[0-9.]+).*/\2/p" /proc/driver/nvidia/version | head -1)
echo "libcuda.so.1 -> $real (host driver $drv)"
case "$real" in *"libcuda.so.$drv") ;; *) echo "libcuda is not the host driver" >&2; exit 1 ;; esac
if dpkg -l | grep -E "^ii +(nvidia-driver|nvidia-dkms|nvidia-utils|nvidia-compute-utils|libnvidia-(compute|gl|decode|encode|extra|fbc1|cfg1|common)|cuda-drivers)"; then echo "driver userspace baked" >&2; exit 1; fi
test ! -e /usr/local/cuda/compat
test -e "$MESA_CUDA_COMPAT_DIR/libcuda.so.1"
test "$(stat -c %u:%g ~/.config/opencode/opencode.json ~/.codex/config.toml | sort -u)" = 1000:100
python3 -c "import json,os; p=json.load(open(os.path.expanduser(\"~/.config/opencode/opencode.json\")))[\"provider\"]; assert \"ollama\" in p and \"aiverde\" in p"
grep -q "^oss_provider = \"ollama\"" ~/.codex/config.toml
echo "no baked driver, compat at $MESA_CUDA_COMPAT_DIR, agent configs OK (1000:100)"
' 2>&1)
rc=$?
printf '%s\n' "$out" > "$logdir/t1-static.log"
env_vis=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | grep -c '^NVIDIA_VISIBLE_DEVICES=' || true)
if [ $rc -eq 0 ] && [ "$env_vis" = 0 ]; then
    record "T1 static" PASS "$(printf '%s' "$out" | grep -m1 '^GPU'); $(printf '%s' "$out" | grep -m1 '^libcuda')"
else
    record "T1 static" FAIL "rc=$rc NVIDIA_VISIBLE_DEVICES-baked=$env_vis: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ---- T2: start like VICE ------------------------------------------------------
docker run -d --name "$name-gpu" "${gpu_args[@]}" --user 1000 -e IPLANT_USER=mesa-test \
    -p 127.0.0.1::8888 "$IMAGE" >/dev/null
port=$(docker port "$name-gpu" 8888/tcp | head -1 | awk -F: '{print $NF}')
t0=$SECONDS
if wait_http "$name-gpu" "$port"; then
    sleep 5  # let late extension start-up messages reach the log
    docker logs "$name-gpu" > "$logdir/t2-server.log" 2>&1
    errs=$(grep -nE '^\[E |Traceback|[Ff]ailed to load|Error loading|ExtensionLoadError|ModuleNotFoundError' "$logdir/t2-server.log" | head -5)
    loaded=$(grep -cE '\| extension was successfully loaded' "$logdir/t2-server.log")
    lab=$(docker exec -u 1000 "$name-gpu" jupyter labextension list 2>&1); lab_rc=$?
    printf '%s\n' "$lab" > "$logdir/t2-labextensions.log"
    lab_bad=$(printf '%s\n' "$lab" | grep -E ' X$|incompatible|outdated' | head -3)
    if [ -z "$errs" ] && [ $lab_rc -eq 0 ] && [ -z "$lab_bad" ] && [ "$(docker inspect -f '{{.State.Running}}' "$name-gpu")" = true ]; then
        record "T2 start (VICE-like)" PASS "/api/status 200 after $((SECONDS - t0)) s; $loaded server extensions loaded, no errors; labextension list OK"
    else
        record "T2 start (VICE-like)" FAIL "log errors: ${errs:-none}; labextension rc=$lab_rc ${lab_bad}"
    fi
else
    docker logs "$name-gpu" > "$logdir/t2-server.log" 2>&1
    record "T2 start (VICE-like)" FAIL "JupyterLab did not answer on 8888 within 300 s: $(tail -3 "$logdir/t2-server.log" | tr '\n' ' ')"
fi

# ---- T3: mesa-gpu-check --ollama ------------------------------------------------
out=$(docker exec -u 1000 "$name-gpu" mesa-gpu-check --ollama 2>&1); rc=$?
printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' > "$logdir/t3-gpu-check.log"
summary=$(grep -m1 '== Summary' "$logdir/t3-gpu-check.log")
if [ $rc -eq 0 ] && grep -q '100% on the GPU' "$logdir/t3-gpu-check.log"; then
    record "T3 mesa-gpu-check" PASS "${summary#== }; $(grep -m1 -oE 'fp16 matmul ~[0-9.]+ TFLOPS' "$logdir/t3-gpu-check.log"); qwen3:0.6b 100% GPU"
else
    record "T3 mesa-gpu-check" FAIL "rc=$rc ${summary}; $(grep -m3 'FAIL' "$logdir/t3-gpu-check.log" | tr '\n' ' ')"
fi

# ---- T4a: default python3 kernel, started by the running Jupyter server --------
out=$(docker exec -i -u 1000 "$name-gpu" python3 - 2>&1 <<'EOF'
import asyncio, json, re, uuid, urllib.request
from datetime import datetime, timezone
from tornado.websocket import websocket_connect

BASE = "127.0.0.1:8888"
CODE = r'''
import os, torch, cupy
assert torch.cuda.is_available(), "torch.cuda.is_available() is False"
a = torch.randn(2048, 2048, device="cuda")
s = (a @ a).sum().item()
torch.cuda.synchronize()
c = int((cupy.arange(1000, dtype=cupy.int64) ** 2).sum())  # exact: sum of k^2, k < 1000
assert c == 332833500, c
print(f"torch {torch.__version__} (CUDA {torch.version.cuda}) on {torch.cuda.get_device_name(0)}: "
      f"2048x2048 matmul OK (sum {s:.3e}); cupy {cupy.__version__} OK; "
      f"MESA_CUDA_COMPAT={os.environ.get('MESA_CUDA_COMPAT', 'unset')}")
'''

def api(method, path, body=None):
    req = urllib.request.Request(f"http://{BASE}{path}", method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        return json.loads(data) if data else None

SESSION = uuid.uuid4().hex

def request(msg_type, content):
    return {"header": {"msg_id": uuid.uuid4().hex, "username": "mesa-test", "session": SESSION,
                       "msg_type": msg_type, "version": "5.3",
                       "date": datetime.now(timezone.utc).isoformat()},
            "parent_header": {}, "metadata": {}, "channel": "shell", "buffers": [],
            "content": content}

async def reply(ws, msg_id, reply_type, timeout, out=None):
    """Read until the shell reply to msg_id; collect its stream/error output."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while True:
        left = deadline - loop.time()
        if left <= 0:
            raise SystemExit(f"no {reply_type} within {timeout} s")
        raw = await asyncio.wait_for(ws.read_message(), left)
        if raw is None:
            raise SystemExit("kernel websocket closed")
        m = json.loads(raw)
        if m["msg_type"] == "status" and m["content"].get("execution_state") in ("dead", "restarting"):
            raise SystemExit(f"kernel {m['content']['execution_state']} (crashed?)")
        if m.get("parent_header", {}).get("msg_id") != msg_id:
            continue
        if out is not None and m["msg_type"] == "stream":
            out.append(m["content"]["text"])
        elif out is not None and m["msg_type"] == "error":
            out.append(re.sub(r"\x1b\[[0-9;]*m", "", "\n".join(m["content"]["traceback"])))
        elif m["msg_type"] == reply_type and m["channel"] == "shell":
            return m["content"]

async def main():
    kid = api("POST", "/api/kernels", {"name": "python3"})["id"]
    try:
        ws = await websocket_connect(f"ws://{BASE}/api/kernels/{kid}/channels?session_id={SESSION}")
        # like jupyter_client: wait until the kernel answers before executing
        msg = request("kernel_info_request", {})
        await ws.write_message(json.dumps(msg))
        await reply(ws, msg["header"]["msg_id"], "kernel_info_reply", 120)
        msg = request("execute_request", {"code": CODE, "silent": False, "store_history": False,
                                          "user_expressions": {}, "allow_stdin": False,
                                          "stop_on_error": True})
        await ws.write_message(json.dumps(msg))
        out = []
        status = (await reply(ws, msg["header"]["msg_id"], "execute_reply", 300, out))["status"]
        print("".join(out).strip())
        raise SystemExit(0 if status == "ok" else 1)
    finally:
        api("DELETE", f"/api/kernels/{kid}")

asyncio.run(main())
EOF
); rc=$?
printf '%s\n' "$out" > "$logdir/t4-kernel.log"
if [ $rc -eq 0 ]; then
    record "T4a kernel via server" PASS "$(tail -1 "$logdir/t4-kernel.log")"
else
    docker logs --tail 80 "$name-gpu" > "$logdir/t4-server.log" 2>&1
    record "T4a kernel via server" FAIL "rc=$rc: $(tail -3 "$logdir/t4-kernel.log" | tr '\n' ' ')"
fi

# ---- T4b: NVDashboard (server + lab extension, REST + GPU websocket) -----------
out=$(docker exec -i -u 1000 "$name-gpu" python3 - 2>&1 <<'EOF'
import asyncio, json, re, subprocess, urllib.request
from tornado.websocket import websocket_connect

def listing(*cmd):
    p = subprocess.run(["jupyter", *cmd, "list"], capture_output=True, text=True)
    return re.sub(r"\x1b\[[0-9;]*m", "", p.stdout + p.stderr)
srv = listing("server", "extension")
assert re.search(r"jupyterlab_nvdashboard\s+enabled", srv), "server extension not enabled"
assert re.search(r"jupyterlab_nvdashboard [0-9.]+\s+OK", srv), "server extension did not validate"
lab = listing("labextension")
assert re.search(r"jupyterlab-nvdashboard v[0-9.]+\s+enabled\s+OK", lab), "lab extension not enabled/OK"
acc = json.load(urllib.request.urlopen("http://127.0.0.1:8888/nvdashboard/accelerators/check", timeout=10))
assert acc["has_gpu"] and acc["ngpus"] >= 1, acc

async def ws():
    c = await websocket_connect("ws://127.0.0.1:8888/nvdashboard/gpu_utilization")
    for _ in range(10):
        m = json.loads(await asyncio.wait_for(c.read_message(), 10))
        if "gpu_utilization" in m:
            return m
    raise SystemExit("no gpu_utilization message")
m = asyncio.run(ws())
print(f"server+lab extension enabled; accelerators/check ngpus={acc['ngpus']}; websocket gpu_utilization={m['gpu_utilization']}")
EOF
); rc=$?
printf '%s\n' "$out" > "$logdir/t4-nvdashboard.log"
if [ $rc -eq 0 ]; then
    record "T4b NVDashboard" PASS "$(tail -1 "$logdir/t4-nvdashboard.log")"
else
    record "T4b NVDashboard" FAIL "rc=$rc: $(tail -3 "$logdir/t4-nvdashboard.log" | tr '\n' ' ')"
fi

# ---- T5: no GPU ------------------------------------------------------------------
docker run -d --name "$name-nogpu" --user 1000 -e IPLANT_USER=mesa-test -p 127.0.0.1::8888 "$IMAGE" >/dev/null
port=$(docker port "$name-nogpu" 8888/tcp | head -1 | awk -F: '{print $NF}')
if wait_http "$name-nogpu" "$port"; then
    out=$(docker exec -u 1000 "$name-nogpu" mesa-gpu-check 2>&1); rc=$?
    printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' > "$logdir/t5-nogpu-check.log"
    acc=$(curl -s -m 5 "http://127.0.0.1:$port/nvdashboard/accelerators/check")
    if [ $rc -eq 1 ] && grep -q 'no NVIDIA GPU in this container' "$logdir/t5-nogpu-check.log" \
        && grep -q '== Summary' "$logdir/t5-nogpu-check.log"; then
        record "T5 no-GPU start" PASS "JupyterLab 200; mesa-gpu-check rc=1: $(grep -m1 '== Summary' "$logdir/t5-nogpu-check.log" | sed 's/== //'); nvdashboard: $acc"
    else
        record "T5 no-GPU start" FAIL "mesa-gpu-check rc=$rc: $(tail -3 "$logdir/t5-nogpu-check.log" | tr '\n' ' ')"
    fi
else
    docker logs "$name-nogpu" > "$logdir/t5-server.log" 2>&1
    record "T5 no-GPU start" FAIL "JupyterLab did not answer without a GPU: $(tail -3 "$logdir/t5-server.log" | tr '\n' ' ')"
fi

# ---- T6: apt pin against NVIDIA driver packages ------------------------------------
# apt-get update exits 0 on noble even when every fetch fails, so "no network"
# is detected by whether it downloaded any package lists (starting from none).
out=$(docker run --rm -u 0 --entrypoint bash "$IMAGE" -c '
f=/etc/apt/preferences.d/mesa-no-nvidia-driver
echo "pin-mode: $(stat -c "%a %U:%G" "$f")"
rm -rf /var/lib/apt/lists/*
timeout 300 apt-get update -qq >/dev/null 2>&1
if ! compgen -G "/var/lib/apt/lists/*_Packages*" >/dev/null; then echo "apt-update: no package lists fetched"; exit 0; fi
echo "apt-update: ok"
apt-cache policy nvidia-driver-580 cuda-drivers cuda-toolkit-12-6
' 2>&1)
printf '%s\n' "$out" > "$logdir/t6-apt-pin.log"
# cand PKG / nver PKG: Candidate and number of known versions in apt-cache policy
cand() { printf '%s\n' "$out" | awk -v p="$1:" '$0 == p {f = 1; next} /^[^ ]/ {f = 0} f && /Candidate:/ {print $2; exit}'; }
nver() { printf '%s\n' "$out" | awk -v p="$1:" '$0 == p {f = 1; next} /^[^ ]/ {f = 0} f && /^     [0-9]/ {n++} END {print n + 0}'; }
mode=$(printf '%s\n' "$out" | sed -n 's/^pin-mode: //p')
if [ "$mode" != "644 root:root" ]; then
    record "T6 apt pin" FAIL "pin file: ${mode:-missing} (want 644 root:root): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
elif printf '%s\n' "$out" | grep -q '^apt-update: no package lists fetched'; then
    record "T6 apt pin" SKIP "pin file 644 root:root; apt-cache policy check skipped: apt-get update fetched no package lists (no network?)"
elif [ "$(cand nvidia-driver-580)" = "(none)" ] && [ "$(nver nvidia-driver-580)" -gt 0 ] \
    && [ "$(cand cuda-drivers)" = "(none)" ] && [ "$(nver cuda-drivers)" -gt 0 ] \
    && [ -n "$(cand cuda-toolkit-12-6)" ] && [ "$(cand cuda-toolkit-12-6)" != "(none)" ]; then
    record "T6 apt pin" PASS "pin file 644 root:root; nvidia-driver-580 ($(nver nvidia-driver-580) versions) and cuda-drivers: Candidate (none); cuda-toolkit-12-6 still installable ($(cand cuda-toolkit-12-6))"
else
    record "T6 apt pin" FAIL "nvidia-driver-580 candidate=$(cand nvidia-driver-580) ($(nver nvidia-driver-580) versions), cuda-drivers candidate=$(cand cuda-drivers), cuda-toolkit-12-6 candidate=$(cand cuda-toolkit-12-6)"
fi

# ---- T7: docker/kubectl exec shell gets the IDE's CUDA forward-compat env ----------
# The Jupyter server (and its terminals/kernels) inherit the env from the
# entrypoint; `docker exec bash -i` does not and relies on /etc/bash.bashrc.
# compat=<MESA_CUDA_COMPAT> ld=<1 if the compat dir is on LD_LIBRARY_PATH>
ide=$(docker exec -u 1000 "$name-gpu" bash -c '
pid=$(pgrep -o -f "jupyter-lab") || exit 1
env_of() { tr "\0" "\n" < "/proc/$pid/environ" | sed -n "s/^$1=//p"; }
c=$(env_of MESA_CUDA_COMPAT); d=$(env_of MESA_CUDA_COMPAT_DIR); l=$(env_of LD_LIBRARY_PATH)
case ":$l:" in *":$d:"*) ld=1 ;; *) ld=0 ;; esac
echo "compat=${c:-unset} ld=$ld"' 2>&1)
exec_sh=$(docker exec -u 1000 "$name-gpu" bash -i -c '
case ":${LD_LIBRARY_PATH:-}:" in *":${MESA_CUDA_COMPAT_DIR:-/nonexistent}:"*) ld=1 ;; *) ld=0 ;; esac
echo "@@compat=${MESA_CUDA_COMPAT:-unset} ld=$ld@@"' 2>"$logdir/t7-exec-shell.stderr" | sed -n 's/.*@@\(.*\)@@.*/\1/p' | tail -1)
printf 'IDE (jupyter-lab environ): %s\nexec bash -i: %s\n' "$ide" "$exec_sh" > "$logdir/t7-exec-shell.log"
case "$ide" in
    compat=[01]\ ld=[01])
        if [ "$exec_sh" = "$ide" ]; then
            record "T7 exec shell env" PASS "docker exec bash -i: $exec_sh = Jupyter server env"
        else
            record "T7 exec shell env" FAIL "docker exec bash -i: '${exec_sh:-no output}' != Jupyter server env '$ide'"
        fi ;;
    *) record "T7 exec shell env" FAIL "could not read the Jupyter server env: $ide" ;;
esac

# ---- T8: nvitop on PATH for the VICE user ------------------------------------------
out=$(docker exec -u 1000 "$name-gpu" bash -i -c 'p=$(command -v nvitop) && v=$(nvitop --version 2>&1 | head -1) && echo "@@$p ($v)@@"' 2>/dev/null \
    | sed -n 's/.*@@\(.*\)@@.*/\1/p' | tail -1)
if [ -n "$out" ]; then
    record "T8 nvitop on PATH" PASS "bash -i as uid 1000: $out"
else
    record "T8 nvitop on PATH" FAIL "command -v nvitop failed in an interactive shell as uid 1000"
fi

# ---- summary -----------------------------------------------------------------------
fail=0
printf '\n%-24s %-6s %s\n' TEST RESULT DETAIL
printf '%-24s %-6s %s\n' ------------------------ ------ ------
for i in "${!names[@]}"; do
    printf '%-24s %-6s %s\n' "${names[$i]}" "${states[$i]}" "${details[$i]}"
    [ "${states[$i]}" = FAIL ] && fail=1
done
echo "logs: $logdir"
exit $fail
