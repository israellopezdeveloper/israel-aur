#!/usr/bin/env bash

set -e

KEY_URL="https://israellopezdeveloper.github.io/israel-aur/israel-repo.asc"
BASE_DIR="$(dirname "$(realpath ${0})")"
GPG_DIR="$(realpath "${BASE_DIR}/airootfs/usr/share/pacman/keyrings")"
WORK_DIR="$(realpath "${BASE_DIR}/../work")"
OUT_DIR="$(realpath "${BASE_DIR}/../out")"
REPO_DIR="$(realpath "${BASE_DIR}/airootfs/opt/localrepo")"
REPO_SCRIPT="$(realpath "${REPO_DIR}/../deplist.sh")"
PACKAGES_LIST="$(realpath "${BASE_DIR}/packages.txt")"
USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"


SKIP_DOWNLOAD=false
if [[ "$1" == "--skip-download-packages" || "$1" == "-p" ]]; then
    SKIP_DOWNLOAD=true
fi


echo "Verificando paths"
echo "================="
mkdir -p "${WORK_DIR}"
mkdir -p "${OUT_DIR}"
mkdir -p "${GPG_DIR}"
mkdir -p "${REPO_DIR}"
chown 1000:1000 -R "${BASE_DIR}"
chown 1000:1000 -R "${OUT_DIR}"
chown 1000:1000 -R "${WORK_DIR}"
rm -rf "${WORK_DIR:?}"/*
rm -rf "${OUT_DIR:?}"/*
echo "👌 OK"


echo
echo "Añadiendo clave de 'israrepo'"
echo "============================="
curl -s -o "${GPG_DIR}/israel-repo.asc" "$KEY_URL"
gpg --dearmor "${GPG_DIR}/israel-repo.asc"
mv "${GPG_DIR}/israel-repo.asc.gpg" "${GPG_DIR}/israel-repo.gpg"
FPR=$(gpg --show-keys --with-colons "${GPG_DIR}/israel-repo.asc" \
      | awk -F: '/^fpr:/ {print $10; exit}')
echo "${FPR}:4:" > "${GPG_DIR}/israel-repo-trusted"
echo "👌 OK"


if [ "${SKIP_DOWNLOAD}" = false ]; then
  rm -rf "${REPO_DIR:?}"/*
  echo
  echo "Descargando paquetes"
  echo "===================="
  "${REPO_SCRIPT}" "${PACKAGES_LIST}" "${REPO_DIR}"
fi

MKSQUASHFS_OPTIONS="-processors 4" mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${BASE_DIR}"

chown 1000:1000 -R "${BASE_DIR}"
chown 1000:1000 -R "${OUT_DIR}"
chown 1000:1000 -R "${WORK_DIR}"
rm -rf "${WORK_DIR:?}"/*
sudo -u "#1000" mv "${OUT_DIR}/"*.iso "${HOME}/Descargas/archlinux.iso"
notify-send --urgency normal "Building ISO..." "Ya se ha creado la imagen" || true
