#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - CC3067 Redes - Ejercicio 4: Servidor de correo
#  Postfix (SMTP) + Dovecot (IMAP/LMTP) autenticando contra OpenLDAP
#
#  Para: Ubuntu Server 24.04 / 22.04 (Dovecot 2.3.x)
#  Requiere: haber corrido 1-instalar-paquetes.sh
#  Uso:   sudo bash 3-configurar-correo.sh
#
#  No usa ninguna IP: todo va por nombres DNS, así que no hay que
#  volver a correrlo si cambian de red (solo 2-configurar-red.sh).
# =====================================================================
set -euo pipefail

DOMINIO="restaurante.redes.test"
LDAP_HOST="ldap.${DOMINIO}"
# El LDAP del grupo permite búsqueda anónima -> no hace falta bind DN
LDAP_BIND_DN=""
LDAP_BIND_PW=""

# dc=restaurante,dc=redes,dc=test  a partir del dominio
BASE_DN="dc=${DOMINIO//./,dc=}"
PEOPLE_DN="ou=People,${BASE_DN}"
MAIL_HOST="mail.${DOMINIO}"
VMAIL_UID=5000

if [[ $EUID -ne 0 ]]; then echo "Ejecutar con sudo"; exit 1; fi

echo "==> Dominio: $DOMINIO | Base LDAP: $BASE_DN | LDAP: $LDAP_HOST"

# --- 1. Hostname ------------------------------------------------------
hostnamectl set-hostname "$MAIL_HOST"
echo "$DOMINIO" > /etc/mailname

# --- 2. Verificar paquetes (instalados en el paso 1) ------------------
if ! command -v dovecot >/dev/null || ! command -v postconf >/dev/null; then
    echo "!! Falta Postfix/Dovecot. Corre primero: sudo bash 1-instalar-paquetes.sh"; exit 1
fi
if [[ "$(dovecot --version | cut -d. -f1,2)" != "2.3" ]]; then
    echo "!! Esta config es para Dovecot 2.3 (Ubuntu 24.04)."; exit 1
fi

# Certificado autofirmado con el nombre correcto (para STARTTLS)
make-ssl-cert generate-default-snakeoil --force-overwrite

# --- 3. Usuario dueño de los buzones ----------------------------------
getent group vmail  >/dev/null || groupadd -g $VMAIL_UID vmail
getent passwd vmail >/dev/null || useradd -u $VMAIL_UID -g vmail -d /var/vmail -s /usr/sbin/nologin -m vmail
mkdir -p /var/vmail && chown -R vmail:vmail /var/vmail && chmod 770 /var/vmail

# --- 4. Postfix -------------------------------------------------------
cat > /etc/postfix/ldap-users.cf <<EOF
# Valida que el destinatario exista en OpenLDAP (atributo mail)
server_host = ldap://${LDAP_HOST}
version = 3
search_base = ${PEOPLE_DN}
scope = one
query_filter = (mail=%s)
result_attribute = mail
EOF
if [[ -n "$LDAP_BIND_DN" ]]; then
cat >> /etc/postfix/ldap-users.cf <<EOF
bind = yes
bind_dn = ${LDAP_BIND_DN}
bind_pw = ${LDAP_BIND_PW}
EOF
else
    echo "bind = no" >> /etc/postfix/ldap-users.cf
fi
chown root:postfix /etc/postfix/ldap-users.cf
chmod 640 /etc/postfix/ldap-users.cf

postconf -e "myhostname = ${MAIL_HOST}"
postconf -e "mydomain = ${DOMINIO}"
postconf -e "myorigin = \$mydomain"
postconf -e "mydestination = localhost"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mynetworks = 127.0.0.0/8"
# Dominio virtual: buzones según LDAP, entrega a Dovecot por LMTP
postconf -e "virtual_mailbox_domains = ${DOMINIO}"
postconf -e "virtual_mailbox_maps = proxy:ldap:/etc/postfix/ldap-users.cf"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
# Autenticación SMTP (SASL) delegada a Dovecot -> LDAP
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "broken_sasl_auth_clients = yes"
# TLS opcional (STARTTLS) con el certificado autofirmado
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_tls_security_level = may"
# Restricciones: rechaza destinatarios inexistentes, no es open relay
postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
postconf -e "smtpd_recipient_restrictions = reject_unlisted_recipient"

# Puerto 587 (submission) para Thunderbird: exige autenticación
postconf -M "submission/inet=submission inet n - y - - smtpd"
postconf -P "submission/inet/syslog_name=postfix/submission"
postconf -P "submission/inet/smtpd_tls_security_level=may"
postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
postconf -P "submission/inet/smtpd_relay_restrictions=permit_sasl_authenticated,reject"
postconf -P "submission/inet/smtpd_recipient_restrictions=reject_unlisted_recipient,permit_sasl_authenticated,reject"

# --- 5. Dovecot (config completa, sin conf.d) -------------------------
[[ -f /etc/dovecot/dovecot.conf.orig ]] || cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.orig

cat > /etc/dovecot/dovecot-ldap.conf.ext <<EOF
# Autenticación por "bind": Dovecot intenta un bind LDAP con el DN del
# usuario y la contraseña escrita en Thunderbird. Si LDAP acepta -> login OK.
uris = ldap://${LDAP_HOST}
ldap_version = 3
base = ${PEOPLE_DN}
auth_bind = yes
auth_bind_userdn = uid=%n,${PEOPLE_DN}
EOF
chmod 600 /etc/dovecot/dovecot-ldap.conf.ext

cat > /etc/dovecot/dovecot.conf <<EOF
# Lab 5 - Dovecot: IMAP para clientes, LMTP para entrega desde Postfix
protocols = imap lmtp
listen = *

# Logs a syslog -> /var/log/mail.log (junto con Postfix)
auth_verbose = yes
auth_verbose_passwords = no
verbose_ssl = no

# Usuarios pueden escribir "juan" o "juan@${DOMINIO}"
auth_username_format = %Ln
auth_mechanisms = plain login
# Laboratorio: permite login sin TLS
disable_plaintext_auth = no

ssl = yes
ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem
ssl_key  = </etc/ssl/private/ssl-cert-snakeoil.key

# Contraseñas: OpenLDAP
passdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
# Buzones: todos pertenecen al usuario de sistema vmail
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/vmail/%n allow_all_users=yes
}

mail_location = maildir:~/Maildir
first_valid_uid = ${VMAIL_UID}

namespace inbox {
  inbox = yes
  mailbox Drafts {
    special_use = \\Drafts
    auto = subscribe
  }
  mailbox Sent {
    special_use = \\Sent
    auto = subscribe
  }
  mailbox Trash {
    special_use = \\Trash
    auto = subscribe
  }
  mailbox Junk {
    special_use = \\Junk
    auto = subscribe
  }
}

service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
  }
}

# Socket donde Postfix entrega el correo
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

# Socket donde Postfix pregunta usuario/contraseña (SMTP AUTH)
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = vmail
  }
}

protocol lmtp {
  postmaster_address = postmaster@${DOMINIO}
}
EOF

# --- 6. Firewall (si ufw está activo) ---------------------------------
if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 25/tcp; ufw allow 587/tcp; ufw allow 143/tcp; ufw allow 993/tcp
fi

# --- 7. Arrancar y dejar persistente ----------------------------------
doveconf -n >/dev/null          # valida sintaxis de Dovecot
postfix check                   # valida Postfix
systemctl enable --now dovecot postfix
systemctl restart dovecot postfix

echo
echo "==> Listo. Verificaciones rápidas:"
ss -lntp | grep -E ':(25|587|143|993)\s' || true
echo "--- Búsqueda LDAP desde Postfix (debe imprimir un correo):"
FIRST=$(ldapsearch -x -LLL -H "ldap://${LDAP_HOST}" -b "$PEOPLE_DN" mail 2>/dev/null | awk '/^mail:/{print $2; exit}' || true)
if [[ -n "${FIRST:-}" ]]; then
    postmap -q "$FIRST" "ldap:/etc/postfix/ldap-users.cf" || echo "!! Postfix no encontró $FIRST en LDAP"
else
    echo "!! No pude leer usuarios de ldap://${LDAP_HOST}. Revisa DNS/LDAP (o configura LDAP_BIND_DN)."
fi
