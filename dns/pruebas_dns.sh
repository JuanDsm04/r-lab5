#!/usr/bin/env bash
# dns/pruebas_dns.sh
# Pruebas automatizadas del DNS - Lab 5 CC3067 (zona restaurante.redes.test)
#
# Uso:
#   ./dns/pruebas_dns.sh                 # consulta a ns1.restaurante.redes.test
#   ./dns/pruebas_dns.sh 172.20.10.10    # consulta a otro servidor (IP o nombre)
#   sudo ./dns/pruebas_dns.sh            # en ns1: agrega validacion, puertos y logs
#
# Ejecuta DNS-01 a DNS-05 y la consulta NS. Si se corre en el propio ns1,
# agrega named-checkconf, named-checkzone, estado del servicio (INT-02),
# puertos (INT-03) y logs (INT-04).
# Guarda cada salida en evidencias/ y termina con codigo 0 solo si todo pasa.

set -u

# ---------- Configuracion (editar aqui si el grupo cambia algo) ----------
ZONA="restaurante.redes.test"
SERVIDOR="${1:-ns1.$ZONA}"
ARCHIVO_ZONA="/etc/bind/zones/db.$ZONA"

# Ultimo octeto acordado para cada host (tabla 3.2 del plan).
# Solo se compara el ultimo octeto, asi que no depende de la subred.
declare -A OCTETO=( [ns1]=10 [ldap]=11 [www]=12 [mail]=13 [ftp]=14 )
# --------------------------------------------------------------------------

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR_DNS="$RAIZ/evidencias/dns"
DIR_INT="$RAIZ/evidencias/integracion"
mkdir -p "$DIR_DNS" "$DIR_INT"

PASARON=0
FALLARON=0
SALIDA=""

if ! command -v dig >/dev/null 2>&1; then
    echo "Falta 'dig'. Instalar con: sudo apt install -y dnsutils"
    exit 2
fi

# ejecutar <archivo> <comando...>: corre el comando, guarda la evidencia
# con encabezado (host, fecha, comando) y deja la salida en $SALIDA.
ejecutar() {
    local archivo="$1"; shift
    SALIDA="$("$@" 2>&1)"
    {
        echo "# Host: $(hostname)   Fecha: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "\$ $*"
        echo "$SALIDA"
    } > "$archivo"
}

resultado() {   # resultado <ID> <0|1> <descripcion>
    if [ "$2" -eq 0 ]; then
        printf '[ OK  ] %-8s %s\n' "$1" "$3"
        PASARON=$((PASARON + 1))
    else
        printf '[FALLA] %-8s %s\n' "$1" "$3"
        FALLARON=$((FALLARON + 1))
    fi
}

octeto_correcto() {   # octeto_correcto <ip> <octeto esperado>
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.$2$ ]]
}

echo "Zona: $ZONA   Servidor consultado: $SERVIDOR   Desde: $(hostname)"
echo "------------------------------------------------------------------"

# Comprobacion previa: si el servidor no contesta, no tiene sentido seguir
# (evita esperar el tiempo de espera de dig en cada prueba).
if ! dig "@$SERVIDOR" "$ZONA" SOA +time=2 +tries=1 >/dev/null 2>&1; then
    echo "El servidor $SERVIDOR no responde consultas DNS."
    echo "Revisar: IP/nombre correcto, misma red, named activo y puerto 53 (ufw)."
    echo "Si el nombre ns1 no resuelve, pasar la IP: $0 <IP-de-ns1>"
    exit 2
fi

# ---------- DNS-01: resolucion del servidor DNS ----------
ejecutar "$DIR_DNS/DNS-01_dig_ns1.txt" dig "@$SERVIDOR" "ns1.$ZONA" A
ip="$(dig "@$SERVIDOR" "ns1.$ZONA" A +short 2>/dev/null | head -n 1)"
octeto_correcto "$ip" "${OCTETO[ns1]}"
resultado "DNS-01" $? "ns1.$ZONA -> ${ip:-sin respuesta}"

# ---------- DNS-02: resolucion de los servicios ----------
: > "$DIR_DNS/DNS-02_dig_servicios.txt"
estado=0
detalle=""
for h in ldap www mail ftp; do
    ejecutar "$DIR_DNS/.tmp" dig "@$SERVIDOR" "$h.$ZONA" A +noall +answer
    cat "$DIR_DNS/.tmp" >> "$DIR_DNS/DNS-02_dig_servicios.txt"
    echo >> "$DIR_DNS/DNS-02_dig_servicios.txt"
    ip="$(dig "@$SERVIDOR" "$h.$ZONA" A +short 2>/dev/null | head -n 1)"
    octeto_correcto "$ip" "${OCTETO[$h]}" || estado=1
    detalle+="$h=${ip:-?} "
done
rm -f "$DIR_DNS/.tmp"
resultado "DNS-02" $estado "$detalle"

# ---------- DNS-03: respuesta autoritativa (SOA con flag aa) ----------
ejecutar "$DIR_DNS/DNS-03_dig_soa.txt" dig "@$SERVIDOR" "$ZONA" SOA +norecurse
estado=0
grep -q 'status: NOERROR' <<< "$SALIDA" || estado=1
grep -E '^;; flags:' <<< "$SALIDA" | grep -qw 'aa' || estado=1
grep -qE "IN[[:space:]]+SOA[[:space:]]+ns1\.$ZONA\." <<< "$SALIDA" || estado=1
serial="$(dig "@$SERVIDOR" "$ZONA" SOA +short 2>/dev/null | awk '{print $3}')"
resultado "DNS-03" $estado "SOA autoritativo (flag aa), serial ${serial:-?}"

# ---------- DNS-04: registro MX ----------
ejecutar "$DIR_DNS/DNS-04_dig_mx.txt" dig "@$SERVIDOR" "$ZONA" MX
mx="$(dig "@$SERVIDOR" "$ZONA" MX +short 2>/dev/null | head -n 1)"
[[ "$mx" =~ ^[0-9]+[[:space:]]mail\.$ZONA\.$ ]]
resultado "DNS-04" $? "MX -> ${mx:-sin respuesta}"

# ---------- Registro NS (lo pide el Ejercicio 1) ----------
ejecutar "$DIR_DNS/DNS-NS_dig_ns.txt" dig "@$SERVIDOR" "$ZONA" NS
ns="$(dig "@$SERVIDOR" "$ZONA" NS +short 2>/dev/null | head -n 1)"
[ "$ns" = "ns1.$ZONA." ]
resultado "DNS-NS" $? "NS -> ${ns:-sin respuesta}"

# ---------- DNS-05: nombre inexistente ----------
ejecutar "$DIR_DNS/DNS-05_dig_nxdomain.txt" dig "@$SERVIDOR" "noexiste.$ZONA" A
grep -q 'status: NXDOMAIN' <<< "$SALIDA"
resultado "DNS-05" $? "noexiste.$ZONA -> NXDOMAIN"

# ---------- Pruebas locales: solo si este equipo es el servidor BIND ----------
if command -v named-checkzone >/dev/null 2>&1 && [ -f "$ARCHIVO_ZONA" ]; then
    echo "------------------------------------------------------------------"
    echo "Servidor BIND detectado en este equipo: pruebas locales"

    ejecutar "$DIR_DNS/DNS-CHK_named-checkconf.txt" named-checkconf
    [ -z "$SALIDA" ]
    resultado "CHECKCONF" $? "named-checkconf sin errores"

    ejecutar "$DIR_DNS/DNS-CHK_named-checkzone.txt" named-checkzone "$ZONA" "$ARCHIVO_ZONA"
    grep -qx 'OK' <<< "$SALIDA"
    resultado "CHECKZONE" $? "named-checkzone OK"

    # INT-02: el servicio esta activo y habilitado al arranque
    ejecutar "$DIR_INT/INT-02_dns_systemctl_named.txt" systemctl status named --no-pager
    estado=0
    systemctl is-active --quiet named 2>/dev/null || estado=1
    systemctl is-enabled --quiet named 2>/dev/null || estado=1
    resultado "INT-02" $estado "named activo y habilitado (enable)"

    # INT-03: puerto 53 en udp y tcp
    ejecutar "$DIR_INT/INT-03_dns_ss_puertos.txt" ss -lntup
    estado=0
    grep -E '^udp' <<< "$SALIDA" | grep -qE ':53[[:space:]]' || estado=1
    grep -E '^tcp' <<< "$SALIDA" | grep -qE ':53[[:space:]]' || estado=1
    resultado "INT-03" $estado "puerto 53 escuchando en udp y tcp"

    # INT-04: extracto de logs (solo se guarda, no se evalua)
    ejecutar "$DIR_INT/INT-04_dns_logs_named.txt" journalctl -u named --since today --no-pager -n 60
    echo "[ INFO] INT-04   logs de named guardados (usar sudo si salen vacios)"
fi

# Si se corrio con sudo, devolver los archivos al usuario normal
# para que git no encuentre evidencias propiedad de root.
if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER": "$RAIZ/evidencias" 2>/dev/null
fi

echo "------------------------------------------------------------------"
echo "Pasaron: $PASARON   Fallaron: $FALLARON"
echo "Evidencias en: $DIR_DNS"
[ -d "$DIR_INT" ] && echo "               $DIR_INT"
[ "$FALLARON" -eq 0 ]
