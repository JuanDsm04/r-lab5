#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Correo. PASO 1: instalar paquetes
#  Necesita INTERNET: córrelo ANTES de 2-configurar-red.sh (después de
#  ese paso la VM usa el DNS del grupo y quizá ya no resuelva internet).
#  Uso:  sudo bash 1-instalar-paquetes.sh
# =====================================================================
set -euo pipefail
DOMINIO="restaurante.redes.test"

if [[ $EUID -ne 0 ]]; then echo "Ejecutar con sudo"; exit 1; fi

export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string $DOMINIO
EOF
apt-get update
apt-get install -y postfix postfix-ldap \
    dovecot-core dovecot-imapd dovecot-lmtpd dovecot-ldap \
    ldap-utils dnsutils swaks curl ssl-cert

VER=$(dovecot --version | cut -d. -f1,2)
if [[ "$VER" != "2.3" ]]; then
    echo "!! Se instaló Dovecot $VER. La config es para 2.3: usa Ubuntu Server 24.04."
    exit 1
fi
echo
echo "==> Paquetes listos (Dovecot $(dovecot --version | cut -d' ' -f1), Postfix $(postconf -h mail_version))."
echo "==> Siguiente: sudo bash 2-configurar-red.sh"
