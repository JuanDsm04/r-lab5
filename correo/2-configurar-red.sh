#!/usr/bin/env bash
# =====================================================================
#  Lab 5 - Correo. PASO 2: red de la VM (IP + DNS del grupo)
#  Pregunta los datos al correrlo. Vuelve a correrlo CADA VEZ que
#  cambien de red / cambie la IP de ns1.
#  Uso:  sudo bash 2-configurar-red.sh
# =====================================================================
set -uo pipefail
DOMINIO="restaurante.redes.test"
NETPLAN=/etc/netplan/99-lab5.yaml

if [[ $EUID -ne 0 ]]; then echo "Ejecutar con sudo"; exit 1; fi

IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
[[ -z "$IFACE" ]] && IFACE=$(ls /sys/class/net | grep -v lo | head -1)
echo "Interfaz de red: $IFACE"
echo "IP actual:       $(ip -4 -o addr show "$IFACE" | awk '{print $4}')"
echo "Gateway actual:  $(ip route show default | awk '{print $3; exit}')"
echo

read -rp "IP del DNS del grupo (ns1): " NS1
read -rp "¿IP fija para esta VM? (s = fija / n = automática DHCP) [n]: " FIJA

if [[ "${FIJA,,}" == "s" ]]; then
    read -rp "IP fija con máscara (ej. 192.168.1.30/24): " MIIP
    read -rp "Gateway (ej. 192.168.1.1): " GW
    cat > "$NETPLAN" <<EOF
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: false
      addresses: [$MIIP]
      routes: [{to: default, via: $GW}]
      nameservers:
        addresses: [$NS1]
        search: [$DOMINIO]
EOF
else
    cat > "$NETPLAN" <<EOF
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: true
      dhcp4-overrides: {use-dns: false}
      nameservers:
        addresses: [$NS1]
        search: [$DOMINIO]
EOF
fi
chmod 600 "$NETPLAN"
netplan apply
sleep 3

MI_IP=$(ip -4 -o addr show "$IFACE" | awk '{print $4}' | cut -d/ -f1 | head -1)
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
    || bad "mail.$DOMINIO apunta a '${R_MAIL:-nada}', pero esta VM es $MI_IP"
N=$(ldapsearch -x -LLL -H "ldap://ldap.$DOMINIO" -b "ou=People,dc=${DOMINIO//./,dc=}" "(uid=*)" mail 2>/dev/null | grep -c '^mail:')
[[ "$N" -gt 0 ]] && ok "LDAP responde: $N usuarios con correo" || bad "No pude consultar el LDAP"

echo
echo "------------------------------------------------------------------"
echo " Mensaje para quien maneja el DNS (si algo de arriba falló):"
echo "   mail  IN  A   $MI_IP"
echo "   @     IN  MX  10 mail.$DOMINIO."
echo "   (y subir el serial de la zona)"
echo "------------------------------------------------------------------"
echo " Para volver a internet normal (DHCP): sudo rm $NETPLAN && sudo netplan apply"
