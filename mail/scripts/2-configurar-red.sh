#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Correo (Integrante 4). PASO 2: red de la VM
#  Según CLAUDE.md §3: IP fija <subred>.13, gateway <subred>.1,
#  ns1 (<subred>.10) como ÚNICO DNS, search restaurante.redes.test.
#  Solo pregunta la subred: se vuelve a correr si cambia la red.
#  Uso:  sudo bash 2-configurar-red.sh
# =====================================================================
set -uo pipefail
DOMINIO="restaurante.redes.test"
OCTETO=13                              # mail = .13 (tabla 3.2)
# Nota: el plan sugiere 01-lab5.yaml, pero netplan lee los archivos en
# orden alfabético y 50-cloud-init.yaml (dhcp4: true) lo sobrescribiría.
# Por eso se usa 99-lab5.yaml, que se aplica al final.
NETPLAN=/etc/netplan/99-lab5.yaml

if [[ $EUID -ne 0 ]]; then echo "Ejecutar con sudo"; exit 1; fi

IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
[[ -z "$IFACE" ]] && IFACE=$(ls /sys/class/net | grep -v lo | head -1)
echo "Interfaz: $IFACE | IP actual: $(ip -4 -o addr show "$IFACE" | awk '{print $4}') | Gateway actual: $(ip route show default | awk '{print $3; exit}')"
echo

read -rp "Subred del día (3 primeros octetos, ej. 192.168.50): " SUB
SUB=${SUB%.}
read -rp "Gateway [${SUB}.1]: " GW;   GW=${GW:-${SUB}.1}
read -rp "DNS ns1 [${SUB}.10]: " NS1; NS1=${NS1:-${SUB}.10}
MI_IP="${SUB}.${OCTETO}"
echo "==> mail = ${MI_IP}/24 | gateway ${GW} | DNS ${NS1}"

[[ -f "$NETPLAN" ]] && cp "$NETPLAN" "${NETPLAN}.bak"
cat > "$NETPLAN" <<EOF
# Lab 5 - mail.${DOMINIO}
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${MI_IP}/24]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${NS1}]
        search: [${DOMINIO}]
EOF
chmod 600 "$NETPLAN"
netplan apply
sleep 3

ok()  { echo "  [OK]    $*"; }
bad() { echo "  [FALLA] $*"; }

echo
echo "==> Verificando dependencias del correo"
for h in ns1 ldap mail; do
    R=$(dig +short "$h.$DOMINIO" A | tail -1)
    [[ -n "$R" ]] && ok "$h.$DOMINIO -> $R" || bad "$h.$DOMINIO no resuelve"
done
MX=$(dig +short "$DOMINIO" MX)
[[ "$MX" == *"mail.$DOMINIO"* ]] && ok "MX de $DOMINIO -> $MX" || bad "No hay registro MX que apunte a mail.$DOMINIO"
R_MAIL=$(dig +short "mail.$DOMINIO" A | tail -1)
[[ "$R_MAIL" == "$MI_IP" ]] && ok "mail.$DOMINIO apunta a ESTA VM ($MI_IP)" \
    || bad "mail.$DOMINIO apunta a '${R_MAIL:-nada}', pero esta VM es $MI_IP (avisar a Integrante 1)"
N=$(ldapsearch -x -LLL -H "ldap://ldap.$DOMINIO" -b "ou=People,dc=${DOMINIO//./,dc=}" "(uid=*)" mail 2>/dev/null | grep -c '^mail:')
[[ "$N" -gt 0 ]] && ok "LDAP responde: $N usuarios con correo" || bad "No pude consultar el LDAP"

echo
echo " SSH desde Windows ahora:  ssh isamail@${MI_IP}"
echo " Registros esperados en la zona (Integrante 1):"
echo "   mail  IN  A   ${MI_IP}"
echo "   @     IN  MX  10 mail.${DOMINIO}."
