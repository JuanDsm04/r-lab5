#!/usr/bin/env bash
# Ejecuta las pruebas FTP-01 a FTP-08 desde una máquina cliente Linux.
# Uso: bash ftp/pruebas/verificar.sh
#
# Variables opcionales:
#   HOST         Servidor FTP (por defecto ftp.restaurante.redes.test).
#   FTP_USER     Usuario FTP (por defecto ftpuser).
#   FTP_PASS     Contraseña. Si no se define, se solicita al ejecutar.
#   OUT          Carpeta de evidencias (por defecto evidencias/ftp/cliente).
#   MODO_ACTIVO  Si vale 1, agrega una prueba en modo activo.
#
# Requiere curl y dig. La salida de cada prueba se guarda en OUT sin la contraseña.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
HOST="${HOST:-ftp.restaurante.redes.test}"
FTP_USER="${FTP_USER:-ftpuser}"
OUT="${OUT:-$REPO/evidencias/ftp/cliente}"
PASV_MIN=40000
PASV_MAX=40100
MENU_LOCAL="$REPO/ftp/archivos/menu-restaurante.txt"

for c in curl dig sha256sum; do
    command -v "$c" >/dev/null || { echo "Falta el comando '$c'. Instálelo con: sudo apt install curl bind9-dnsutils"; exit 1; }
done
if [ -z "${FTP_PASS:-}" ]; then
    read -rsp "Ingrese la contraseña de ${FTP_USER}: " FTP_PASS; echo
fi

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL="ftp://${HOST}"
CRED="${FTP_USER}:${FTP_PASS}"
declare -a RESUMEN=()

# Ejecuta un comando y guarda su salida, sin la contraseña, en un archivo de evidencia.
# Uso: evidencia <archivo> <descripción> <comando...>
evidencia() {
    local archivo="$OUT/$1" desc="$2"; shift 2
    local mostrado="${*//"$FTP_PASS"/********}"
    {
        echo "# ${desc}"
        echo "# Fecha:    $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "# Cliente:  $(hostname) ($(hostname -I 2>/dev/null | awk '{print $1}'))"
        echo "# Servidor: ${HOST}"
        echo "# Comando:  ${mostrado}"
        echo
    } > "$archivo"
    "$@" > "$TMP/crudo" 2>&1
    local rc=$?
    local linea
    while IFS= read -r linea || [ -n "$linea" ]; do
        printf '%s\n' "${linea//"$FTP_PASS"/********}"
    done < "$TMP/crudo" > "$TMP/ultima"
    cat "$TMP/ultima" >> "$archivo"
    printf '\n# Código de salida: %s\n' "$rc" >> "$archivo"
    return 0
}

# Registra y muestra el resultado de una prueba.
# Uso: resultado <ID> <ok|fallo|omitida> <texto>
resultado() {
    local id="$1" estado="$2" texto="$3" marca
    case "$estado" in
        ok)    marca=$'\033[32mOK     \033[0m' ;;
        fallo) marca=$'\033[31mFALLO  \033[0m' ;;
        *)     marca=$'\033[33mOMITIDA\033[0m' ;;
    esac
    RESUMEN+=("$(printf '%-7s %s %s' "$id" "$marca" "$texto")")
    printf '%-7s %s %s\n' "$id" "$marca" "$texto"
}

tiene() { grep -qE "$1" "$TMP/ultima"; }

# Calcula el puerto anunciado en la respuesta 227 (p1*256+p2).
puerto_pasivo() {
    grep -oE '227 Entering Passive Mode \([0-9,]+\)' "$TMP/ultima" | head -1 \
        | grep -oE '[0-9]+,[0-9]+\)' | tr -d ')' | awk -F, '{print $1*256+$2}'
}

echo "Servidor: ${URL}  Usuario: ${FTP_USER}"
echo "Evidencias: ${OUT}"
echo

# -v muestra el diálogo FTP; --disable-epsv fuerza PASV para mostrar IP y puerto.
OPC=(-sS -v --disable-epsv --connect-timeout 10 --max-time 60)
CURL=(curl "${OPC[@]}")

# FTP-01: resolución DNS.
if [[ "$HOST" =~ ^[0-9.]+$ ]]; then
    resultado FTP-01 omitida "Se usó una IP. Debe repetirse con el FQDN."
else
    evidencia "FTP-01_resolucion_dns.txt" "FTP-01 Resolución de ${HOST}" dig "$HOST"
    IP_DNS="$(dig +short "$HOST" A | tail -1)"
    if [ -n "$IP_DNS" ] && tiene "status: NOERROR"; then
        resultado FTP-01 ok "${HOST} resuelve a ${IP_DNS}."
    else
        resultado FTP-01 fallo "${HOST} no resuelve. Verifique que el cliente use ns1 como DNS."
    fi
fi

# FTP-02: autenticación válida y cierre de sesión.
evidencia "FTP-02_autenticacion_valida.txt" "FTP-02 Autenticación con usuario autorizado y cierre de sesión" \
    "${CURL[@]}" --user "$CRED" "$URL/" -o /dev/null -Q "-QUIT"
if tiene '^< 230' && tiene '^< 221'; then
    resultado FTP-02 ok "230 Login successful. QUIT respondido con 221 Goodbye."
else
    resultado FTP-02 fallo "No se recibieron las respuestas 230 y 221."
fi

# FTP-03: contraseña incorrecta.
evidencia "FTP-03_autenticacion_invalida.txt" "FTP-03 Autenticación con contraseña incorrecta" \
    "${CURL[@]}" --user "${FTP_USER}:contrasena-incorrecta-lab5" "$URL/" -o /dev/null
if tiene '^< 530'; then resultado FTP-03 ok "530 Login incorrect."
else resultado FTP-03 fallo "El acceso no fue rechazado con 530."; fi

# FTP-04: acceso anónimo.
evidencia "FTP-04_acceso_anonimo.txt" "FTP-04 Intento de acceso anónimo" \
    "${CURL[@]}" --user "anonymous:invitado@restaurante.redes.test" "$URL/" -o /dev/null
if tiene '^< 530' && ! tiene '^< 230'; then resultado FTP-04 ok "Acceso anónimo rechazado con 530."
else resultado FTP-04 fallo "El acceso anónimo no fue rechazado."; fi

# FTP-05: listado de directorio.
evidencia "FTP-05_listado_directorio.txt" "FTP-05 Listado de la raíz y de publico/ en modo pasivo" \
    bash -c '"$@"' _ "${CURL[@]}" --user "$CRED" "$URL/" "$URL/publico/"
P="$(puerto_pasivo)"
if [ -n "$P" ]; then
    echo "# Puerto de datos anunciado en la respuesta 227: ${P} (rango ${PASV_MIN}-${PASV_MAX})." \
        >> "$OUT/FTP-05_listado_directorio.txt"
fi
if tiene 'publico' && tiene 'subidas' && tiene 'menu-restaurante.txt'; then
    resultado FTP-05 ok "Se listan publico/, subidas/ y menu-restaurante.txt."
else
    resultado FTP-05 fallo "El listado no muestra el contenido esperado."
fi
if [ -n "$P" ] && [ "$P" -ge "$PASV_MIN" ] && [ "$P" -le "$PASV_MAX" ]; then
    resultado PASV ok "Puerto de datos ${P}, dentro del rango ${PASV_MIN}-${PASV_MAX}."
else
    resultado PASV fallo "Puerto pasivo '${P}' fuera del rango o no detectado."
fi

# FTP-06: carga de archivo.
PRUEBA="prueba-$(hostname)-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "Archivo de prueba FTP-06/FTP-07 - Laboratorio 5 CC3067"
    echo "Generado en $(hostname) el $(date)"
    head -c 4096 /dev/urandom | base64
} > "$TMP/$PRUEBA"
SHA_ORIG="$(sha256sum "$TMP/$PRUEBA" | cut -d' ' -f1)"
cp "$TMP/$PRUEBA" "$OUT/$PRUEBA"
evidencia "FTP-06_carga_archivo.txt" "FTP-06 Carga de ${PRUEBA} en subidas/ y listado posterior" \
    bash -c '"$@"' _ "${CURL[@]}" --user "$CRED" -T "$TMP/$PRUEBA" "$URL/subidas/" \
    --next "${OPC[@]}" --user "$CRED" "$URL/subidas/"
echo "# SHA-256 del archivo local: ${SHA_ORIG}" >> "$OUT/FTP-06_carga_archivo.txt"
if tiene '^< 226' && tiene "$PRUEBA"; then resultado FTP-06 ok "${PRUEBA} cargado (226) y visible en subidas/."
else resultado FTP-06 fallo "La carga no se completó."; fi

# FTP-07: descarga sin alteraciones.
evidencia "FTP-07_descarga_archivo.txt" "FTP-07 Descarga del archivo cargado y de publico/menu-restaurante.txt" \
    bash -c '"$@"' _ "${CURL[@]}" --user "$CRED" "$URL/subidas/$PRUEBA" -o "$TMP/descargado-$PRUEBA" \
    --next "${OPC[@]}" --user "$CRED" "$URL/publico/menu-restaurante.txt" -o "$TMP/menu-restaurante.txt"
SHA_DESC="$(sha256sum "$TMP/descargado-$PRUEBA" 2>/dev/null | cut -d' ' -f1)"
SHA_MENU="$(sha256sum "$TMP/menu-restaurante.txt" 2>/dev/null | cut -d' ' -f1)"
SHA_MENU_REPO=""
[ -f "$MENU_LOCAL" ] && SHA_MENU_REPO="$(sha256sum "$MENU_LOCAL" | cut -d' ' -f1)"
cp "$TMP/menu-restaurante.txt" "$OUT/descargado-menu-restaurante.txt" 2>/dev/null || true
{
    echo
    echo "# Comparación SHA-256"
    echo "# ${PRUEBA}"
    echo "#   Original:   ${SHA_ORIG}"
    echo "#   Descargado: ${SHA_DESC:-no descargado}"
    echo "# menu-restaurante.txt"
    echo "#   Repositorio: ${SHA_MENU_REPO:-no disponible}"
    echo "#   Descargado:  ${SHA_MENU:-no descargado}"
} >> "$OUT/FTP-07_descarga_archivo.txt"
if [ -n "$SHA_DESC" ] && [ "$SHA_DESC" = "$SHA_ORIG" ]; then
    if [ -z "$SHA_MENU_REPO" ] || [ "$SHA_MENU" = "$SHA_MENU_REPO" ]; then
        resultado FTP-07 ok "Los hashes SHA-256 coinciden."
    else
        resultado FTP-07 fallo "menu-restaurante.txt no coincide con la copia del repositorio."
    fi
else
    resultado FTP-07 fallo "El archivo descargado no coincide con el original."
fi

# FTP-08: restricción de directorios.
evidencia "FTP-08_restriccion_directorios.txt" "FTP-08 Intentos de acceso fuera del directorio autorizado" \
    env U="$URL" F="$TMP/$PRUEBA" bash -c '
        echo "a) Cambio a /etc"
        "$@" -Q "CWD /etc" "$U/"
        echo; echo "b) Cambio a ../../.. y consulta del directorio actual"
        "$@" -Q "CWD ../../.." -Q "PWD" "$U/"
        echo; echo "c) Descarga de /etc/passwd"
        "$@" "$U/%2Fetc/passwd" -o /dev/null
        echo; echo "d) Carga de un archivo en publico/"
        "$@" -T "$F" "$U/publico/"
    ' _ "${CURL[@]}" --user "$CRED"
FTP08_OK=1
grep -A40 '^a) ' "$TMP/ultima" | grep -m1 -qE '^< 550' || FTP08_OK=0
grep -A40 '^b) ' "$TMP/ultima" | grep -m1 -qE '^< 257 "/"' || FTP08_OK=0
grep -A40 '^c) ' "$TMP/ultima" | grep -m1 -qE '^< 550' || FTP08_OK=0
grep -A40 '^d) ' "$TMP/ultima" | grep -m1 -qE '^< 553' || FTP08_OK=0
if [ "$FTP08_OK" = 1 ]; then
    resultado FTP-08 ok "/etc: 550. ../../..: permanece en /. /etc/passwd: 550. publico/: 553."
else
    resultado FTP-08 fallo "Alguna restricción no se cumplió. Revise FTP-08_restriccion_directorios.txt."
fi

# Prueba opcional en modo activo.
if [ -n "${MODO_ACTIVO:-}" ]; then
    evidencia "EXTRA_modo_activo.txt" "Listado en modo activo (PORT)" \
        curl -sS -v --ftp-port - --no-eprt --connect-timeout 10 --max-time 30 --user "$CRED" "$URL/"
    if tiene '^< 200 PORT' && tiene '^< 226'; then resultado ACTIVO ok "PORT aceptado y listado completo."
    else resultado ACTIVO fallo "Falló. Puede deberse al firewall del cliente."; fi
fi

# Resumen.
{
    echo "Resumen de pruebas FTP, $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Servidor: ${HOST}"
    echo "Cliente:  $(hostname)"
    echo
    printf '%s\n' "${RESUMEN[@]}" | sed 's/\x1b\[[0-9;]*m//g'
} > "$OUT/RESUMEN.txt"
echo
echo "Resumen guardado en $OUT/RESUMEN.txt"
grep -q 'FALLO' "$OUT/RESUMEN.txt" && exit 1 || exit 0
