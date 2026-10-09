#!/usr/bin/env bash
# Pone IP fija, DNS del grupo y hostname ldap.restaurante.redes.test (persiste al reiniciar).
# Correr DESPUÉS de setup_ldap.sh (setup necesita internet por DHCP para apt).
#
# Uso: sudo ./configurar_red.sh <ip/prefijo> <gateway> <ip_dns_bind>
#  ej: sudo ./configurar_red.sh 192.168.1.50/24 192.168.1.1 192.168.1.10
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Correr con sudo"; exit 1; }
[[ $# -eq 3 ]] || { echo "Uso: sudo $0 <ip/prefijo> <gateway> <ip_dns_bind>"; exit 1; }
IP="$1"; GW="$2"; DNS="$3"
[[ $IP == */* ]] || { echo "La IP lleva prefijo, ej 192.168.1.50/24"; exit 1; }

IFACE=$(ip route | awk '/^default/ {print $5; exit}')
[[ -n $IFACE ]] || { echo "No encontré la interfaz con ruta por defecto"; exit 1; }
echo "Interfaz: ${IFACE}"

# Que cloud-init no sobrescriba la red al reiniciar
echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg 2>/dev/null || true

cat > /etc/netplan/99-lab5.yaml <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${IP}]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${DNS}]
        search: [restaurante.redes.test]
EOF
chmod 600 /etc/netplan/99-lab5.yaml
# Los otros yaml (ej. 50-cloud-init.yaml) piden DHCP en la misma interfaz; se apartan
for f in /etc/netplan/*.yaml; do
  [[ $f == /etc/netplan/99-lab5.yaml ]] || mv "$f" "${f}.bak"
done

hostnamectl set-hostname ldap.restaurante.redes.test
netplan apply

echo
ip -4 addr show "$IFACE"
resolvectl status "$IFACE" | grep -E 'DNS Servers|DNS Domain' || true
