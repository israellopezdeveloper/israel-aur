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

echo "  - Listando paquetes"
DOWNLOADED_PACKAGES=$(ls -l /archiso/airootfs/opt/localrepo/ | wc -l)
while ((${#QUEUE[@]} > 0)); do
    echo -en "\r                           \r"
    echo -n "SEEN: ${#SEEN[@]}/${DOWNLOADED_PACKAGES}"
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

echo
echo "  - Descargando paquetes"
MAX_PACMAN_RETRIES=6
PACMAN_RETRIES_COUNT=0
while [ $PACMAN_RETRIES_COUNT -lt $MAX_PACMAN_RETRIES ]; do
    PACMAN_RETRIES_COUNT=$((PACMAN_RETRIES_COUNT + 1))
    URL="https://kogaslife.duckdns.org/israrepo/x86_64/"
    MAX_RETRIES=6
    RETRY_COUNT=0
    SLEEP_TIME=2
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "${URL}")
        if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
            break
        else
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                sleep $SLEEP_TIME
            else
                echo "ERROR: No se pudo conectar con ${URL}"
                exit 1
            fi
        fi
    done

    pacman -Syyww --noconfirm --overwrite --needed --asdeps \
        --cachedir "${DEST}" \
        $(cat "${PKGFILE}") > /dev/null 2>&1 \
        && { break; } \
        || { \
          if [ $PACMAN_RETRIES_COUNT -lt $MAX_PACMAN_RETRIES ]; then \
              sleep $SLEEP_TIME; \
          else \
              echo "ERROR: No se pudo descargar los paquetes"; \
              exit 1; \
          fi; \
        }
done
cd "${DEST}"
rm localrepo.* || true
echo "  - Creando base de datos del repo"
repo-add localrepo.db.tar.gz ./*.pkg.tar.zst > /dev/null 2>&1
echo "👌 OK"


