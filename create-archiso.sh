#!/usr/bin/env bash

BASE_DIR="$(dirname "$(realpath "${0}")")"

podman run --rm \
  --privileged \
  -v "${BASE_DIR}/archiso:/archiso" \
  -v "${BASE_DIR}/out:/out" \
  -v "${BASE_DIR}/work:/work" \
  --cpus=10 \
  --memory=8g --memory-swap=8g \
  -e TARGET_UID="$(id -u)" \
  -e TARGET_GID="$(id -g)" \
  -w "/archiso" \
  archlinux \
  ./build.sh

rm -rf iso/*.iso
mv out/*.iso iso/isra-archlinux.iso >/dev/null 2>&1
