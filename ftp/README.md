# Servidor FTP (vsftpd)

Servidor FTP del laboratorio, accesible como `ftp.restaurante.redes.test` con la IP `<subred>.14`.

## Contenido

```
ftp/
├── README.md                      Guía de instalación y pruebas
├── KIT-CLIENTE.md                 Pruebas FTP-01 a FTP-08 desde el cliente
├── vsftpd.conf                    Configuración del servidor
├── vsftpd.userlist                Usuarios permitidos
├── setup.sh                       Instalación y configuración
├── red/cambiar-ip.sh              Asignación de IP fija con netplan
├── archivos/menu-restaurante.txt  Archivo de prueba para descargas
├── pruebas/
│   ├── verificar.sh               Pruebas desde el cliente
│   ├── recolectar-evidencias.sh   Evidencias del servidor
│   └── capturar-trafico.sh        Captura de control y datos
└── informe/seccion-ftp.md         Sección FTP del informe
```

Las evidencias se guardan en `evidencias/ftp/cliente/` y `evidencias/ftp/servidor/`.

## Decisiones de diseño

| Decisión | Motivo |
|----------|--------|
| Usuario local `ftpuser` | El enunciado no exige LDAP para FTP; se evita depender de otro servicio |
| Directorio restringido `/srv/ftp/ftpuser`, propiedad de root | Restringe al usuario sin usar `allow_writeable_chroot` |
| Solo `subidas/` admite escritura | Los permisos del sistema de archivos impiden escribir en otras rutas |
| Lista de usuarios permitidos | Cualquier usuario distinto de `ftpuser` es rechazado con 530 |
| Modo pasivo en 40000-40100 | Rango limitado, abierto en ufw |
| Sin IPs en `vsftpd.conf` | Un cambio de red solo requiere modificar netplan |
| Sin TLS | Permite observar la conexión de control en la captura de tráfico |

## Procedimiento

Los comandos se ejecutan en la VM del servidor FTP, desde la raíz del repositorio, salvo indicación contraria.

### 1. Preparación de la VM

1. Instalar Ubuntu Server 24.04 con el adaptador de red en modo puente y asignar `ftp` como nombre del equipo (`sudo hostnamectl set-hostname ftp`).
2. Clonar el repositorio:
   ```bash
   sudo apt install -y git
   git clone <url-del-repositorio> r-lab5 && cd r-lab5
   ```

### 2. Instalación

Requiere acceso a Internet, por lo que debe hacerse antes de asignar la IP del laboratorio.

```bash
sudo bash ftp/setup.sh
```

El script solicita la contraseña de `ftpuser`. Esta contraseña no debe guardarse en el repositorio. El script:

- instala vsftpd, crea el usuario y configura el directorio con sus permisos;
- instala `vsftpd.conf` y respalda el original en `/etc/vsftpd.conf.original`;
- habilita ufw con los puertos 22, 20, 21 y 40000-40100;
- habilita el servicio al arranque, verifica el acceso y muestra el SHA-256 del archivo de prueba.

Puede ejecutarse de nuevo después de modificar `vsftpd.conf`.

### 3. IP provisional

Antes de conectarse a la red del laboratorio, se usa una IP provisional con el mismo octeto `.14`, fuera del rango DHCP del router. Mientras ns1 no esté disponible, el router funciona como DNS:

```bash
sudo bash ftp/red/cambiar-ip.sh 192.168.1 192.168.1.1 192.168.1.1
```

### 4. Pruebas preliminares

Desde otra máquina Linux de la misma red:

```bash
HOST=192.168.1.14 bash ftp/pruebas/verificar.sh
```

Todas las pruebas deben resultar `OK`, excepto FTP-01, que se omite al usar una IP. Estas salidas no constituyen la evidencia final.

### 5. Registro DNS

La zona `restaurante.redes.test` debe incluir:

```
ftp    IN  A   <subred>.14
```

### 6. Pruebas en la red del laboratorio

1. Asignar la IP definitiva, con ns1 como DNS:
   ```bash
   sudo bash ftp/red/cambiar-ip.sh <subred>
   ```
2. Verificar la resolución: `dig ftp.restaurante.redes.test +short`.
3. Iniciar la captura de tráfico en el servidor:
   ```bash
   sudo bash ftp/pruebas/capturar-trafico.sh
   ```
4. Ejecutar las pruebas desde el cliente según `KIT-CLIENTE.md` y detener la captura con Ctrl+C.
5. Para INT-02, reiniciar el servidor (`sudo reboot`) y repetir FTP-02 y FTP-05.
6. Recolectar las evidencias del servidor:
   ```bash
   sudo bash ftp/pruebas/recolectar-evidencias.sh
   ```
7. Guardar las capturas de pantalla en `evidencias/ftp/` con el formato `FTP-0X_descripcion.png` y subir las evidencias:
   ```bash
   git add evidencias/ftp && git commit -m "Evidencias FTP" && git push
   ```
8. Abrir `evidencias/ftp/servidor/control-vs-datos.pcap` en Wireshark con el filtro `ftp || ftp-data` y tomar una captura de pantalla.

### 7. Informe

Completar los campos `[COMPLETAR]` de `informe/seccion-ftp.md` con la IP final y las evidencias.

## Lista de verificación

- [ ] `setup.sh` ejecutado y pruebas preliminares correctas
- [ ] Registro `ftp` agregado en la zona DNS
- [ ] IP definitiva asignada y `dig` resuelve correctamente
- [ ] FTP-01 a FTP-08 correctas usando el FQDN
- [ ] Reinicio realizado y pruebas repetidas (INT-02)
- [ ] Evidencias del servidor y captura de tráfico guardadas
- [ ] Sección del informe completa

## Problemas frecuentes

| Síntoma | Causa y solución |
|---------|------------------|
| `500 OOPS: refusing to run with writable root inside chroot()` | El directorio raíz del usuario es escribible. Ejecutar `setup.sh` de nuevo |
| `530 Login incorrect` con la contraseña correcta | El usuario no está en `/etc/vsftpd.userlist` o `/usr/sbin/nologin` no está en `/etc/shells`. Ejecutar `setup.sh` de nuevo |
| La conexión se establece pero `ls` no responde | Los puertos pasivos están bloqueados. Verificar `sudo ufw status` |
| Funciona por IP pero no por nombre | Falta el registro A o el cliente no usa ns1 como DNS |
| `bash: $'\r': command not found` | El script tiene finales de línea CRLF. Corregir con `find ftp -name '*.sh' -exec sed -i 's/\r$//' {} +` |
| `apt` falla después de cambiar la IP | ns1 no resuelve nombres externos. Instalar los paquetes antes de cambiar la IP |
