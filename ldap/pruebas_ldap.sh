#!/usr/bin/env bash
# Matriz de pruebas LDAP-01 a LDAP-04 (Lab 5). Correr desde OTRA máquina del grupo
# (Ubuntu con ldap-utils, o macOS que ya trae ldapsearch). Guarda la salida en evidencias/ldap/.
#
# Uso: ./pruebas_ldap.sh <uid> <password>
#      LDAP_HOST=192.168.1.50 ./pruebas_ldap.sh nmuralles '<password>'   # si aún no hay DNS
set -uo pipefail

[[ $# -eq 2 ]] || { echo "Uso: $0 <uid> <password>"; exit 1; }
USUARIO="$1"
PASS="$2"

DOMINIO="restaurante.redes.test"
BASE_DN="dc=restaurante,dc=redes,dc=test"
PEOPLE="ou=People,${BASE_DN}"
LDAP_HOST="${LDAP_HOST:-ldap.${DOMINIO}}"
URI="ldap://${LDAP_HOST}"
USER_DN="uid=${USUARIO},${PEOPLE}"

command -v ldapsearch >/dev/null || { echo "Falta ldap-utils: sudo apt install -y ldap-utils"; exit 1; }

# Convención del grupo (CLAUDE.md): evidencias/ldap/ en la raíz del repo
DIR="$(cd "$(dirname "$0")/.." && pwd)/evidencias/ldap"
mkdir -p "$DIR"
LOG="${DIR}/pruebas_ldap_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$LOG") 2>&1

OK=0; FALLA=0
titulo() { printf '\n==================== %s ====================\n' "$1"; }
resultado() {
  if [[ $1 -eq 0 ]]; then echo ">>> RESULTADO: PASA"; OK=$((OK + 1))
  else echo ">>> RESULTADO: FALLA"; FALLA=$((FALLA + 1)); fi
}

echo "Pruebas LDAP - ${DOMINIO}"
echo "Fecha:   $(date)"
echo "Cliente: $(hostname)"
echo "Server:  ${URI}"

titulo "PRE - Resolución DNS de ${LDAP_HOST}"
if [[ $LDAP_HOST =~ ^[0-9.]+$ ]]; then
  echo "AVISO: usando IP directa. Para la entrega final usar el FQDN (INT-01)."
elif command -v dig >/dev/null; then
  echo "\$ dig +short ${LDAP_HOST}"
  IP=$(dig +short "$LDAP_HOST"); echo "$IP"
  [[ -n $IP ]] || { echo "No resuelve ${LDAP_HOST}. Revisa el DNS o usa LDAP_HOST=<ip>."; exit 1; }
else
  echo "\$ nslookup ${LDAP_HOST}"
  nslookup "$LDAP_HOST" || { echo "No resuelve ${LDAP_HOST}. Revisa el DNS o usa LDAP_HOST=<ip>."; exit 1; }
fi

titulo "LDAP-01 - Consulta de usuarios en ${PEOPLE}"
echo "\$ ldapsearch -x -LLL -H ${URI} -b \"${PEOPLE}\" \"(objectClass=inetOrgPerson)\" uid cn mail"
SALIDA=$(ldapsearch -x -LLL -o ldif-wrap=no -H "$URI" -b "$PEOPLE" "(objectClass=inetOrgPerson)" uid cn mail)
RC=$?
echo "$SALIDA"
N=$(grep -c '^dn:' <<<"$SALIDA")
echo "Usuarios encontrados: ${N}"
[[ $RC -eq 0 && $N -gt 0 ]]; resultado $?

titulo "LDAP-02 - Bind con credenciales válidas (${USUARIO})"
echo "\$ ldapwhoami -x -H ${URI} -D \"${USER_DN}\" -w '********'"
ldapwhoami -x -H "$URI" -D "$USER_DN" -w "$PASS"
resultado $?

titulo "LDAP-03 - Bind con contraseña incorrecta"
echo "\$ ldapwhoami -x -H ${URI} -D \"${USER_DN}\" -w 'contraseña_incorrecta'"
SALIDA=$(ldapwhoami -x -H "$URI" -D "$USER_DN" -w "contraseña_incorrecta" 2>&1)
echo "$SALIDA"
grep -q 'Invalid credentials (49)' <<<"$SALIDA"; resultado $?

titulo "LDAP-03b - Bind con usuario inexistente"
FAKE_DN="uid=noexiste,${PEOPLE}"
echo "\$ ldapwhoami -x -H ${URI} -D \"${FAKE_DN}\" -w 'cualquiera'"
SALIDA=$(ldapwhoami -x -H "$URI" -D "$FAKE_DN" -w "cualquiera" 2>&1)
echo "$SALIDA"
grep -q 'Invalid credentials (49)' <<<"$SALIDA"; resultado $?

titulo "LDAP-04 - Atributos uid, cn, sn y mail de ${USUARIO}"
echo "\$ ldapsearch -x -LLL -H ${URI} -b \"${BASE_DN}\" \"(uid=${USUARIO})\" uid cn sn mail"
SALIDA=$(ldapsearch -x -LLL -o ldif-wrap=no -H "$URI" -b "$BASE_DN" "(uid=${USUARIO})" uid cn sn mail)
echo "$SALIDA"
FALTAN=""
for a in uid cn sn mail; do grep -qE "^${a}::? " <<<"$SALIDA" || FALTAN="${FALTAN} ${a}"; done
[[ -n $FALTAN ]] && echo "Faltan atributos:${FALTAN}"
[[ -z $FALTAN ]] && grep -q "^mail: .*@${DOMINIO}$" <<<"$SALIDA"; resultado $?

titulo "EXTRA - userPassword no es visible anónimamente"
echo "\$ ldapsearch -x -LLL -H ${URI} -b \"${BASE_DN}\" \"(uid=${USUARIO})\" userPassword"
SALIDA=$(ldapsearch -x -LLL -o ldif-wrap=no -H "$URI" -b "$BASE_DN" "(uid=${USUARIO})" userPassword)
echo "$SALIDA"
! grep -q '^userPassword' <<<"$SALIDA"; resultado $?

titulo "RESUMEN"
echo "Pasan: ${OK}   Fallan: ${FALLA}"
echo "Evidencia guardada en: ${LOG}"
[[ $FALLA -eq 0 ]]
