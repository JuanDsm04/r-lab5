#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Correo (Integrante 4). PASO 4: evidencias del lado servidor
#  Ejecuta MAIL-01..07 + INT-03/INT-04 en mail.restaurante.redes.test y
#  guarda un archivo por prueba en ./evidencias/mail/ con el formato del
#  grupo: <ID-PRUEBA>_<descripcion>.txt  (CLAUDE.md §8).
#  Complementa las capturas de Thunderbird que toma el Integrante 6.
#
#  Uso: sudo bash 4-pruebas-correo.sh <uid1> '<pass1>' <uid2> '<pass2>'
#  (uid de LDAP; contraseñas de laboratorio entre comillas simples.
#   Las contraseñas NO se escriben en los archivos de evidencia.)
# =====================================================================
set -uo pipefail
if [[ $# -ne 4 ]]; then
    echo "Uso: sudo bash $0 <uid1> '<pass1>' <uid2> '<pass2>'"; exit 1
fi
D="restaurante.redes.test"; U1=$1; P1=$2; U2=$3; P2=$4
MAIL="mail.$D"
EV="$(pwd)/evidencias/mail"
mkdir -p "$EV"

# Encabezado de cada evidencia: prueba, hostname, fecha
abrir() {
    OUT="$EV/$1.txt"
    { echo "# $1"; echo "# host: $(hostname -f)   fecha: $(date '+%F %T %Z')"
      [[ -f /etc/lab5-modo-individual ]] && echo "# MODO INDIVIDUAL: DNS (BIND9) y LDAP (OpenLDAP) de prueba locales en esta VM, no los servidores del grupo"
      echo; } > "$OUT"
    echo ">> $1"
}
# Ejecuta un comando mostrando el comando (sin contraseñas) y su salida
run() {
    local shown="$1"; shift
    { echo "\$ $shown"; "$@" 2>&1; echo; } >> "$OUT"
}
nota() { echo "$*" >> "$OUT"; }
logs() {   # logs recientes de Postfix/Dovecot filtrados por un patrón
    { echo "--- log ($1)"
      if [[ -f /var/log/mail.log ]]; then tail -n 400 /var/log/mail.log | grep -E "$1" | tail -n "${2:-10}"
      else journalctl --since "15 min ago" -u dovecot -u 'postfix*' --no-pager | grep -E "$1" | tail -n "${2:-10}"; fi
      echo; } >> "$OUT"
}

# ---------------------------------------------------------------------
abrir "MAIL-01_dig_mail_mx"
run "dig mail.$D A" dig "$MAIL" A
run "dig $D MX"     dig "$D" MX

abrir "MAIL-03_auth_valida"
run "doveadm auth test $U1 ****" doveadm auth test "$U1" "$P1"
run "curl imap://$MAIL/ --user $U1:**** (LOGIN + LIST)" \
    curl -sS --url "imap://$MAIL/" --user "$U1:$P1"
sleep 1; logs "imap-login: Login: user=<$U1>" 3

abrir "MAIL-04_auth_invalida"
run "doveadm auth test $U1 <contraseña incorrecta>" doveadm auth test "$U1" "contrasena-incorrecta"
run "curl imap://$MAIL/ --user $U1:<incorrecta>" \
    curl -sS --url "imap://$MAIL/" --user "$U1:contrasena-incorrecta"
nota "(curl exit 67 = login denied)"
sleep 1; logs "auth failed|password mismatch|Invalid credentials" 5

abrir "MAIL-05_envio_smtp"
SUBJ="Prueba Lab5 MAIL-05 $(date +%H%M%S)"
run "postmap -q $U2@$D ldap:/etc/postfix/ldap-users.cf   (destinatario existe en LDAP)" \
    postmap -q "$U2@$D" ldap:/etc/postfix/ldap-users.cf
run "swaks --server $MAIL --port 587 -tls --auth-user $U1 --from $U1@$D --to $U2@$D" \
    swaks --server "$MAIL" --port 587 -tls --auth LOGIN --auth-user "$U1" --auth-password "$P1" \
          --from "$U1@$D" --to "$U2@$D" --header "Subject: $SUBJ" \
          --body "Mensaje de prueba MAIL-05 enviado por $U1 a $U2"
sleep 3
logs "sasl_username=$U1|to=<$U2@$D>" 8
run "ls -l /var/vmail/$U2/Maildir/new/   (entrega al buzón)" ls -l "/var/vmail/$U2/Maildir/new/"

abrir "MAIL-06_lectura_imap"
UID_MSG=$(curl -s --url "imap://$MAIL/INBOX" --user "$U2:$P2" -X "UID SEARCH SUBJECT \"$SUBJ\"" | awk '{print $NF}' | tr -d '\r')
run "curl imap://$MAIL/INBOX --user $U2:**** -X 'UID SEARCH SUBJECT ...'" \
    curl -sS --url "imap://$MAIL/INBOX" --user "$U2:$P2" -X "UID SEARCH SUBJECT \"$SUBJ\""
if [[ "$UID_MSG" =~ ^[0-9]+$ ]]; then
    run "curl imap://$MAIL/INBOX;UID=$UID_MSG --user $U2:****  (FETCH del mensaje)" \
        curl -sS --url "imap://$MAIL/INBOX;UID=$UID_MSG" --user "$U2:$P2"
else
    nota "!! No se encontró el mensaje '$SUBJ' en el INBOX de $U2"
fi
sleep 1; logs "imap\($U2\)|imap-login: Login: user=<$U2>" 4

abrir "MAIL-07_destinatario_inexistente"
run "postmap -q noexiste@$D ldap:/etc/postfix/ldap-users.cf   (sin resultado = no existe)" \
    postmap -q "noexiste@$D" ldap:/etc/postfix/ldap-users.cf
run "swaks --server $MAIL --port 587 -tls --auth-user $U1 --to noexiste@$D" \
    swaks --server "$MAIL" --port 587 -tls --auth LOGIN --auth-user "$U1" --auth-password "$P1" \
          --from "$U1@$D" --to "noexiste@$D" --header "Subject: MAIL-07"
sleep 1; logs "User unknown" 3

abrir "INT-03_ss_mail"
run "ss -lntup" ss -lntup
run "systemctl is-enabled postfix dovecot" systemctl is-enabled postfix dovecot
run "systemctl is-active postfix dovecot"  systemctl is-active postfix dovecot

abrir "INT-04_logs_mail"
logs "postfix|dovecot" 80

# Nunca dejar contraseñas en las evidencias
# (en texto plano y en base64, que es como swaks las muestra en AUTH LOGIN)
for P in "$P1" "$P2"; do
    for S in "$P" "$(printf '%s' "$P" | base64 -w0)"; do
        SECRETO="$S" perl -pi -e 's/\Q$ENV{SECRETO}\E/****/g' "$EV"/*.txt
    done
done
[[ -n "${SUDO_USER:-}" ]] && chown -R "$SUDO_USER": "$(pwd)/evidencias"

echo
echo "==> Evidencias en $EV:"
ls -1 "$EV"
