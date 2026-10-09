#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Correo (Integrante 4). PASO 5: exportar configuración final
#  Copia la configuración real del servidor a ./export/mail/ con la
#  estructura del repo (CLAUDE.md §9: mail/main.cf, master.cf, dovecot/).
#  Uso:  sudo bash 5-exportar-config.sh
# =====================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Ejecutar con sudo"; exit 1; fi

OUT="$(pwd)/export/mail"
mkdir -p "$OUT/dovecot"

cp /etc/postfix/main.cf             "$OUT/main.cf"
cp /etc/postfix/master.cf           "$OUT/master.cf"
cp /etc/postfix/ldap-users.cf       "$OUT/ldap-users.cf"
cp /etc/dovecot/dovecot.conf        "$OUT/dovecot/dovecot.conf"
cp /etc/dovecot/dovecot-ldap.conf.ext "$OUT/dovecot/dovecot-ldap.conf.ext"
postconf -n                         > "$OUT/postconf-n.txt"
doveconf -n                         > "$OUT/dovecot/doveconf-n.txt"

# Regla 5/§8: sin contraseñas en texto plano
if grep -rniE '^\s*(bind_pw|dnpass)\s*=\s*\S' "$OUT"; then
    echo "!! Hay contraseñas en la config exportada: bórralas antes de subirla al repo."
fi
[[ -n "${SUDO_USER:-}" ]] && chown -R "$SUDO_USER": "$(pwd)/export"

echo "==> Exportado en $OUT:"
find "$OUT" -type f | sort
