#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   ./resolve_deps.sh packages.txt
#
# packages.txt: lista de paquetes separados por espacios (o saltos de línea)

PKGFILE="$(realpath "${1:-packages.txt}")"
DEST="$(realpath "${2:-folder}")"

if [[ ! -f "$PKGFILE" ]]; then
    echo "ERROR: no se encuentra el archivo '$PKGFILE'" >&2
    exit 1
fi

# Leer paquetes iniciales (separamos por espacios / saltos de línea)
mapfile -t QUEUE < <(tr ' \t' '\n' < "$PKGFILE" | sed '/^$/d')

if [[ ${#QUEUE[@]} -eq 0 ]]; then
    echo "ERROR: no se han encontrado paquetes en '$PKGFILE'" >&2
    exit 1
fi

# Usamos un array asociativo para evitar duplicados
declare -A SEEN=()
FINAL=()

get_deps() {
    local pkg="$1"
    # Forzamos LC_ALL=C para que la salida de pacman esté en inglés
    LC_ALL=C pacman -Si "$pkg" 2>/dev/null | awk '
        /^Depends On\s*:/ {
            collecting=1
            # Eliminar el prefijo "Depends On :"
            sub(/^Depends On\s*:\s*/, "")
            if ($0 !~ /None/) print
            next
        }
        collecting && /^[[:space:]]/ {
            # Líneas continuadas de dependencias
            gsub(/^[[:space:]]+/, "")
            print
            next
        }
        collecting {
            # Cualquier otra línea corta la sección
            collecting=0
        }
    '
}

while ((${#QUEUE[@]} > 0)); do
    pkg="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")  # pop

    # Ya procesado
    if [[ -n "${SEEN[$pkg]:-}" ]]; then
        continue
    fi

    SEEN["$pkg"]=1
    FINAL+=("$pkg")

    # Obtener dependencias directas de este paquete
    deps_raw="$(get_deps "$pkg" || true)"

    [[ -z "$deps_raw" ]] && continue
    # Procesar cada token de dependencias
    for dep in $deps_raw; do
        # Quitar restricciones de versión
        dep="${dep%%[<>=]*}"
        # Quitar posibles dos puntos
        dep="${dep%%:*}"

        # Saltar tokens vacíos o "None"
        [[ -z "$dep" || "$dep" == "None" ]] && continue

        # Si aún no lo hemos visto, lo añadimos a la cola
        if [[ -z "${SEEN[$dep]:-}" ]]; then
            QUEUE+=("$dep")
        fi
    done
done

mkdir -p "${DEST}"

pacman -Syyww --noconfirm --overwrite --needed --asdeps \
    --cachedir ${DEST} $(cat "${PKGFILE}")
cd "${DEST}"
rm localrepo.* || true
repo-add localrepo.db.tar.gz ./*.pkg.tar.zst


