#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Correo (Integrante 4). PASO 6 (opcional): MODO INDIVIDUAL
#  Para probar el correo SIN la red del grupo: instala en esta misma VM
#  un DNS (BIND9) y un LDAP (OpenLDAP) mínimos que imitan los del grupo
#  (mismos FQDN, misma base, mismos atributos). La configuración del
#  correo no cambia. Las evidencias del paso 4 quedan marcadas como
#  "MODO INDIVIDUAL".
#
#  Requiere internet (correr con la VM en NAT).
#  Uso:  sudo bash 6-modo-individual.sh <uid1> '<pass1>' <uid2> '<pass2>'
#        (usuarios y contraseñas de PRUEBA, exclusivas del laboratorio)
#
#  Para desactivarlo el día de la prueba en grupo:
#        sudo systemctl disable --now named slapd && sudo rm /etc/lab5-modo-individual
#        y luego correr 2-configurar-red.sh
# =====================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Ejecutar con sudo"; exit 1; fi
if [[ $# -ne 4 ]]; then echo "Uso: sudo bash $0 <uid1> '<pass1>' <uid2> '<pass2>'"; exit 1; fi
U1=$1; P1=$2; U2=$3; P2=$4

D="restaurante.redes.test"
BASE="dc=${D//./,dc=}"
IFACE=$(ip route show default | awk '{print $5; exit}')
MI_IP=$(ip -4 -o addr show "$IFACE" | awk '{print $4}' | cut -d/ -f1 | head -1)
ADMIN_PW=$(openssl rand -base64 18)
echo "==> Modo individual: DNS + LDAP locales en $MI_IP ($IFACE)"

# --- 1. Paquetes (antes de cambiar el DNS de la VM) -------------------
export DEBIAN_FRONTEND=noninteractive
preseed_slapd() {
debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string $D
slapd shared/organization string Restaurante
slapd slapd/password1 password $ADMIN_PW
slapd slapd/password2 password $ADMIN_PW
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF
}
preseed_slapd
apt-get update
apt-get install -y bind9 bind9-utils slapd ldap-utils
# debconf olvida las contraseñas tras instalar: recargar y reconfigurar
preseed_slapd
dpkg-reconfigure -f noninteractive slapd
# Contraseña de admin del LDAP de prueba (sin salto de línea, para ldapadd -y)
printf '%s' "$ADMIN_PW" > /root/lab5-ldap-admin.txt; chmod 600 /root/lab5-ldap-admin.txt

# --- 2. DNS: zona mínima restaurante.redes.test -----------------------
ZONA=/etc/bind/db.$D
cat > "$ZONA" <<EOF
\$TTL 300
@       IN SOA ns1.$D. admin.$D. ( $(date +%Y%m%d)01 3600 900 604800 300 )
@       IN NS  ns1.$D.
@       IN MX  10 mail.$D.
ns1     IN A   $MI_IP
ldap    IN A   $MI_IP
mail    IN A   $MI_IP
EOF
grep -q "zone \"$D\"" /etc/bind/named.conf.local || cat >> /etc/bind/named.conf.local <<EOF
zone "$D" { type master; file "$ZONA"; };
EOF
named-checkzone "$D" "$ZONA"
systemctl enable named >/dev/null 2>&1 || true
systemctl restart named

# La VM usa este DNS local (sin /etc/hosts). Mismo archivo que el paso 2,
# así 2-configurar-red.sh lo reemplaza el día de la prueba en grupo.
cat > /etc/netplan/99-lab5.yaml <<EOF
# Lab 5 - MODO INDIVIDUAL (DNS local)
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: true
      dhcp4-overrides: {use-dns: false}
      nameservers:
        addresses: [127.0.0.1]
        search: [$D]
EOF
chmod 600 /etc/netplan/99-lab5.yaml
netplan apply; sleep 3

# --- 3. LDAP: ou=People + 2 usuarios con los atributos del grupo ------
LDIF=$(mktemp)
{
cat <<EOF
dn: ou=People,$BASE
objectClass: organizationalUnit
ou: People

EOF
for par in "$U1:$P1" "$U2:$P2"; do
    u=${par%%:*}; p=${par#*:}
    cat <<EOF
dn: uid=$u,ou=People,$BASE
objectClass: inetOrgPerson
uid: $u
cn: Usuario $u
sn: $u
mail: $u@$D
userPassword: $(slappasswd -s "$p")

EOF
done
} > "$LDIF"
ldapadd -c -x -H ldap://localhost -D "cn=admin,$BASE" -y /root/lab5-ldap-admin.txt -f "$LDIF" || true
rm -f "$LDIF"

# --- 4. Reiniciar correo para que tome el DNS/LDAP nuevos -------------
touch /etc/lab5-modo-individual
systemctl restart postfix dovecot

# --- 5. Verificación ---------------------------------------------------
echo
ok()  { echo "  [OK]    $*"; }
bad() { echo "  [FALLA] $*"; }
for h in ns1 ldap mail; do
    R=$(dig +short "$h.$D" A | tail -1); [[ -n "$R" ]] && ok "$h.$D -> $R" || bad "$h.$D no resuelve"
done
[[ "$(dig +short "$D" MX)" == *"mail.$D"* ]] && ok "MX -> mail.$D" || bad "MX"
N=$(ldapsearch -x -LLL -H "ldap://ldap.$D" -b "ou=People,$BASE" "(uid=*)" mail 2>/dev/null | grep -c '^mail:' || true)
[[ "$N" -ge 2 ]] && ok "LDAP: $N usuarios con correo" || bad "LDAP sin usuarios"
postmap -q "$U1@$D" ldap:/etc/postfix/ldap-users.cf >/dev/null && ok "Postfix encuentra $U1@$D" || bad "Postfix no encuentra $U1@$D"
doveadm auth test "$U1" "$P1" >/dev/null 2>&1 && ok "Dovecot autentica a $U1" || bad "Dovecot no autentica a $U1"
echo
echo "==> Siguiente: sudo bash 4-pruebas-correo.sh $U1 '<pass1>' $U2 '<pass2>'"
