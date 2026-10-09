#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Pruebas MAIL-01..07 desde terminal (complementa capturas
#  de Thunderbird). Guarda todo en evidencias-correo-<fecha>.txt
#
#  Uso: sudo bash 4-pruebas-correo.sh <user1> <pass1> <user2> <pass2>
#  Ej:  sudo bash 4-pruebas-correo.sh dflores 'Lab5-Diego-2026' otrouser 'OtraPass'
#  (usuarios = uid de LDAP; contraseñas entre comillas simples)
# =====================================================================
set -uo pipefail
if [[ $# -ne 4 ]]; then
    echo "Uso: sudo bash $0 <user1> <pass1> <user2> <pass2>"; exit 1
fi
D="restaurante.redes.test"; U1=$1; P1=$2; U2=$3; P2=$4
MAIL="mail.$D"
OUT="evidencias-correo-$(date +%Y%m%d-%H%M).txt"
exec > >(tee "$OUT") 2>&1

t() { echo; echo "=================== $* ==================="; echo "# $(date '+%F %T')"; }

t "MAIL-01  Resolución de mail.$D y registro MX"
dig +noall +answer "$MAIL" A
dig +noall +answer "$D" MX
dig "$D" MX | grep -E 'flags|SERVER'

t "Puertos en escucha (INT-03)"
ss -lntp | grep -E ':(25|587|143|993)\s'

t "LDAP: Postfix encuentra los buzones"
postmap -q "$U1@$D" ldap:/etc/postfix/ldap-users.cf && echo "-> $U1@$D existe"
postmap -q "noexiste@$D" ldap:/etc/postfix/ldap-users.cf || echo "-> noexiste@$D NO existe en LDAP"

t "MAIL-03  Autenticación válida (Dovecot -> LDAP)"
doveadm auth test "$U1" "$P1"
curl -s --url "imap://$MAIL/" --user "$U1:$P1" -X "CAPABILITY" -v 2>&1 | grep -E '^[<>] .*(LOGIN|AUTHENTICATE|OK|NO)' | head -5

t "MAIL-04  Autenticación inválida"
doveadm auth test "$U1" "contrasena-incorrecta"
curl -s --url "imap://$MAIL/" --user "$U1:contrasena-incorrecta" -X "CAPABILITY"; echo "curl exit code: $? (67 = login denied)"

t "MAIL-05  Envío SMTP autenticado $U1 -> $U2 (puerto 587)"
SUBJ="Prueba Lab5 $(date +%H%M%S)"
swaks --server "$MAIL" --port 587 -tls \
      --auth LOGIN --auth-user "$U1" --auth-password "$P1" \
      --from "$U1@$D" --to "$U2@$D" \
      --header "Subject: $SUBJ" --body "Mensaje de prueba MAIL-05 enviado por $U1"
sleep 3

t "Entrega al buzón de $U2 (Maildir)"
ls -l "/var/vmail/$U2/Maildir/new/" 2>/dev/null | tail -5
grep -l "$SUBJ" /var/vmail/"$U2"/Maildir/new/* 2>/dev/null && echo "-> mensaje '$SUBJ' entregado"

t "MAIL-06  Lectura por IMAP como $U2"
curl -s --url "imap://$MAIL/INBOX" --user "$U2:$P2" -X "SEARCH SUBJECT \"$SUBJ\""
UID_MSG=$(curl -s --url "imap://$MAIL/INBOX" --user "$U2:$P2" -X "UID SEARCH SUBJECT \"$SUBJ\"" | awk '{print $NF}' | tr -d '\r')
[[ "$UID_MSG" =~ ^[0-9]+$ ]] && curl -s --url "imap://$MAIL/INBOX;UID=$UID_MSG" --user "$U2:$P2"

t "MAIL-07  Destinatario inexistente"
swaks --server "$MAIL" --port 587 -tls \
      --auth LOGIN --auth-user "$U1" --auth-password "$P1" \
      --from "$U1@$D" --to "noexiste@$D" --header "Subject: MAIL-07"

t "INT-04  Logs de Postfix y Dovecot (últimos 10 min)"
if [[ -f /var/log/mail.log ]]; then
    tail -n 300 /var/log/mail.log | grep -E "postfix|dovecot" | tail -n 60
else
    journalctl --since "10 min ago" -u dovecot -u 'postfix*' --no-pager | tail -n 60
fi

echo; echo ">>> Evidencias guardadas en $OUT"
