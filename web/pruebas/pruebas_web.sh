#!/usr/bin/env bash
# Pruebas WEB-01 a WEB-05 (e INT-02/03/04 si se corre en el servidor web).
# Indica cuales pasan y guarda la salida de cada comando en evidencias/web/.
# La contrasena NUNCA se escribe en las evidencias.
#
# Uso (desde la raiz del repositorio):
#   ./web/pruebas/pruebas_web.sh <usuario> '<password>'             # desde un cliente
#   ./web/pruebas/pruebas_web.sh <usuario> '<password>' <ip_ns1>    # si el equipo aun no usa ns1 como DNS
#   sudo ./web/pruebas/pruebas_web.sh <usuario> '<password>'        # en el servidor web: agrega INT-02/03/04
#
# WEB-05 (con slapd detenido en el servidor LDAP):
#   ./web/pruebas/pruebas_web.sh <usuario> '<password>' --ldap-detenido
#
# Codigo de salida: 0 si todo pasa, 1 si alguna prueba falla, 2 si faltan datos o curl.
set -uo pipefail

DOMINIO="restaurante.redes.test"
FQDN="www.${DOMINIO}"
URL="http://${FQDN}"
OCTETO=12

MODO="normal"; POS=()
for a in "$@"; do
    case "$a" in
        --ldap-detenido) MODO="ldap-detenido" ;;
        *) POS+=("$a") ;;
    esac
done
USUARIO="${POS[0]:-}"; PASS="${POS[1]:-}"; NS="${POS[2]:-}"

if [ -z "$USUARIO" ] || [ -z "$PASS" ]; then
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
command -v curl >/dev/null || { echo "Falta curl: sudo apt install -y curl"; exit 2; }
command -v dig  >/dev/null || { echo "Falta dig: sudo apt install -y bind9-dnsutils"; exit 2; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${REPO}/evidencias/web"
mkdir -p "$OUT"

PASA=0; FALLA=0
ok()   { printf '[ OK  ] %-8s %s\n' "$1" "$2"; PASA=$((PASA+1)); }
fail() { printf '[FALLA] %-8s %s\n' "$1" "$2"; FALLA=$((FALLA+1)); }

# evid <archivo> <comando mostrado> <salida>
evid() {
    {
        echo "# Host:    $(hostname)"
        echo "# Fecha:   $(date '+%F %T %Z')"
        echo "# Comando: $2"
        echo
        printf '%s\n' "$3"
    } > "${OUT}/$1"
}

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" 2>/dev/null || true; }
http_full() { curl -sS -i --max-time 10 "$@" 2>&1 | head -n 25; }

echo "Sitio: ${URL}   Usuario de prueba: ${USUARIO}   Desde: $(hostname)"
echo "------------------------------------------------------------------"

# ---------------------------------------------------------------- WEB-05
if [ "$MODO" = "ldap-detenido" ]; then
    CODE=$(http_code -u "${USUARIO}:${PASS}" "${URL}/privado/")
    SALIDA=$(http_full -u "${USUARIO}:${PASS}" "${URL}/privado/")
    evid "WEB-05_ldap_detenido.txt" "curl -i -u ${USUARIO}:******** ${URL}/privado/   (slapd detenido)" "$SALIDA"
    if [ "$CODE" != "200" ]; then
        ok "WEB-05" "con LDAP detenido el acceso NO se concede (HTTP ${CODE})"
    else
        fail "WEB-05" "con LDAP detenido el servidor dio 200: revisar que slapd este detenido"
    fi
    if [ -r /var/log/apache2/restaurante_error.log ]; then
        LOG=$(tail -n 20 /var/log/apache2/restaurante_error.log)
        evid "WEB-05_log_apache_error.txt" "tail -n 20 /var/log/apache2/restaurante_error.log" "$LOG"
        echo "         log de Apache guardado en WEB-05_log_apache_error.txt"
    else
        echo "         Para el log de Apache, correr en el servidor web:"
        echo "         sudo tail -n 20 /var/log/apache2/restaurante_error.log"
    fi
    echo "------------------------------------------------------------------"
    echo "Recordatorio: volver a iniciar slapd en el servidor LDAP (sudo systemctl start slapd)."
    echo "Pasaron: ${PASA}   Fallaron: ${FALLA}"
    [ "$FALLA" -eq 0 ] && exit 0 || exit 1
fi

# ---------------------------------------------------------------- WEB-01
if [ -n "$NS" ]; then
    CMD="dig @${NS} ${FQDN} A"; COMPLETO=$(dig @"$NS" "$FQDN" A 2>&1); R=$(dig +short @"$NS" "$FQDN" A | tail -1)
else
    CMD="dig ${FQDN} A";        COMPLETO=$(dig "$FQDN" A 2>&1);        R=$(dig +short "$FQDN" A | tail -1)
fi
evid "WEB-01_dig_www.txt" "$CMD" "$COMPLETO"
if [[ "$R" == *".${OCTETO}" ]]; then
    ok "WEB-01" "${FQDN} -> ${R}"
else
    fail "WEB-01" "${FQDN} -> '${R:-sin respuesta}' (se esperaba una IP terminada en .${OCTETO})"
fi

# ---------------------------------------------------------------- WEB-02
CODE=$(http_code "${URL}/")
evid "WEB-02_pagina_principal.txt" "curl -i ${URL}/" "$(http_full "${URL}/")"
if [ "$CODE" = "200" ]; then ok "WEB-02" "pagina principal HTTP 200"; else fail "WEB-02" "HTTP ${CODE} (esperado 200)"; fi

# ---------------------------------------------------------------- WEB-03
C_SIN=$(http_code "${URL}/privado/")
C_OK=$(http_code -u "${USUARIO}:${PASS}" "${URL}/privado/")
{
    echo "## Sin credenciales"; http_full "${URL}/privado/"
    echo; echo "## Con credenciales LDAP validas (usuario ${USUARIO})"; http_full -u "${USUARIO}:${PASS}" "${URL}/privado/"
} > /tmp/web03.$$ 2>&1
evid "WEB-03_acceso_valido.txt" "curl -i ${URL}/privado/  y  curl -i -u ${USUARIO}:******** ${URL}/privado/" "$(cat /tmp/web03.$$)"
rm -f /tmp/web03.$$
if [ "$C_SIN" = "401" ]; then ok "WEB-03a" "/privado/ sin credenciales -> 401 (pide autenticacion)"; else fail "WEB-03a" "/privado/ sin credenciales -> ${C_SIN} (esperado 401)"; fi
if [ "$C_OK"  = "200" ]; then ok "WEB-03"  "usuario LDAP valido (${USUARIO}) -> 200"; else fail "WEB-03" "usuario LDAP valido -> ${C_OK} (esperado 200)"; fi

# ---------------------------------------------------------------- WEB-04
C_MALA=$(http_code -u "${USUARIO}:contrasena-incorrecta-lab" "${URL}/privado/")
C_NOEX=$(http_code -u "usuario_inexistente:cualquier-cosa" "${URL}/privado/")
{
    echo "## Contrasena incorrecta (usuario ${USUARIO})"; http_full -u "${USUARIO}:contrasena-incorrecta-lab" "${URL}/privado/"
    echo; echo "## Usuario inexistente"; http_full -u "usuario_inexistente:cualquier-cosa" "${URL}/privado/"
} > /tmp/web04.$$ 2>&1
evid "WEB-04_rechazo.txt" "curl -i -u ${USUARIO}:<incorrecta> ...  y  curl -i -u usuario_inexistente:<x> ..." "$(cat /tmp/web04.$$)"
rm -f /tmp/web04.$$
if [ "$C_MALA" = "401" ]; then ok "WEB-04a" "contrasena incorrecta -> 401"; else fail "WEB-04a" "contrasena incorrecta -> ${C_MALA} (esperado 401)"; fi
if [ "$C_NOEX" = "401" ]; then ok "WEB-04b" "usuario inexistente -> 401"; else fail "WEB-04b" "usuario inexistente -> ${C_NOEX} (esperado 401)"; fi

# ------------------------------------------------- INT (solo en el servidor web)
if [ "$(id -u)" -eq 0 ] && systemctl is-active --quiet apache2 2>/dev/null; then
    CT=$(apache2ctl configtest 2>&1)
    evid "WEB-CHK_apache2ctl_configtest.txt" "apache2ctl configtest" "$CT"
    [[ "$CT" == *"Syntax OK"* ]] && ok "CHECK" "apache2ctl configtest: Syntax OK" || fail "CHECK" "apache2ctl configtest con errores"

    ST=$( { systemctl status apache2 --no-pager; echo; echo "is-enabled: $(systemctl is-enabled apache2)"; } 2>&1 )
    evid "INT-02_web_systemctl_apache2.txt" "systemctl status apache2; systemctl is-enabled apache2" "$ST"
    if [ "$(systemctl is-enabled apache2 2>/dev/null)" = "enabled" ]; then ok "INT-02" "apache2 activo y habilitado al arranque"; else fail "INT-02" "apache2 no esta habilitado al arranque"; fi

    PT=$(ss -lntup | awk 'NR==1 || /:80 /')
    evid "INT-03_web_ss_puertos.txt" "ss -lntup | grep :80" "$PT"
    if grep -q ':80 ' <<<"$PT"; then ok "INT-03" "Apache escucha en el puerto 80"; else fail "INT-03" "nada escucha en el puerto 80"; fi

    LG="## restaurante_access.log (ultimas 20)
$(tail -n 20 /var/log/apache2/restaurante_access.log 2>&1)

## restaurante_error.log (ultimas 20)
$(tail -n 20 /var/log/apache2/restaurante_error.log 2>&1)"
    evid "INT-04_web_logs_apache.txt" "tail -n 20 /var/log/apache2/restaurante_{access,error}.log" "$LG"
    ok "INT-04" "extracto de logs guardado (solo evidencia, no se evalua)"
else
    echo "(INT-02/03/04 y configtest solo se ejecutan en el servidor web, con sudo)"
fi

echo "------------------------------------------------------------------"
echo "Evidencias en: ${OUT}"
echo "Pasaron: ${PASA}   Fallaron: ${FALLA}"
echo "Pendiente manual: capturas de navegador WEB-02/03/04 y WEB-05 (ver README)."
[ "$FALLA" -eq 0 ] && exit 0 || exit 1
