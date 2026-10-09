# DNS — ns1.restaurante.redes.test

Servidor DNS autoritativo del grupo (BIND9) para la zona `restaurante.redes.test`.

## Archivos de esta carpeta

| Archivo | Ubicación en el servidor | Para qué sirve |
|---|---|---|
| `named.conf.options` | `/etc/bind/named.conf.options` | Opciones globales: interfaces, quién puede consultar, recursión |
| `named.conf.local` | `/etc/bind/named.conf.local` | Declara la zona del grupo |
| `db.restaurante.redes.test` | `/etc/bind/zones/db.restaurante.redes.test` | Archivo de zona (entregable c) |
| `pruebas_dns.sh` | — | Pruebas automatizadas y generación de evidencias |

## Pruebas automatizadas

`pruebas_dns.sh` ejecuta las pruebas DNS de la matriz, indica cuáles pasan y guarda
la salida de cada comando en `evidencias/`.

### Requisitos

- `dig` (`sudo apt install -y dnsutils`).
- El equipo debe estar en la misma red que ns1.
- La primera vez: `chmod +x dns/pruebas_dns.sh`.

### Uso

Desde la raíz del repositorio:

```bash
# Desde el cliente o cualquier otro equipo de la red
./dns/pruebas_dns.sh

# Indicando el servidor por IP (útil si el equipo aún no usa a ns1 como DNS)
./dns/pruebas_dns.sh 192.168.1.10

# En el propio ns1: agrega validación de archivos, servicio, puertos y logs
sudo ./dns/pruebas_dns.sh
```

Sin argumento, el script consulta a `ns1.restaurante.redes.test`. Siempre le pregunta
directamente a BIND (`dig @servidor`), no al resolvedor local de Ubuntu
(`127.0.0.53`), porque este último quita el flag `aa` y rechaza las consultas
`+norecurse`, lo que haría fallar DNS-03.

### Qué verifica

Pruebas que se ejecutan desde cualquier equipo:

| ID | Comando | Se considera correcta si |
|---|---|---|
| DNS-01 | `dig @ns1 ns1.restaurante.redes.test A` | La IP termina en `.10` |
| DNS-02 | `dig @ns1 <host>.restaurante.redes.test A` para ldap, www, mail y ftp | Las IPs terminan en `.11`, `.12`, `.13` y `.14` |
| DNS-03 | `dig @ns1 restaurante.redes.test SOA +norecurse` | `status: NOERROR`, flag `aa` y SOA con `ns1` como servidor primario |
| DNS-04 | `dig @ns1 restaurante.redes.test MX` | El MX apunta a `mail.restaurante.redes.test.` |
| DNS-NS | `dig @ns1 restaurante.redes.test NS` | El NS es `ns1.restaurante.redes.test.` |
| DNS-05 | `dig @ns1 noexiste.restaurante.redes.test A` | `status: NXDOMAIN` |

Pruebas adicionales, solo cuando el script se corre en ns1:

| ID | Comando | Se considera correcta si |
|---|---|---|
| CHECKCONF | `named-checkconf` | No imprime errores |
| CHECKZONE | `named-checkzone restaurante.redes.test <archivo>` | Termina en `OK` |
| INT-02 | `systemctl status named` | El servicio está activo y habilitado al arranque |
| INT-03 | `ss -lntup` | El puerto 53 escucha en udp y tcp |
| INT-04 | `journalctl -u named` | Solo guarda el extracto de logs; no se evalúa |

Las IPs se comparan solo por el último octeto (tabla 3.2 del plan), así que el script
funciona igual en cualquier subred. Si el grupo cambia un octeto, se edita el arreglo
`OCTETO` al inicio del script.

Para INT-02, reiniciar ns1 (`sudo reboot`) y volver a correr el script: si todo pasa
después del reinicio, la configuración es persistente.

### Resultado

```
Zona: restaurante.redes.test   Servidor consultado: ns1.restaurante.redes.test   Desde: ns1
------------------------------------------------------------------
[ OK  ] DNS-01   ns1.restaurante.redes.test -> 172.20.10.10
[ OK  ] DNS-02   ldap=172.20.10.11 www=172.20.10.12 mail=172.20.10.13 ftp=172.20.10.14
[ OK  ] DNS-03   SOA autoritativo (flag aa), serial 2026100801
[ OK  ] DNS-04   MX -> 10 mail.restaurante.redes.test.
[ OK  ] DNS-NS   NS -> ns1.restaurante.redes.test.
[ OK  ] DNS-05   noexiste.restaurante.redes.test -> NXDOMAIN
------------------------------------------------------------------
Pasaron: 6   Fallaron: 0
```

Código de salida: `0` si todas las pruebas pasan, `1` si alguna falla, `2` si falta
`dig` o el servidor no responde.

### Evidencias generadas

Cada archivo incluye el hostname, la fecha, el comando ejecutado y su salida completa.

```
evidencias/
├── dns/
│   ├── DNS-01_dig_ns1.txt
│   ├── DNS-02_dig_servicios.txt
│   ├── DNS-03_dig_soa.txt
│   ├── DNS-04_dig_mx.txt
│   ├── DNS-05_dig_nxdomain.txt
│   ├── DNS-NS_dig_ns.txt
│   ├── DNS-CHK_named-checkconf.txt      (solo en ns1)
│   └── DNS-CHK_named-checkzone.txt      (solo en ns1)
└── integracion/                          (solo en ns1)
    ├── INT-02_dns_systemctl_named.txt
    ├── INT-03_dns_ss_puertos.txt
    └── INT-04_dns_logs_named.txt
```

Estos `.txt` respaldan las capturas de pantalla, no las reemplazan: el informe sigue
usando capturas `.png` con el formato `<ID-PRUEBA>_<descripcion>.png`. Cada corrida
sobrescribe los archivos anteriores.

### Si algo falla

| Síntoma | Causa probable | Qué revisar |
|---|---|---|
| "El servidor ... no responde consultas DNS" | ns1 apagado, otra red, o nombre sin resolver | `ping` a ns1; pasar la IP como argumento; en ns1, `systemctl status named` y `sudo ufw allow 53` |
| DNS-01 o DNS-02 con octeto distinto | La zona no coincide con la tabla 3.2 | Corregir el registro A, subir el serial, `sudo rndc reload` |
| DNS-03 sin flag `aa` | La consulta no llegó a BIND | Confirmar que el servidor indicado es ns1 |
| DNS-04 o DNS-NS "sin respuesta" | Falta el registro en la zona | Revisar las líneas `MX` y `NS` del archivo de zona |
| CHECKZONE falla | Error de sintaxis en la zona | Leer `evidencias/dns/DNS-CHK_named-checkzone.txt` |
| INT-02 falla | Servicio detenido o sin `enable` | `sudo systemctl enable --now named` |
| INT-04 vacío | Faltan permisos para leer los logs | Correr el script con `sudo` |

## Cambio de red

`named.conf.options` y `named.conf.local` no contienen IPs y no se modifican.
Solo cambian la red de la VM y el archivo de zona:

```bash
# 1. IP fija de ns1: <subred>.10, gateway real, DNS <subred>.10 (netplan o Ajustes)

# 2. Zona: reemplazar el prefijo actual por el nuevo y subir el serial
sudo sed -i 's/PREFIJO\.ACTUAL\./PREFIJO.NUEVO./g' /etc/bind/zones/db.restaurante.redes.test
sudo nano /etc/bind/zones/db.restaurante.redes.test      # serial AAAAMMDDnn

# 3. Validar, recargar y probar
sudo named-checkzone restaurante.redes.test /etc/bind/zones/db.restaurante.redes.test
sudo rndc reload
sudo ./dns/pruebas_dns.sh
```