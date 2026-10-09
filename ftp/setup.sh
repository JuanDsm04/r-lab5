#!/usr/bin/env bash
# Instala y configura vsftpd para ftp.restaurante.redes.test.
# Uso: sudo bash ftp/setup.sh
#
# Variables opcionales:
#   FTP_USER      Usuario FTP (por defecto ftpuser).
#   FTP_PASS      Contraseña. Si no se define, se solicita al ejecutar.
#   SIN_FIREWALL  Si vale 1, no se modifica ufw.
#
# Puede ejecutarse varias veces. Requiere acceso a Internet para instalar paquetes.
set -euo pipefail

FTP_USER="${FTP_USER:-ftpuser}"
JAIL="/srv/ftp/${FTP_USER}"
PASV_MIN=40000
PASV_MAX=40100
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

paso()  { printf '\n\033[1;34m%s\033[0m\n' "$*"; }
ok()    { printf '  [OK] %s\n' "$*"; }
aviso() { printf '  [AVISO] %s\n' "$*"; }
error() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "El script debe ejecutarse con sudo."
[ -f "$DIR/vsftpd.conf" ] || error "No se encontró $DIR/vsftpd.conf."

# Paquetes. Solo se instalan los que falten.
paso "1/7 Instalación de paquetes"
export DEBIAN_FRONTEND=noninteractive
PAQUETES=(vsftpd ftp curl tcpdump bind9-dnsutils)
FALTAN=()
for p in "${PAQUETES[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || FALTAN+=("$p")
done
if [ ${#FALTAN[@]} -gt 0 ]; then
    apt-get update -qq
    apt-get install -y -qq "${FALTAN[@]}" >/dev/null
fi
ok "vsftpd $(dpkg-query -W -f='${Version}' vsftpd) instalado."

# Usuario FTP sin acceso a terminal. PAM exige que su shell esté en /etc/shells.
paso "2/7 Usuario FTP: ${FTP_USER}"
if ! grep -qx '/usr/sbin/nologin' /etc/shells; then
    echo '/usr/sbin/nologin' >> /etc/shells
    ok "/usr/sbin/nologin agregado a /etc/shells."
fi

pedir_pass() {
    if [ -n "${FTP_PASS:-}" ]; then return; fi
    local p1 p2
    while true; do
        read -rsp "  Ingrese la contraseña para ${FTP_USER}: " p1; echo
        read -rsp "  Confirme la contraseña: " p2; echo
        if [ -z "$p1" ]; then aviso "La contraseña no puede estar vacía."; continue; fi
        if [ "$p1" != "$p2" ]; then aviso "Las contraseñas no coinciden."; continue; fi
        FTP_PASS="$p1"; break
    done
}

if id "$FTP_USER" &>/dev/null; then
    ok "El usuario ya existe."
    usermod --home "$JAIL" --shell /usr/sbin/nologin "$FTP_USER" 2>/dev/null || true
    if [ -z "${FTP_PASS:-}" ]; then
        read -rp "  ¿Desea cambiar la contraseña? (s/N): " r || r=""
        if [[ "$r" =~ ^[sS]$ ]]; then pedir_pass; fi
    fi
else
    useradd --home-dir "$JAIL" --no-create-home --shell /usr/sbin/nologin \
            --user-group --comment "Usuario FTP Lab5" "$FTP_USER"
    ok "Usuario creado."
    pedir_pass
fi
if [ -n "${FTP_PASS:-}" ]; then
    echo "${FTP_USER}:${FTP_PASS}" | chpasswd
    ok "Contraseña establecida."
fi

# Directorio del usuario. La raíz y publico/ pertenecen a root; solo subidas/ es escribible.
paso "3/7 Directorios y permisos"
install -d -m 755 -o root -g root /srv/ftp
install -d -m 750 -o root -g "$FTP_USER" "$JAIL" "$JAIL/publico"
install -d -m 750 -o "$FTP_USER" -g "$FTP_USER" "$JAIL/subidas"
chown root:"$FTP_USER" "$JAIL" "$JAIL/publico";  chmod 750 "$JAIL" "$JAIL/publico"
chown "$FTP_USER":"$FTP_USER" "$JAIL/subidas";   chmod 750 "$JAIL/subidas"
install -m 640 -o root -g "$FTP_USER" "$DIR/archivos/menu-restaurante.txt" "$JAIL/publico/"
ok "Directorio $JAIL configurado."
ls -la "$JAIL" | sed 's/^/    /'

# Configuración de vsftpd. Se respalda la original una sola vez.
paso "4/7 Configuración de vsftpd"
if [ -f /etc/vsftpd.conf ] && [ ! -f /etc/vsftpd.conf.original ]; then
    cp -p /etc/vsftpd.conf /etc/vsftpd.conf.original
    ok "Configuración original respaldada en /etc/vsftpd.conf.original."
fi
install -m 644 -o root -g root "$DIR/vsftpd.conf" /etc/vsftpd.conf
install -m 644 -o root -g root "$DIR/vsftpd.userlist" /etc/vsftpd.userlist
grep -qx "$FTP_USER" /etc/vsftpd.userlist || echo "$FTP_USER" >> /etc/vsftpd.userlist
for f in /var/log/vsftpd.log /var/log/xferlog; do
    [ -f "$f" ] || install -m 600 -o root -g root /dev/null "$f"
done
ok "Archivos /etc/vsftpd.conf y /etc/vsftpd.userlist instalados."

# Firewall: SSH, control FTP y puertos de datos.
paso "5/7 Firewall"
if [ -n "${SIN_FIREWALL:-}" ]; then
    aviso "Omitido por SIN_FIREWALL=1."
elif ! command -v ufw >/dev/null; then
    aviso "ufw no está instalado. Paso omitido."
else
    {
        ufw allow OpenSSH
        ufw allow 20/tcp   comment 'FTP datos (modo activo)'
        ufw allow 21/tcp   comment 'FTP control'
        ufw allow ${PASV_MIN}:${PASV_MAX}/tcp comment 'FTP datos (modo pasivo)'
        ufw --force enable
    } >/dev/null 2>&1 && ok "ufw activo con los puertos 22, 20, 21 y ${PASV_MIN}-${PASV_MAX}/tcp." \
                      || aviso "No se pudo configurar ufw. Revise 'sudo ufw status'."
fi

# Servicio habilitado al arranque.
paso "6/7 Servicio"
if [ -d /run/systemd/system ]; then
    systemctl enable vsftpd >/dev/null 2>&1
    systemctl restart vsftpd
    sleep 1
    systemctl is-active --quiet vsftpd || { journalctl -u vsftpd -n 20 --no-pager; error "vsftpd no se inició."; }
    ok "vsftpd activo y habilitado al arranque."
else
    aviso "systemd no está disponible. Se inicia vsftpd manualmente."
    pkill -x vsftpd 2>/dev/null || true
    mkdir -p /var/run/vsftpd/empty
    vsftpd /etc/vsftpd.conf >/dev/null 2>&1 &
    sleep 1
fi

# Comprobación local de puerto y acceso.
paso "7/7 Comprobación"
if ss -lnt | grep -q ':21 '; then ok "El servicio escucha en el puerto 21."; else error "Ningún proceso escucha en el puerto 21."; fi
if [ -n "${FTP_PASS:-}" ]; then
    if curl -s --disable-epsv --user "${FTP_USER}:${FTP_PASS}" ftp://127.0.0.1/ | grep -q subidas; then
        ok "Inicio de sesión y listado correctos."
    else
        aviso "No fue posible listar el directorio. Revise /var/log/vsftpd.log."
    fi
else
    aviso "Prueba de acceso omitida porque no se cambió la contraseña."
fi

SHA=$(sha256sum "$JAIL/publico/menu-restaurante.txt" | cut -d' ' -f1)
IPS=$(hostname -I 2>/dev/null || true)
cat <<EOF

Servidor FTP configurado.
  Usuario:      ${FTP_USER}
  Directorio:   ${JAIL} (publico/ de solo lectura, subidas/ con escritura)
  Puertos:      21 (control), 20 (datos, modo activo), ${PASV_MIN}-${PASV_MAX} (datos, modo pasivo)
  IP actual:    ${IPS:-desconocida}
  SHA-256 de publico/menu-restaurante.txt:
    ${SHA}

Siguiente paso: sudo bash ftp/red/cambiar-ip.sh <subred> [gateway] [dns]
EOF
