#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-kirawursthorn/gdrnpp_bop2022:v6.1}"
CONTAINER_NAME="${CONTAINER_NAME:-gdrnpp_bop2022}"
HOST_HOME="${HOST_HOME:-/home/robot}"
WORKDIR="${WORKDIR:-/home/robot/Projects/gdrnpp_bop2022}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XAUTH_HOST="${XAUTH_HOST:-${SCRIPT_DIR}/.docker/.docker.xauth}"
XAUTH_CONTAINER="${XAUTH_CONTAINER:-/tmp/.docker.xauth}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found" >&2
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  echo "Container '${CONTAINER_NAME}' already exists."

  EXISTING_XAUTH_HOST="$(
    docker inspect \
      --format "{{range .Mounts}}{{if eq .Destination \"${XAUTH_CONTAINER}\"}}{{.Source}}{{end}}{{end}}" \
      "${CONTAINER_NAME}" 2>/dev/null || true
  )"
  if [ -n "${EXISTING_XAUTH_HOST}" ]; then
    "${SCRIPT_DIR}/scripts/prepare_docker_xauth.sh" "${EXISTING_XAUTH_HOST}"
  else
    echo "No ${XAUTH_CONTAINER} bind mount found on existing container." >&2
  fi

  if [ "$(docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}")" = "true" ]; then
    echo "Entering running container '${CONTAINER_NAME}'..."
    exec docker exec -it "${CONTAINER_NAME}" /bin/bash
  fi

  echo "Starting container '${CONTAINER_NAME}'..."
  exec docker start -ai "${CONTAINER_NAME}"
fi

if [ ! -d "${HOST_HOME}" ]; then
  echo "Host directory does not exist: ${HOST_HOME}" >&2
  exit 1
fi

"${SCRIPT_DIR}/scripts/prepare_docker_xauth.sh" "${XAUTH_HOST}"

echo "Creating container '${CONTAINER_NAME}' from '${IMAGE}'..."
echo "Host home mounted as ${HOST_HOME}:${HOST_HOME}"
echo "Xauthority mounted as ${XAUTH_HOST}:${XAUTH_CONTAINER}"
echo "If X11 apps cannot open, run on host: xhost +SI:localuser:root"

docker run -it \
  --name "${CONTAINER_NAME}" \
  --gpus all \
  --ipc=host \
  --network=host \
  --privileged \
  -e DISPLAY="${DISPLAY:-:0}" \
  -e QT_X11_NO_MITSHM=1 \
  -e XAUTHORITY="${XAUTH_CONTAINER}" \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v "${XAUTH_HOST}:${XAUTH_CONTAINER}:rw" \
  -v "${HOST_HOME}:${HOST_HOME}:rw" \
  -w "${WORKDIR}" \
  "${IMAGE}" \
  /bin/bash
