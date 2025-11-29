#!/usr/bin/env bash
set -euo pipefail

# Directorio donde está este script
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Asegurarse de que existen los directorios de trabajo/salida en el host
mkdir -p "${BASE_DIR}/out" "${BASE_DIR}/work"

# Imagen de Arch (con tag explícito mejor)
ARCH_IMAGE="archlinux:latest"

# Usa sudo si hace falta (en GitHub Actions seguro que sí)
DOCKER_BIN="${DOCKER_BIN:-podman}"

${DOCKER_BIN} run --rm \
  --privileged \
  -v "${BASE_DIR}/archiso:/archiso" \
  -v "${BASE_DIR}/out:/out" \
  -v "${BASE_DIR}/work:/work" \
  --cpus=10 \
  --memory=8g --memory-swap=8g \
  -e TARGET_UID="$(id -u)" \
  -e TARGET_GID="$(id -g)" \
  -w "/archiso" \
  "${ARCH_IMAGE}" \
  bash -lc '
    set -e
    pacman -Syu --noconfirm archiso curl gnupg squashfs-tools
    yes | pacman -Scc || true

    chmod +x ./build.sh
    ./build.sh
  '

