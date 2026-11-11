platform = linux/amd64
repo = harbor.cyverse.org/vice/mesa-jupyterlab
tag = latest
context = latest
repotag = $(repo):$(tag)

.PHONY: build push run rmi pull-base build-gpu test-gpu push-gpu run-gpu

build:
	docker buildx build --rm --platform "$(platform)" -t "$(repotag)" --load "$(context)/"

push:
	docker push "$(repotag)"

run:
	docker run --rm -p 8888:8888 -e IPLANT_USER=$$USER "$(repotag)"

rmi:
	docker rmi "$(repotag)"

# ---- NVIDIA GPU variant (gpu/) — layers on the CPU image above ----
gpu_repotag = $(repo):gpu
base_image = $(repo):latest

pull-base:        ## fetch the published CPU image the GPU layer builds FROM
	docker pull "$(base_image)"

build-gpu:        ## BASE_IMAGE defaults to the CPU image (run `make build` first to layer on a local CPU build)
	docker buildx build --rm --platform "$(platform)" --build-arg BASE_IMAGE="$(base_image)" -t "$(gpu_repotag)" --load gpu/
	@docker image inspect -f 'built on $(base_image): {{.Id}} {{.RepoDigests}}' "$(base_image)" 2>/dev/null || true

test-gpu:         ## GPU smoke test (needs an NVIDIA GPU + nvidia-container-toolkit); GPU=<index> picks the device
	gpu/test-gpu.sh "$(gpu_repotag)"

push-gpu:
	docker push "$(gpu_repotag)"

run-gpu:          ## loopback only: JupyterLab is tokenless outside VICE (remote: ssh -L 8888:127.0.0.1:8888 <gpu-host>)
	docker run --rm --gpus all -p 127.0.0.1:8888:8888 -e IPLANT_USER=$$USER "$(gpu_repotag)"

# ---- AI Sandbox variants (sandbox/): the published images with sudo and every
# setuid/setgid/file-capability escalation path removed. :sandbox layers on the
# CPU :latest, :gpu-sandbox on :gpu. ----
sandbox_repotag = $(repo):sandbox
gpu_sandbox_repotag = $(repo):gpu-sandbox
sandbox_port = 8888
sandbox_path = /api/status
sandbox_docker_args = 

build-sandbox:    ## :sandbox from the CPU image (base_image=... to pin a digest)
	docker buildx build --rm --platform "$(platform)" --build-arg BASE_IMAGE="$(repo):latest" -t "$(sandbox_repotag)" --load sandbox/

build-gpu-sandbox: ## :gpu-sandbox from the GPU image
	docker buildx build --rm --platform "$(platform)" --build-arg BASE_IMAGE="$(gpu_repotag)" -t "$(gpu_sandbox_repotag)" --load sandbox/

test-sandbox:     ## lockdown + startup checks as UID 1000 (no GPU needed)
	SANDBOX_PORT=$(sandbox_port) SANDBOX_PATH=$(sandbox_path) SANDBOX_DOCKER_ARGS="$(sandbox_docker_args)" sandbox/test-sandbox.sh "$(sandbox_repotag)"

test-gpu-sandbox:
	SANDBOX_PORT=$(sandbox_port) SANDBOX_PATH=$(sandbox_path) SANDBOX_DOCKER_ARGS="$(sandbox_docker_args)" sandbox/test-sandbox.sh "$(gpu_sandbox_repotag)"

push-sandbox:
	docker push "$(sandbox_repotag)"

push-gpu-sandbox:
	docker push "$(gpu_sandbox_repotag)"

.PHONY: build-sandbox build-gpu-sandbox test-sandbox test-gpu-sandbox push-sandbox push-gpu-sandbox
