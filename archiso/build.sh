#!/usr/bin/env bash

set -e

KEY_URL="https://israellopezdeveloper.github.io/israel-aur/israel-repo.asc"
BASE_DIR="$(dirname "$(realpath ${0})")"
ARCHISO_PACMAN="$(realpath "${BASE_DIR}/pacman.conf")"
GPG_DIR="$(realpath "${BASE_DIR}/airootfs/usr/share/pacman/keyrings")"
WORK_DIR="$(realpath "${BASE_DIR}/../work")"
OUT_DIR="$(realpath "${BASE_DIR}/../out")"
REPO_DIR="$(realpath "${BASE_DIR}/airootfs/opt/localrepo")"
mkdir -p "${REPO_DIR}"
REPO_SCRIPT="$(realpath "${REPO_DIR}/../deplist.sh")"
PACKAGES_LIST="$(realpath "${BASE_DIR}/packages.txt")"
SYSTEM_PACMAN_CONF="/etc/pacman.conf"
PACMAN_BACKUP=""


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
rm -rf "${WORK_DIR:?}"/*
rm -rf "${OUT_DIR:?}"/*
sed "s&__WORKING_DIRECTORY__&${BASE_DIR}&" "${ARCHISO_PACMAN}.bak" > "${ARCHISO_PACMAN}"
echo "👌 OK"

echo "."
echo "Preparando pacman local"
echo "======================="
curl -s -o "${GPG_DIR}/israel-repo.asc" "$KEY_URL"
gpg --dearmor "${GPG_DIR}/israel-repo.asc"
mv "${GPG_DIR}/israel-repo.asc.gpg" "${GPG_DIR}/israel-repo.gpg"
FPR=$(gpg --show-keys --with-colons "${GPG_DIR}/israel-repo.asc" \
      | awk -F: '/^fpr:/ {print $10; exit}')
echo "${FPR}:4:" > "${GPG_DIR}/israel-repo-trusted"

restore_pacman_conf() {
  if [[ -n "${PACMAN_BACKUP}" && -f "${PACMAN_BACKUP}" ]]; then
    echo
    echo "Restaurando /etc/pacman.conf original"
    echo "====================================="
    cp "${PACMAN_BACKUP}" "${SYSTEM_PACMAN_CONF}"
    rm -f "${PACMAN_BACKUP}"
  fi
  chown -R ${TARGET_UID}:${TARGET_GID} "${BASE_DIR}"
}

trap restore_pacman_conf EXIT

enable_multilib() {
  local conf="${SYSTEM_PACMAN_CONF}"

  if grep -q '^\[multilib\]' "${conf}"; then
    echo "multilib ya está habilitado."
    return
  fi

  if grep -q '^[[:space:]]*#[[:space:]]*\[multilib\]' "${conf}"; then
    echo "Descomentando repositorio multilib..."
    # Descomenta la cabecera [multilib]
    sed -i 's/^[[:space:]]*#[[:space:]]*\[multilib\]/[multilib]/' "${conf}"
    # Descomenta el Include dentro del bloque multilib hasta la siguiente línea vacía
    sed -i '/^\[multilib\]/,/^$/ s/^[[:space:]]*#[[:space:]]*Include/Include/' "${conf}"
  else
    echo "Añadiendo repositorio multilib al final de pacman.conf..."
    cat <<'EOF' >> "${conf}"

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  fi
}

ensure_repo() {
  local name="$1"
  local server_url="$2"
  local conf="${SYSTEM_PACMAN_CONF}"

  if grep -q "^\[${name}\]" "${conf}"; then
    echo "Repositorio ${name} ya está habilitado."
    return
  fi

  if grep -q "^[[:space:]]*#[[:space:]]*\[${name}\]" "${conf}"; then
    echo "Descomentando repositorio ${name}..."
    sed -i "s/^[[:space:]]*#[[:space:]]*\[${name}\]/[${name}]/" "${conf}"
    # Descomentar líneas de Server dentro del bloque del repo hasta línea vacía
    sed -i "/^\[${name}\]/,/^$/ s/^[[:space:]]*#[[:space:]]*Server/Server/" "${conf}"
  else
    echo "Añadiendo repositorio ${name} al final de pacman.conf..."
    cat <<EOF >> "${conf}"

[${name}]
Server = ${server_url}
EOF
  fi
}

if [[ -f "${SYSTEM_PACMAN_CONF}" ]]; then
  PACMAN_BACKUP="$(mktemp /tmp/pacman.conf.backup.XXXXXX)"
  cp "${SYSTEM_PACMAN_CONF}" "${PACMAN_BACKUP}"
else
  echo "❌ No se encontró ${SYSTEM_PACMAN_CONF}. Abortando."
  exit 1
fi
sed -i 's/[\#]*Color/Color\nILoveCandy/' "${SYSTEM_PACMAN_CONF}"
sed -i 's/[\#]*NoProgressBar/#NoProgressBar/' "${SYSTEM_PACMAN_CONF}"
sed -i 's/[\#]*VerbosePkgLists/#VerbosePkgLists/' "${SYSTEM_PACMAN_CONF}"
sed -i 's/[\#]*ParallelDownloads.*/ParallelDownloads = 2/' "${SYSTEM_PACMAN_CONF}"
sed -i 's/[\#]*DownloadUser.*/#DownloadUser = alpm/' "${SYSTEM_PACMAN_CONF}"
sed -i 's/[\#]*DisableSandbox/#DisableSandbox/' "${SYSTEM_PACMAN_CONF}"
enable_multilib
ensure_repo "israrepo"   "https://israellopezdeveloper.github.io/israel-aur/\$arch"
ensure_repo "israbigrepo" "https://kogaslife.duckdns.org/israrepo/\$arch"
echo "Inicializando keyring de pacman..."
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux >/dev/null 2>&1
if ! pacman-key --list-keys "${FPR}" >/dev/null 2>&1; then
  echo "Añadiendo clave israel-repo al keyring local..."
  pacman-key --add "${GPG_DIR}/israel-repo.asc" >/dev/null 2>&1
fi
pacman-key --lsign-key "${FPR}" >/dev/null 2>&1
echo "👌 OK"


if [ "${SKIP_DOWNLOAD}" = false ]; then
  rm -rf "${REPO_DIR:?}"/*
  echo "."
  echo "Descargando paquetes"
  echo "===================="
  pacman -Syyu --noconfirm gnupg gpgme archlinux-keyring
  rm -rf /etc/pacman.d/gnupg
  pacman-key --init
  pacman-key --populate archlinux
  pacman -Syyu --noconfirm archiso
  "${REPO_SCRIPT}" "${PACKAGES_LIST}" "${REPO_DIR}"
fi

MKSQUASHFS_OPTIONS="-processors 4" mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${BASE_DIR}"

rm -rf "${WORK_DIR:?}"/*
rm -rf "${ARCHISO_PACMAN}"
chown -R ${TARGET_UID}:${TARGET_GID} "${OUT_DIR}"
