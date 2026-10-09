#!/usr/bin/env bash
# Instala y configura Apache para www.restaurante.redes.test con login LDAP.
# Requiere Internet (apt): correrlo ANTES de asignar la IP del laboratorio.
# Se puede repetir: vuelve a publicar el sitio y el virtual host.
#
# Uso (desde la raiz del repositorio):
#   sudo bash web/setup.sh
set -euo pipefail

DOMINIO="restaurante.redes.test"
FQDN="www.${DOMINIO}"
RAIZ="/var/www/restaurante"
CONF="restaurante.conf"
DIR="$(cd "$(dirname "$0")" && pwd)"

error() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Correr con sudo: sudo bash $0"
[ -f "$DIR/$CONF" ] || error "No encuentro $DIR/$CONF"
[ -d "$DIR/sitio" ] || error "No encuentro la carpeta $DIR/sitio"

echo "==> [1/5] Instalando Apache y herramientas de prueba"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q apache2 ldap-utils curl bind9-dnsutils

echo "==> [2/5] Habilitando modulos ldap, authnz_ldap e include"
a2enmod ldap authnz_ldap include >/dev/null
echo "ServerName ${FQDN}" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null

echo "==> [3/5] Publicando el sitio en ${RAIZ}"
mkdir -p "$RAIZ"
rm -rf "${RAIZ:?}"/*
cp -r "$DIR/sitio/." "$RAIZ/"
chown -R root:root "$RAIZ"
find "$RAIZ" -type d -exec chmod 755 {} +
find "$RAIZ" -type f -exec chmod 644 {} +

echo "==> [4/5] Instalando el virtual host"
install -m 644 "$DIR/$CONF" "/etc/apache2/sites-available/$CONF"
a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite "$CONF" >/dev/null
apache2ctl configtest

echo "==> [5/5] Servicio y firewall"
systemctl enable apache2 >/dev/null 2>&1
systemctl restart apache2
if ufw status 2>/dev/null | grep -q 'Status: active'; then
    ufw allow 80/tcp
else
    echo "ufw inactivo, no hace falta abrir el 80"
fi

echo
echo "Verificacion local (cabecera Host: ${FQDN}):"
P=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${FQDN}" http://localhost/ || true)
Q=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${FQDN}" http://localhost/privado/ || true)
echo "  /          -> ${P}  (esperado 200)"
echo "  /privado/  -> ${Q}  (esperado 401: pide credenciales)"
echo
echo "Siguiente paso: asignar la IP fija con"
echo "  sudo bash web/red/cambiar-ip.sh <subred>"
