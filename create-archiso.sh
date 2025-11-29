#!/usr/bin/env bash
set -euo pipefail

# Directorio donde está este script
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Asegurarse de que existen los directorios de trabajo/salida en el host
mkdir -p "${BASE_DIR}/out" "${BASE_DIR}/work"

# Imagen de Arch (con tag explícito mejor)
ARCH_IMAGE="archlinux:latest"

# Usa sudo si hace falta (en GitHub Actions seguro que sí)
DOCKER_BIN="${DOCKER_BIN:-sudo podman}"

${DOCKER_BIN} run -it --rm \
  --privileged \
  --cap-add=SYS_ADMIN \
  --cap-add=SYS_CHROOT \
  --cap-add=MKNOD \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --tmpfs /run \
  --tmpfs /tmp \
  -v /dev:/dev \
  -v "${BASE_DIR}/archiso:/archiso" \
  -v "${BASE_DIR}/out:/out" \
  -v "${BASE_DIR}/work:/work" \
  --cpus=3 \
  --memory=8g --memory-swap=8g \
  -e TARGET_UID="$(id -u)" \
  -e TARGET_GID="$(id -g)" \
  -w "/archiso" \
  "${ARCH_IMAGE}" \
  bash -lc '
    set -e
    pacman -Syu --noconfirm archiso curl gnupg squashfs-tools > /dev/null 2>&1
    yes | pacman -Scc > /dev/null 2>&1 || true

    chmod +x ./build.sh
    ./build.sh
  '

