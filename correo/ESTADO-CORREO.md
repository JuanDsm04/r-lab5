# Lab 5: Servidor de correo, estado y pasos pendientes

**Grupo:** restaurante.redes.test · **Mi parte:** Ejercicio 4, correo (25 pts) + matriz MAIL-01 a MAIL-07

---

## 1. Qué es lo que se implementa

Un servidor de correo propio para el dominio del grupo (`@restaurante.redes.test`):

| Componente | Función |
|---|---|
| **Postfix** | Recibe y envía correos (SMTP, puertos 25 y 587). Antes de aceptar un correo, pregunta a LDAP si el destinatario existe; si no, lo rechaza con `550 User unknown`. |
| **Dovecot** | Guarda los buzones y deja leerlos (IMAP, puertos 143 y 993). Valida las contraseñas haciendo *bind* contra el LDAP del grupo. |
| **OpenLDAP** (compañero) | Tiene los usuarios y contraseñas. El correo no guarda contraseñas propias. |
| **BIND9** (compañero) | Hace que `mail.restaurante.redes.test` y el registro MX apunten a mi VM. |
| **Thunderbird** | Cliente de correo en las computadoras del grupo. |

```
Thunderbird ──SMTP 587──> Postfix ──LMTP──> Dovecot ──> /var/vmail/<usuario>/Maildir
                             │                 │
                     ¿existe el destino?   ¿contraseña correcta?
                             └──────> OpenLDAP <┘
Thunderbird <──IMAP 143───────────────── Dovecot
```

---

## 2. Lo que ya está hecho ✅

### Máquina virtual
- VirtualBox, VM **`mail-restaurante`**
- **Ubuntu Server 24.04.5 LTS**, 4 GB RAM, 2 CPUs, disco de 20 GB
- Nombre del servidor: **`mail`** · usuario: **`isamail`**
- OpenSSH instalado
- Red actual: **NAT** con reenvío de puertos **2222 → 22**, así que me conecto desde Windows con:
  ```
  ssh -p 2222 isamail@127.0.0.1
  ```

### Scripts (en `Escritorio\Lab5-Correo\correo` y copiados a la VM en `~/correo`)

| Script | Qué hace | Estado |
|---|---|---|
| `1-instalar-paquetes.sh` | Instala Postfix, Dovecot 2.3, ldap-utils, swaks, etc. | ✅ Ejecutado |
| `2-configurar-red.sh` | IP de la VM + DNS del grupo, y verifica DNS/MX/LDAP | ⏳ Se corre con el grupo |
| `3-configurar-correo.sh` | Configura Postfix + Dovecot + LDAP | ✅ Ejecutado |
| `4-pruebas-correo.sh` | Ejecuta MAIL-01 a 07 y guarda la evidencia en un `.txt` | ⏳ Se corre con el grupo |

### Resultado del paso 3
- Postfix escucha en **25** y **587**; Dovecot en **143** y **993**.
- Los servicios están habilitados (`systemctl enable`), así que **arrancan solos** al encender la VM (sirve para INT-02).
- El aviso `!! No pude leer usuarios de ldap...` es **esperado**: la VM aún no está en la red del grupo.

### Configuración aplicada (resumen)
- Dominio virtual `restaurante.redes.test`; los buzones existen según el atributo `mail` en LDAP.
- LDAP: `ldap://ldap.restaurante.redes.test`, base `ou=People,dc=restaurante,dc=redes,dc=test`, búsqueda anónima.
- Autenticación por bind: `uid=<usuario>,ou=People,dc=restaurante,dc=redes,dc=test`.
- Se puede iniciar sesión como `usuario` o como `usuario@restaurante.redes.test`.
- STARTTLS con certificado autofirmado; se permite login sin TLS (laboratorio).
- **Ningún archivo de configuración tiene IPs**: todo va por nombres DNS.

### Problemas resueltos en el camino
- El instalador de Ubuntu se colgaba ("call trace"): se subió la RAM a 4 GB y se reinstaló.
- `doveconf: Garbage after '{'` (línea 54): bloques de Dovecot escritos en una sola línea. Ya está corregido en el script.

---

## 3. Lo que falta: el día que se junte el grupo ⏳

**Requisito:** todos conectados a **la misma red** (mismo router o hotspot). Las redes WiFi de la universidad pueden bloquear la comunicación entre computadoras.

### Paso A: Pedir datos al grupo
- [ ] IP del DNS (**ns1**)
- [ ] uid y contraseña de **2 usuarios LDAP** para las pruebas (ej. `dflores`)

### Paso B: Poner la VM en la red del grupo
1. Con la VM **apagada**: *VirtualBox → Configuración → Red → Adaptador 1 →* **Adaptador puente** → Aceptar.
2. Encender la VM y entrar **desde la ventana de VirtualBox** (el SSH por `127.0.0.1:2222` ya no funciona con adaptador puente).
3. Ver la IP nueva con `ip a`. Desde ahí, el SSH desde Windows es `ssh isamail@<IP de la VM>`.

### Paso C: Configurar la red (script 2)
```
cd ~/correo
sudo bash 2-configurar-red.sh
```
- Pregunta la **IP de ns1** y si quiero **IP fija** (`s`) o automática (`n`).
- Revisa `ns1`, `ldap`, `mail`, el MX y el LDAP, y marca `[OK]` o `[FALLA]` en cada uno.
- Al final imprime el texto para el compañero del **DNS**:
  ```
  mail  IN  A   <mi IP>
  @     IN  MX  10 mail.restaurante.redes.test.
  ```
- [ ] Mandarle eso, esperar a que recargue la zona y **volver a correr el script** hasta que todo salga `[OK]`.
- Si cambian de red otro día, solo se repite este paso.

### Paso D: Comprobar que Postfix ve el LDAP
```
postmap -q dflores@restaurante.redes.test ldap:/etc/postfix/ldap-users.cf
```
Debe imprimir el correo. Si no imprime nada, el usuario no tiene el atributo `mail` (hablar con el compañero de LDAP).

### Paso E: Configurar Windows y Thunderbird
1. **DNS de Windows**: *Configuración → Red → Adaptador → IPv4 →* DNS = IP de ns1. Comprobar con:
   ```
   nslookup mail.restaurante.redes.test
   ```
2. **Thunderbird**: *Nueva cuenta → correo y contraseña de LDAP → Configurar manualmente*:

| | Servidor | Puerto | Seguridad | Autenticación | Usuario |
|---|---|---|---|---|---|
| IMAP | `mail.restaurante.redes.test` | 143 | STARTTLS | Contraseña normal | uid (ej. `dflores`) |
| SMTP | `mail.restaurante.redes.test` | 587 | STARTTLS | Contraseña normal | uid |

3. Aceptar la advertencia del **certificado autofirmado** (*Confirmar excepción de seguridad*).
4. Configurar **2 cuentas** (en la misma o en distintas computadoras).

### Paso F: Pruebas y capturas

Dejar los logs abiertos en otra ventana SSH mientras se prueba:
```
sudo tail -f /var/log/mail.log
```

| ID | Qué hacer | Captura |
|---|---|---|
| MAIL-01 | `dig mail.restaurante.redes.test` y `dig restaurante.redes.test MX` | Terminal |
| MAIL-02 | Configurar la cuenta | Pantalla de configuración manual |
| MAIL-03 | Iniciar sesión con la contraseña correcta | Bandeja abierta + log `imap-login: Login: user=<...>` |
| MAIL-04 | Iniciar sesión con una contraseña incorrecta | Error en Thunderbird + log `auth failed` |
| MAIL-05 | Usuario 1 envía a usuario 2 | Correo en *Enviados* + log `sasl_username=...` y `status=sent` |
| MAIL-06 | Usuario 2 abre su bandeja | Correo recibido abierto |
| MAIL-07 | Enviar a `noexiste@restaurante.redes.test` | Error en Thunderbird + log `550 5.1.1 User unknown` |

Luego, la evidencia por terminal (contraseñas entre comillas simples):
```
sudo bash 4-pruebas-correo.sh usuario1 'pass1' usuario2 'pass2'
```
Genera `evidencias-correo-<fecha>.txt` en `~/correo`. Para traerlo a Windows (desde PowerShell, en `Lab5-Correo`):
```
scp isamail@<IP de la VM>:~/correo/evidencias-correo-*.txt .
```

### Paso G: Pruebas de integración en las que participa el correo
- [ ] **INT-02**: `sudo reboot`, y luego repetir el script 4. Los servicios deben volver solos.
- [ ] **INT-03**: `sudo ss -lntup` (puertos 25, 587, 143, 993).
- [ ] **INT-04**: extractos de `/var/log/mail.log`.
- ⚠️ Mientras alguien hace **WEB-05** (detener LDAP), el correo tampoco autentica. Es lo esperado; no probar correo en ese momento.

---

## 4. Para el PDF del grupo

Copiar la salida de estos comandos como "configuraciones relevantes":
```
postconf -n
postconf -M submission/inet
cat /etc/postfix/ldap-users.cf
doveconf -n
sudo cat /etc/dovecot/dovecot-ldap.conf.ext
```

**Párrafo sugerido:**
> El servidor `mail.restaurante.redes.test` ejecuta Postfix como MTA y Dovecot como servidor IMAP y agente de entrega (LMTP). El dominio `restaurante.redes.test` está configurado como dominio virtual de Postfix. Para cada correo entrante, Postfix busca el destinatario en OpenLDAP (`ou=People`, atributo `mail`) y rechaza con 550 las direcciones que no existen. Los mensajes aceptados se entregan a Dovecot por LMTP y se almacenan en formato Maildir en `/var/vmail/<uid>`. La autenticación de IMAP (puerto 143) y de SMTP submission (puerto 587, SASL delegado a Dovecot) se realiza mediante un bind LDAP con el DN `uid=<usuario>,ou=People,dc=restaurante,dc=redes,dc=test`, de modo que los usuarios usan las mismas credenciales en todos los servicios. Ambos servicios ofrecen STARTTLS con un certificado autofirmado, y el registro MX de la zona apunta a `mail.restaurante.redes.test`.

---

## 5. Si algo falla

| Síntoma | Qué revisar |
|---|---|
| Thunderbird no encuentra el servidor | Windows no usa el DNS del grupo, o falta `mail` en la zona: `nslookup mail.restaurante.redes.test` |
| `auth failed` con la contraseña correcta | `ldapwhoami -x -H ldap://ldap.restaurante.redes.test -D "uid=USUARIO,ou=People,dc=restaurante,dc=redes,dc=test" -W` y `sudo doveadm log errors` |
| `User unknown` con un usuario que sí existe | Le falta el atributo `mail` en LDAP (ver paso D) |
| El correo no llega | `mailq` y `grep lmtp /var/log/mail.log` |
| No responde el SSH | Cerrar con **Enter, `~`, `.`** o cerrar PowerShell. La VM sigue bien. |

## 6. Encender y apagar la VM de forma segura
- **Encender:** VirtualBox → `mail-restaurante` → Iniciar → esperar ~1 min → conectarse por SSH.
- **Apagar:** `sudo shutdown now`, o en VirtualBox *Máquina → Apagado ACPI*.
- **Solo si está totalmente trabada:** cerrar la ventana → "Apagar la máquina".
