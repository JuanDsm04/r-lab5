#!/usr/bin/env bash
# Instala y configura OpenLDAP para restaurante.redes.test en un Ubuntu limpio.
# Genera usuarios.ldif a partir de integrantes.csv y lo carga.
# Se puede volver a correr: reconfigura slapd y recrea el directorio desde cero.
#
# Uso: sudo ./setup_ldap.sh              (pide la contraseña del admin LDAP)
#      sudo ADMIN_PASS='...' ./setup_ldap.sh
set -euo pipefail

DOMINIO="restaurante.redes.test"
BASE_DN="dc=restaurante,dc=redes,dc=test"
ADMIN_DN="cn=admin,${BASE_DN}"
ORG="Cadena de restaurantes - Grupo Redes"
ADMIN_PASS="${ADMIN_PASS:-}"
GID_GRUPO=10000
UID_INICIAL=10001

DIR="$(cd "$(dirname "$0")" && pwd)"
CSV="${DIR}/integrantes.csv"
LDIF="${DIR}/usuarios.ldif"

[[ $EUID -eq 0 ]] || { echo "Correr con sudo: sudo $0"; exit 1; }
[[ -f $CSV ]] || { echo "No encuentro ${CSV}. Cópialo de integrantes.ejemplo.csv y pon las contraseñas."; exit 1; }
if [[ -z $ADMIN_PASS ]]; then
  read -rsp "Contraseña para cn=admin (solo del laboratorio): " ADMIN_PASS; echo
  [[ -n $ADMIN_PASS ]] || { echo "La contraseña no puede ir vacía"; exit 1; }
fi

if grep -q '^integrante[0-9]' "$CSV"; then
  echo "AVISO: integrantes.csv todavía tiene filas de ejemplo (integranteN)."
  echo "       Edítalo con los datos reales antes de la entrega."
fi

# El postinst de slapd borra las contraseñas de debconf al usarlas,
# por eso se precargan antes de instalar y otra vez antes de reconfigurar.
preseed() {
  debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string ${DOMINIO}
slapd shared/organization string ${ORG}
slapd slapd/password1 password ${ADMIN_PASS}
slapd slapd/password2 password ${ADMIN_PASS}
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF
}

echo "==> [1/6] Preconfigurando slapd (dominio ${DOMINIO})"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q debconf-utils
preseed

echo "==> [2/6] Instalando slapd y ldap-utils"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q slapd ldap-utils
# Fuerza la base dc=restaurante,dc=redes,dc=test aunque slapd ya estuviera instalado
preseed
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive slapd
systemctl enable --now slapd
for _ in $(seq 1 20); do
  ldapsearch -Y EXTERNAL -H ldapi:/// -Q -s base -b cn=config dn >/dev/null 2>&1 && break
  sleep 1
done

echo "==> [3/6] Activando logs de conexiones y binds (journalctl -u slapd)"
ldapmodify -Y EXTERNAL -H ldapi:/// -Q <<EOF
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
EOF

# Escribe "attr: valor", o "attr:: base64" si el valor tiene tildes/ñ (requisito de LDIF)
attr() {
  if LC_ALL=C grep -q '[^ -~]' <<<"$2"; then
    printf '%s:: %s\n' "$1" "$(printf '%s' "$2" | base64 -w0)"
  else
    printf '%s: %s\n' "$1" "$2"
  fi
}

echo "==> [4/6] Generando ${LDIF}"
{
  echo "# Usuarios LDAP - Laboratorio 5 - ${DOMINIO}"
  echo
  echo "dn: ou=People,${BASE_DN}"
  echo "objectClass: organizationalUnit"
  echo "ou: People"
  echo
  echo "dn: ou=Groups,${BASE_DN}"
  echo "objectClass: organizationalUnit"
  echo "ou: Groups"
  echo

  miembros=()
  num=$UID_INICIAL
  while IFS=, read -r uid nombre apellido pass; do
    [[ -z ${uid// } || $uid == \#* ]] && continue
    pass="${pass%$'\r'}"
    echo "dn: uid=${uid},ou=People,${BASE_DN}"
    echo "objectClass: inetOrgPerson"
    echo "objectClass: posixAccount"
    echo "objectClass: shadowAccount"
    echo "uid: ${uid}"
    attr cn "${nombre} ${apellido}"
    attr givenName "${nombre}"
    attr sn "${apellido}"
    echo "mail: ${uid}@${DOMINIO}"
    echo "userPassword: $(slappasswd -s "$pass")"
    echo "uidNumber: ${num}"
    echo "gidNumber: ${GID_GRUPO}"
    echo "homeDirectory: /home/${uid}"
    echo "loginShell: /bin/bash"
    echo
    miembros+=("$uid")
    num=$((num + 1))
  done < "$CSV"

  echo "dn: cn=restaurante,ou=Groups,${BASE_DN}"
  echo "objectClass: posixGroup"
  echo "cn: restaurante"
  echo "gidNumber: ${GID_GRUPO}"
  for m in "${miembros[@]}"; do echo "memberUid: ${m}"; done
} > "$LDIF"

echo "==> [5/6] Cargando usuarios"
ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PASS" -f "$LDIF"

echo "==> [6/6] Firewall"
if ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow 389/tcp
else
  echo "ufw inactivo, no hace falta abrir el 389"
fi

echo
echo "Listo. Usuarios cargados en ou=People,${BASE_DN}:"
ldapsearch -x -LLL -H ldap://localhost -b "ou=People,${BASE_DN}" '(uid=*)' uid mail
ss -lntp | grep ':389 ' || true
echo "Admin DN: ${ADMIN_DN}"
echo "LDIF generado (entregable): ${LDIF}"
