#!/usr/bin/env bash
# Asigna la IP fija del servidor FTP mediante netplan.
#
# Uso:
#   sudo bash ftp/red/cambiar-ip.sh <subred> [gateway] [dns]
#
#   subred   Primeros tres octetos de la red, por ejemplo 192.168.50.
#   gateway  Por defecto <subred>.1.
#   dns      Por defecto <subred>.10 (ns1).
#
# La IP asignada siempre es <subred>.14.
#
# Ejemplos:
#   IP provisional, usando el router como DNS:
#     sudo bash ftp/red/cambiar-ip.sh 192.168.1 192.168.1.1 192.168.1.1
#   Red del laboratorio:
#     sudo bash ftp/red/cambiar-ip.sh 192.168.50
#
# Variables opcionales: IFACE (interfaz de red) y PREFIJO (por defecto 24).
# Si se ejecuta por SSH, la sesión se interrumpe al cambiar la IP.
set -euo pipefail

OCTETO=14
DOMINIO="restaurante.redes.test"
PREFIJO="${PREFIJO:-24}"
DESTINO="/etc/netplan/01-lab5.yaml"

uso() { sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
error() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
valida_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || error "IP inválida: $1"; }

[ "$(id -u)" -eq 0 ] || error "El script debe ejecutarse con sudo."
[ $# -ge 1 ] || uso

SUBRED="${1%.}"
[[ "$SUBRED" =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]] || error "La subred debe tener tres octetos, por ejemplo 192.168.50."
IP="${SUBRED}.${OCTETO}"
GW="${2:-${SUBRED}.1}"
DNS="${3:-${SUBRED}.10}"
valida_ip "$GW"; valida_ip "$DNS"

# Interfaz de la ruta por defecto o, en su ausencia, la primera distinta de lo.
IFACE="${IFACE:-$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')}"
[ -n "$IFACE" ] || IFACE="$(ip -o link show | awk -F': ' '$2 != "lo" {sub(/@.*/, "", $2); print $2; exit}')"
[ -n "$IFACE" ] || error "No se pudo detectar la interfaz. Indíquela con IFACE=<nombre>."

echo "Interfaz: $IFACE"
echo "IP:       $IP/$PREFIJO"
echo "Gateway:  $GW"
echo "DNS:      $DNS (dominio de búsqueda: $DOMINIO)"
echo

# Se desactivan otras configuraciones de netplan para evitar conflictos.
for f in /etc/netplan/*.yaml; do
    [ -e "$f" ] || continue
    [ "$f" = "$DESTINO" ] && continue
    mv "$f" "$f.respaldo-lab5"
    echo "Respaldado: $f -> $f.respaldo-lab5"
done

# Evita que cloud-init restablezca la configuración de red al reiniciar.
if [ -d /etc/cloud/cloud.cfg.d ]; then
    echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
fi

cat > "$DESTINO" <<EOF
# Generado por ftp/red/cambiar-ip.sh para ftp.${DOMINIO}.
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      dhcp6: false
      addresses: [${IP}/${PREFIJO}]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${DNS}]
        search: [${DOMINIO}]
EOF
chmod 600 "$DESTINO"

netplan generate || error "netplan rechazó la configuración de $DESTINO."
netplan apply
sleep 2

echo
ip -4 -brief addr show "$IFACE"
echo "Ruta por defecto: $(ip -4 route show default | head -1)"
if command -v resolvectl >/dev/null; then
    echo "DNS en uso:      $(resolvectl dns "$IFACE" 2>/dev/null | cut -d: -f2-)"
fi
echo
echo "Configuración aplicada. Registro requerido en la zona DNS:"
echo "  ftp    IN  A   ${IP}"
