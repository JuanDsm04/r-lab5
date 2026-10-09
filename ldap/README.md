# Ejercicio 2: OpenLDAP (Integrante 2)

Dominio del grupo: `restaurante.redes.test` · Base del directorio: `dc=restaurante,dc=redes,dc=test` · Servidor: `ldap.restaurante.redes.test` (IP `<subred>.11`, puerto 389)

## 0. Cómo funciona

```
Apache (www) ──bind uid=<usuario>──┐
Dovecot (mail) ──bind uid=<usuario>─┼──> slapd en ldap.restaurante.redes.test:389
Postfix (mail) ──búsqueda (mail=…)─┘          dc=restaurante,dc=redes,dc=test
                                               ├── ou=People   (un usuario por integrante)
                                               └── ou=Groups   (grupo posix "restaurante")
```

- Cada integrante es una entrada `uid=<usuario>,ou=People,dc=restaurante,dc=redes,dc=test` con `inetOrgPerson` + `posixAccount` + `shadowAccount`.
- Las contraseñas se guardan como hash `{SSHA}` (`slappasswd`), nunca en texto plano.
- **Búsqueda anónima permitida** (ACL por defecto de Ubuntu), excepto `userPassword`, que no se puede leer. Los demás servicios validan contraseñas haciendo **bind como el usuario**.
- Log level `stats`: cada conexión, bind y búsqueda queda en `journalctl -u slapd` (INT-04, WEB-05).

## 1. Archivos

| Archivo | Qué es | ¿En el repo? |
|---|---|---|
| `setup_ldap.sh` | Instala slapd, fija la base del directorio, activa logs, genera `usuarios.ldif` y lo carga. Se puede repetir (recrea el directorio desde cero) | Sí |
| `configurar_red.sh` | IP fija, DNS = ns1 y hostname `ldap.restaurante.redes.test` (netplan) | Sí |
| `pruebas_ldap.sh` | LDAP-01 a 04 + extras. Guarda la salida en `evidencias/ldap/` | Sí |
| `usuarios.ldif` | **Entregable d.** El que generó la VM (hashes SSHA) | Sí |
| `integrantes.ejemplo.csv` | Plantilla de usuarios sin contraseñas | Sí |
| `integrantes.csv` | Usuarios **con contraseñas en texto plano** | **No** (`.gitignore`) |

## 2. Usuarios

| uid | Nombre | Correo |
|---|---|---|
| nmuralles | Nils Muralles | nmuralles@restaurante.redes.test |
| irecinos | Isabella Recinos | irecinos@restaurante.redes.test |
| dflores | Diego Flores | dflores@restaurante.redes.test |
| pmendez | Pablo Méndez | pmendez@restaurante.redes.test |
| jsolis | Juan Solís | jsolis@restaurante.redes.test |
| vperez | Víctor Pérez | vperez@restaurante.redes.test |

`uidNumber` 10001–10006, `gidNumber` 10000, `homeDirectory` `/home/<uid>`. Las contraseñas (solo del laboratorio) se pasan por el chat del grupo.

## 3. Instalación (Ubuntu Server 24.04, adaptador puente)

| Paso | Comando | ¿Cuándo? |
|---|---|---|
| 1 | `cp integrantes.ejemplo.csv integrantes.csv` y poner las contraseñas | Una vez |
| 2 | `sudo ./setup_ldap.sh` (pide la contraseña de `cn=admin`) | Una vez, **con internet** |
| 3 | `sudo ./configurar_red.sh <subred>.11/24 <subred>.1 <subred>.10` | Cada vez que cambie la red |

En el paso 3, correr desde la consola de VirtualBox (el SSH se corta al cambiar la IP).

## 4. Datos para los demás servicios

```
URI:      ldap://ldap.restaurante.redes.test   (389, sin TLS)
Base:     ou=People,dc=restaurante,dc=redes,dc=test
DN user:  uid=<usuario>,ou=People,dc=restaurante,dc=redes,dc=test
Filtro:   (uid=%u)   — o (mail=%s) para buscar por correo
Búsqueda anónima: sí (sin bind DN). userPassword no es legible: validar por bind.
```

Verificado en conjunto con `correo/`: Postfix encuentra los buzones por `mail`, Dovecot autentica por bind y rechaza contraseñas malas, y si slapd se detiene el log de Dovecot muestra `Can't connect to server: ldap://ldap.restaurante.redes.test`.

## 5. Pruebas y evidencias

Desde el cliente (o cualquier equipo que use ns1 como DNS):

```bash
./pruebas_ldap.sh nmuralles '<password>'
```

| ID | Qué muestra | Resultado esperado |
|---|---|---|
| LDAP-01 | `ldapsearch` sobre `ou=People` | 6 usuarios |
| LDAP-02 | `ldapwhoami` con contraseña correcta | `dn:uid=nmuralles,...` |
| LDAP-03 | `ldapwhoami` con contraseña incorrecta / usuario inexistente | `Invalid credentials (49)` |
| LDAP-04 | Atributos `uid`, `cn`, `sn`, `mail` | Presentes, correo `@restaurante.redes.test` |
| Extra | `userPassword` por búsqueda anónima | No aparece |

Capturas con el nombre del grupo: `LDAP-01_ldapsearch_people.png`, `LDAP-02_bind_valido.png`, etc.

Los nombres con tilde se muestran como `cn:: <base64>` (así se codifica UTF-8 en LDIF). Para verlos: `echo 'Sm9zw6k=' | base64 -d`.

En el servidor LDAP:

| ID | Comando |
|---|---|
| INT-02 | `sudo reboot` y repetir `pruebas_ldap.sh` |
| INT-03 | `sudo ss -lntup \| grep 389` |
| INT-04 | `sudo journalctl -u slapd --since "30 min ago"` (busca `BIND` y `RESULT ... err=49`) |
| WEB-05 | `sudo systemctl stop slapd` cuando lo pida Web; luego `sudo systemctl start slapd` |

## 6. Para el PDF

```bash
sudo slapcat -n 0 | grep -E '^(dn: olcDatabase=\{1\}mdb|olcSuffix|olcRootDN|olcAccess|olcLogLevel)'
ldapsearch -x -LLL -H ldap://ldap.restaurante.redes.test -b dc=restaurante,dc=redes,dc=test dn
cat usuarios.ldif     # sin contraseñas en texto plano: solo hashes SSHA
```

Párrafo sugerido:

> El servidor `ldap.restaurante.redes.test` ejecuta OpenLDAP (slapd) con la base `dc=restaurante,dc=redes,dc=test`, generada a partir del dominio DNS del grupo. Dentro de `ou=People` existe una entrada por integrante con las clases `inetOrgPerson`, `posixAccount` y `shadowAccount`, que contienen `uid`, `cn`, `sn`, `mail` (`<uid>@restaurante.redes.test`) y `userPassword` almacenado como hash SSHA. El directorio permite búsquedas anónimas para que Postfix pueda verificar destinatarios, pero el atributo `userPassword` solo se usa para autenticar: Apache y Dovecot validan las credenciales realizando un bind con el DN del usuario, por lo que todos los servicios comparten las mismas cuentas. El nivel de log `stats` registra cada conexión, bind y búsqueda, y el servicio queda habilitado con systemd para iniciar automáticamente tras un reinicio.

## 7. Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| `Can't contact LDAP server (-1)` | slapd caído (`systemctl status slapd`), la VM sigue en NAT o el DNS apunta a otra IP (`dig ldap.restaurante.redes.test`) |
| `Invalid credentials (49)` con la contraseña correcta | Contraseña con caracteres especiales sin comillas simples, o el DN está mal escrito |
| `No such object (32)` | Base mal escrita: es `dc=restaurante,dc=redes,dc=test` |
| Base con otro dominio (`dc=ubuntu,...`) | Se instaló slapd a mano sin reconfigurar: volver a correr `sudo ./setup_ldap.sh` |
