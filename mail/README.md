# Correo: Postfix + Dovecot (Integrante 4)

**Host:** `mail.restaurante.redes.test` · **IP:** `<subred>.13` · **Puertos:** 25, 587, 143 (+993 IMAPS) · **Puntos:** 25
**Pruebas:** MAIL-01 a MAIL-07. El Integrante 4 prepara el servidor y los logs; el Integrante 6 ejecuta desde el cliente (CLAUDE.md §7).

---

## 1. Cómo funciona

```
Thunderbird ──SMTP 587 + AUTH──> Postfix ──LMTP──> Dovecot ──> /var/vmail/<uid>/Maildir
 (cliente)                         │                 │
                          ¿existe el destino?   ¿contraseña correcta?
                                   └────> OpenLDAP <─┘   (ldap.restaurante.redes.test)
Thunderbird <──IMAP 143───────────────────── Dovecot
```

- **Postfix** recibe y envía (SMTP). Para cada destinatario busca `mail=<dirección>` en `ou=People`; si no existe, responde `550 5.1.1 User unknown` (MAIL-07).
- **Dovecot** guarda los buzones (Maildir, usuario de sistema `vmail`) y sirve IMAP. Autentica con un **bind LDAP** como `uid=<usuario>,ou=People,dc=restaurante,dc=redes,dc=test`.
- **Postfix usa Dovecot SASL** para autenticar el envío (puerto 587), así que SMTP e IMAP usan las mismas credenciales LDAP.
- El inicio de sesión acepta `uid` o `uid@restaurante.redes.test`.

### Decisiones de configuración (para el PDF)
| Decisión | Motivo |
|---|---|
| Dominio **virtual** (`virtual_mailbox_domains`) + `virtual_mailbox_maps` por LDAP | Los usuarios viven en LDAP, no como cuentas Linux. Un buzón por integrante sin crear usuarios locales. |
| Entrega por **LMTP** a Dovecot | Un solo dueño del almacenamiento (Dovecot) y logs de entrega claros. |
| `auth_bind` en Dovecot | LDAP valida la contraseña. No hace falta leer `userPassword` (que no es visible) ni guardar credenciales de admin. |
| Búsquedas LDAP **anónimas** | El LDAP del grupo las permite, así que no hay contraseñas en los archivos de configuración. |
| `mynetworks = 127.0.0.0/8`, `inet_interfaces = all` | Sin IPs fijas en la configuración (CLAUDE.md §3.4). Escucha en todas las interfaces y solo relaya con autenticación. |
| Puerto **587** con `smtpd_sasl_auth_enable` y `reject` sin auth | Los clientes envían autenticados. El 25 recibe correo para el dominio, pero no es open relay. |
| STARTTLS con certificado autofirmado (snakeoil), login sin TLS permitido | Es un laboratorio sin CA. Thunderbird pide aceptar una excepción. |
| Servicios con `systemctl enable` | Persistencia tras reinicio (INT-02). |

---

## 2. Archivos

```
mail/
├── README.md
├── scripts/
│   ├── 1-instalar-paquetes.sh   instala Postfix, Dovecot 2.3, ldap-utils, swaks (necesita internet)
│   ├── 2-configurar-red.sh      netplan: <subred>.13, gw <subred>.1, DNS <subred>.10; verifica DNS/MX/LDAP
│   ├── 3-configurar-correo.sh   configura Postfix + Dovecot + LDAP (respalda *.orig antes de modificar)
│   ├── 4-pruebas-correo.sh      MAIL-01..07, INT-03, INT-04 → evidencias/mail/<ID>_<desc>.txt
│   ├── 5-exportar-config.sh     copia la config final del servidor a export/mail/
│   └── 6-modo-individual.sh     DNS + LDAP de prueba locales para probar el correo sin el grupo (ver §4b)
└── (después del paso 5) main.cf, master.cf, ldap-users.cf, postconf-n.txt, dovecot/
```

---

## 3. Estado

| | Estado |
|---|---|
| VM `mail-restaurante`: Ubuntu Server 24.04.5, 4 GB RAM, 2 CPU, usuario `isamail` | ✅ |
| Paso 1: paquetes (Dovecot 2.3) | ✅ |
| Paso 3: Postfix 25/587 y Dovecot 143/993 escuchando, servicios habilitados | ✅ |
| Red en **NAT** con reenvío 2222→22 (`ssh -p 2222 isamail@127.0.0.1`) | ✅ provisional |
| Paso 2: IP fija `.13` en adaptador puente | ⏳ día de la prueba |
| Paso 4: evidencias | ⏳ día de la prueba |
| Paso 5: config final en el repo | ⏳ |

---

## 4. Día de la prueba (en orden)

Todos conectados al **router u hotspot del grupo**, no a la Wi-Fi de la universidad.

1. **Exportar la config** (se puede hacer antes, aún en NAT):
   ```bash
   cd ~/correo && sudo bash 5-exportar-config.sh
   ```
2. **Adaptador puente:** con la VM apagada, *VirtualBox → Configuración → Red → Adaptador 1 → Adaptador puente*. Enciéndela y entra desde la ventana de VirtualBox.
3. **Red** (cuando el grupo confirme la subred y que `.13` está fuera del rango DHCP):
   ```bash
   cd ~/correo && sudo bash 2-configurar-red.sh
   ```
   Solo pide la subred (ej. `192.168.50`). Todo debe salir `[OK]`. Si `mail` o el MX fallan, avisar al Integrante 1.
   Desde aquí, el SSH es `ssh isamail@<subred>.13`.
4. **Comprobar que Postfix ve el LDAP:**
   ```bash
   postmap -q <uid>@restaurante.redes.test ldap:/etc/postfix/ldap-users.cf
   ```
   Debe imprimir el correo. Si no, ese usuario no tiene `mail` en LDAP (avisar al Integrante 2).
5. **Logs en vivo** en una segunda ventana SSH mientras el Integrante 6 prueba con Thunderbird:
   ```bash
   sudo tail -f /var/log/mail.log
   ```
6. **Evidencias del servidor** (2 usuarios LDAP; las contraseñas se ocultan con `****` en los archivos):
   ```bash
   cd ~/correo && sudo bash 4-pruebas-correo.sh <uid1> '<pass1>' <uid2> '<pass2>'
   ```
7. **INT-02:** `sudo reboot`, y luego repetir el paso 6 (o lo básico desde Thunderbird).
8. **Traer los archivos al repo** (PowerShell, en la carpeta `r-lab5`):
   ```bash
   scp -r isamail@<subred>.13:~/correo/evidencias/mail evidencias/
   ```
   ```bash
   scp -r isamail@<subred>.13:~/correo/export/mail/* mail/
   ```

---

## 4b. Modo individual (pruebas sin la red del grupo)

Si el grupo no puede conectarse al mismo tiempo, `6-modo-individual.sh` instala **en la VM de correo** un BIND9 y un OpenLDAP mínimos que imitan los del grupo: mismos FQDN, base `dc=restaurante,dc=redes,dc=test`, `ou=People` y atributos `uid/cn/sn/mail/userPassword`. La configuración del correo **no cambia**, y las evidencias del paso 4 llevan la línea `# MODO INDIVIDUAL: ...`.

```bash
cd ~/correo && sudo bash 6-modo-individual.sh <uid1> '<pass1>' <uid2> '<pass2>'
```
```bash
sudo bash 4-pruebas-correo.sh <uid1> '<pass1>' <uid2> '<pass2>'
```

Para volver al modo de grupo: `sudo systemctl disable --now named slapd && sudo rm /etc/lab5-modo-individual`, y luego el paso 2.

---

## 5. Para el Integrante 6 (cliente)

**DNS del equipo:** solo `ns1` (`<subred>.10`). Comprobar con `nslookup mail.restaurante.redes.test`.

**Thunderbird:** *Nueva cuenta → nombre, `<uid>@restaurante.redes.test`, contraseña LDAP → Configurar manualmente:*

| | Servidor | Puerto | Seguridad | Autenticación | Usuario |
|---|---|---|---|---|---|
| Entrante IMAP | `mail.restaurante.redes.test` | 143 | STARTTLS | Contraseña normal | `<uid>` |
| Saliente SMTP | `mail.restaurante.redes.test` | 587 | STARTTLS | Contraseña normal | `<uid>` |

Aceptar la excepción del certificado autofirmado. Configurar **2 cuentas**.

| ID | Desde el cliente (captura) | Del servidor (Integrante 4) |
|---|---|---|
| MAIL-01 | `MAIL-01_dig_mail_mx.png`: `dig mail.restaurante.redes.test` y `dig restaurante.redes.test MX` | `MAIL-01_dig_mail_mx.txt` |
| MAIL-02 | `MAIL-02_config_thunderbird.png`: configuración manual | — |
| MAIL-03 | `MAIL-03_auth_valida.png`: bandeja abierta | `MAIL-03_auth_valida.txt` (`imap-login: Login: user=<…>`) |
| MAIL-04 | `MAIL-04_auth_invalida.png`: error de contraseña | `MAIL-04_auth_invalida.txt` (`auth failed`) |
| MAIL-05 | `MAIL-05_envio_smtp.png`: correo en Enviados | `MAIL-05_envio_smtp.txt` (`sasl_username=…`, `status=sent`) |
| MAIL-06 | `MAIL-06_lectura_imap.png`: correo recibido abierto | `MAIL-06_lectura_imap.txt` |
| MAIL-07 | `MAIL-07_destinatario_inexistente.png`: error al enviar a `noexiste@…` | `MAIL-07_destinatario_inexistente.txt` (`550 5.1.1 User unknown`) |
| INT-03 | — | `INT-03_ss_mail.txt` (`ss -lntup`) |
| INT-04 | — | `INT-04_logs_mail.txt` |

⚠️ Durante **WEB-05** (LDAP detenido), el correo tampoco autentica. No probar correo en ese momento.

---

## 6. Si algo falla

| Síntoma | Revisar |
|---|---|
| Thunderbird no encuentra el servidor | El cliente no usa ns1, o falta `mail` en la zona |
| `auth failed` con la contraseña correcta | `ldapwhoami -x -H ldap://ldap.restaurante.redes.test -D "uid=<uid>,ou=People,dc=restaurante,dc=redes,dc=test" -W` y `sudo doveadm log errors` |
| `User unknown` con un usuario que existe | Le falta el atributo `mail` en LDAP (paso 4.4) |
| El correo no llega | `mailq`, `grep lmtp /var/log/mail.log` |
| El SSH se congela | **Enter, `~`, `.`**, o cerrar PowerShell |

**Apagar la VM:** `sudo shutdown now` (o *Máquina → Apagado ACPI*). "Apagar la máquina" solo si está totalmente trabada.
