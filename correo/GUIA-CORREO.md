# Ejercicio 4: Servidor de correo (Postfix + Dovecot + LDAP + Thunderbird)

Dominio del grupo: `restaurante.redes.test` (en el texto, `X.redes.test` = `restaurante.redes.test`).

## 0. Cómo funciona

```
 Thunderbird (Ana) --SMTP 587 + AUTH-->  Postfix --LMTP-->  Dovecot --> /var/vmail/luis/Maildir
                                           |   \                 ^
                                 ¿existe luis@...?  ¿pass de ana?  |
                                           v     v                |
                                        OpenLDAP (ldap.X)         |
 Thunderbird (Luis) <------------- IMAP 143 ----------------------+  (Dovecot valida la pass contra LDAP)
```

- **Postfix** recibe y envía correo por SMTP. Antes de aceptar un correo, le pregunta a LDAP si el destinatario existe (atributo `mail`). Si no existe, responde `550 User unknown`, que es lo que pide MAIL-07.
- **Dovecot** guarda los buzones y los sirve por IMAP. Para autenticar hace un *bind* a LDAP con `uid=<usuario>,ou=People,...` y la contraseña que escribiste. Si LDAP acepta, el login es válido.
- Postfix **no** revisa contraseñas por su cuenta: delega la autenticación SMTP a Dovecot por un socket (SASL). Así, SMTP e IMAP usan las mismas credenciales LDAP.
- Todos los buzones viven en `/var/vmail/<uid>/Maildir` y pertenecen al usuario de sistema `vmail`. Los usuarios LDAP no necesitan una cuenta Linux.

## 1. Datos del grupo

- **LDAP**: `ldap://ldap.restaurante.redes.test`, base `ou=People,dc=restaurante,dc=redes,dc=test`, búsqueda anónima permitida y usuarios con `uid` y `mail`. Esto ya está configurado en los scripts.
- **DNS**: quien lo maneja debe agregar `mail IN A <IP de tu VM>` y `@ IN MX 10 mail.restaurante.redes.test.`. El script 2 te imprime ese texto con tu IP real.
- **Usuarios de prueba**: los uid y las contraseñas están en la tabla que pasó el compañero de LDAP. Solo se escriben al correr el script 4, no se guardan en ningún archivo.

> Nota: en Thunderbird puedes escribir como usuario tanto `dflores` como `dflores@restaurante.redes.test`, porque Dovecot le quita el dominio antes de validar contra LDAP.
> Si alguien corre la prueba WEB-05 (detener LDAP), el correo tampoco va a autenticar en ese momento. Es lo esperado.

## 2. Preparar la VM

- **Ubuntu Server 24.04 LTS**, con la red de VirtualBox en **Adaptador puente** y OpenSSH instalado.
- No uses Ubuntu 26.04: trae Dovecot 2.4, que tiene otra sintaxis de configuración.

## 3. Instalar: 4 scripts, en orden

| Paso | Script | ¿Cuándo? | ¿Necesita a los compañeros? |
|---|---|---|---|
| 1 | `sudo bash 1-instalar-paquetes.sh` | Una sola vez, **con internet** | No |
| 2 | `sudo bash 2-configurar-red.sh` | Cada vez que cambien de red | Sí: DNS y LDAP encendidos |
| 3 | `sudo bash 3-configurar-correo.sh` | Una sola vez | No (al final verifica LDAP si ya hay red) |
| 4 | `sudo bash 4-pruebas-correo.sh user1 'pass1' user2 'pass2'` | El día de las pruebas | Sí |

- Los pasos 1 y 3 los puedes hacer **sola y desde ya**.
- El paso 2 te pregunta la IP de ns1 y si quieres IP fija o automática. Después revisa que DNS, MX y LDAP respondan y te dice qué mandarle al compañero del DNS.
- Ningún archivo de configuración del correo tiene IPs. Si cambian de red, solo repites el paso 2 y le pasas tu nueva IP al compañero del DNS.

## 4. Configurar Thunderbird (en cada cliente)

El equipo cliente también debe usar como DNS la IP de ns1. En Windows se cambia en Configuración de red → Adaptador → IPv4 → DNS. Sin eso, no resuelve `mail.X.redes.test`.

Ve a *Nueva cuenta de correo*, escribe el nombre, `ana@restaurante.redes.test` y la contraseña LDAP, y luego **Configurar manualmente**:

| | Servidor | Puerto | Seguridad | Autenticación | Usuario |
|---|---|---|---|---|---|
| Entrante (IMAP) | `mail.restaurante.redes.test` | 143 | STARTTLS | Contraseña normal | `ana` |
| Saliente (SMTP) | `mail.restaurante.redes.test` | 587 | STARTTLS | Contraseña normal | `ana` |

Thunderbird va a advertir que el **certificado es autofirmado**. Marca *Confirmar excepción de seguridad*; es normal en el laboratorio. Si da problemas, puedes poner Seguridad = "Ninguna".

## 5. Pruebas y evidencias (matriz MAIL)

Desde la VM de correo, con 2 usuarios reales, corre este script. Guarda todo en `evidencias-correo-<fecha>.txt`:

```bash
sudo bash 4-pruebas-correo.sh dflores 'Lab5-Diego-2026' otrouser 'SuPass'
```

Además, toma estas **capturas en Thunderbird**:

| ID | Captura |
|---|---|
| MAIL-01 | `dig mail.X.redes.test` y `dig X.redes.test MX` (salen en el script) |
| MAIL-02 | Pantalla de configuración manual de la cuenta (tabla de arriba) |
| MAIL-03 | Bandeja abierta tras iniciar sesión, más el log `dovecot: imap-login: Login: user=<ana>` |
| MAIL-04 | Error de contraseña en Thunderbird, más el log `auth failed` |
| MAIL-05 | Correo de Ana a Luis en *Enviados*, más el log `postfix/submission/smtpd ... sasl_username=ana` y `status=sent` |
| MAIL-06 | El correo abierto en la bandeja de entrada de Luis |
| MAIL-07 | Error de Thunderbird al enviar a `noexiste@X.redes.test`, más el log `550 5.1.1 ... User unknown` |

Para ver los logs en vivo mientras haces las pruebas en Thunderbird:

```bash
sudo tail -f /var/log/mail.log
```

Para INT-02 (reinicio), reinicia la VM con `sudo reboot` y vuelve a correr el script 4. Los servicios quedan habilitados con `systemctl enable`.

## 6. Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| Thunderbird no encuentra el servidor | El cliente no usa el DNS del grupo, o falta el registro `mail` en la zona. |
| `auth failed` con la contraseña correcta | Revisa que el usuario exista como `uid=ana,ou=People,...`. Prueba con `ldapwhoami -x -H ldap://ldap.X.redes.test -D uid=ana,ou=People,dc=... -W` y ve el detalle en `sudo doveadm log errors`. |
| `User unknown` para usuarios que sí existen | Al usuario LDAP le falta el atributo `mail` o no es `inetOrgPerson`. Prueba con `postmap -q ana@X.redes.test ldap:/etc/postfix/ldap-users.cf`. |
| El correo se queda en cola | Revisa con `mailq` y `grep lmtp /var/log/mail.log`. |
| No hay `/var/log/mail.log` | Usa `journalctl -u dovecot -u 'postfix*'`. |

## 7. Texto para el PDF (configuraciones relevantes)

Para el informe, incluye la salida de estos comandos:

```bash
postconf -n
```
```bash
postconf -M submission/inet
```
```bash
cat /etc/postfix/ldap-users.cf
```
```bash
doveconf -n
```
```bash
cat /etc/dovecot/dovecot-ldap.conf.ext
```

Párrafo sugerido:

> El servidor `mail.X.redes.test` ejecuta Postfix como MTA y Dovecot como servidor IMAP y agente de entrega (LMTP). El dominio `X.redes.test` está configurado como dominio virtual de Postfix. Para cada correo entrante, Postfix busca el destinatario en OpenLDAP (`ou=People`, atributo `mail`) y rechaza con 550 las direcciones que no existen. Los mensajes aceptados se entregan a Dovecot por LMTP y se almacenan en formato Maildir en `/var/vmail/<uid>`. La autenticación de IMAP (puerto 143) y de SMTP submission (puerto 587, SASL delegado a Dovecot) se realiza con un bind LDAP usando el DN `uid=<usuario>,ou=People,dc=X,dc=redes,dc=test`, de modo que los usuarios usan las mismas credenciales en el correo, el sitio web y el directorio. Ambos servicios ofrecen STARTTLS con un certificado autofirmado. El registro MX de la zona apunta a `mail.X.redes.test`.
