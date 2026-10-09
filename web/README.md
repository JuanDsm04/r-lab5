# Servidor web (Apache + login LDAP)

Servidor web del laboratorio, accesible como `http://www.restaurante.redes.test` con la IP `<subred>.12`.
Tiene una página principal pública y una sección `/privado/` protegida con usuarios del OpenLDAP del grupo
(`mod_authnz_ldap`).

## Contenido

```
web/
├── README.md                  Guía de instalación y pruebas
├── setup.sh                   Instala Apache, módulos y publica el sitio
├── restaurante.conf           Virtual host con autenticación LDAP
├── red/cambiar-ip.sh          IP fija <subred>.12 con netplan
├── sitio/
│   ├── index.html             Página principal que identifica al grupo
│   └── privado/index.html     Sección protegida (muestra el usuario autenticado)
├── pruebas/pruebas_web.sh     WEB-01 a WEB-05 (+ INT-02/03/04 en el servidor)
└── informe/seccion-web.md     Sección del informe PDF
```

Las evidencias se guardan en `evidencias/web/`.

## Decisiones de diseño

| Decisión | Motivo |
|---|---|
| `mod_authnz_ldap` con `AuthBasicProvider ldap` | Apache valida contra OpenLDAP sin escribir una aplicación propia |
| `AuthLDAPURL` con `?uid?sub` sobre `ou=People` | Busca `uid=<usuario>` y valida la contraseña con un bind como ese usuario |
| Sin `AuthLDAPBindDN` | El LDAP del grupo permite búsqueda anónima (salvo `userPassword`) |
| `Require valid-user` | Entra cualquiera de los usuarios LDAP del grupo |
| `LDAPSharedCacheSize 0` | Sin caché, con slapd detenido nadie entra (WEB-05) |
| `LogLevel authnz_ldap:info ldap:info` | Los rechazos y los fallos de conexión a LDAP quedan en `restaurante_error.log` |
| URL con nombre DNS (`ldap.restaurante.redes.test`) | El servicio no depende de IPs |
| Sin TLS | Laboratorio en red interna; las credenciales viajan en Base64 sobre HTTP (se menciona en el informe) |

## Procedimiento

Los comandos se ejecutan en la VM del servidor web, desde la raíz del repositorio, salvo indicación contraria.

### 1. Preparación de la VM

1. Instalar Ubuntu Server 24.04 con el adaptador de red en modo puente y OpenSSH activado.
2. Clonar el repositorio:
   ```bash
   sudo apt install -y git
   git clone https://github.com/JuanDsm04/r-lab5.git && cd r-lab5
   ```

### 2. Instalación

Requiere Internet, por lo que debe hacerse **antes** de asignar la IP del laboratorio.

```bash
sudo bash web/setup.sh
```

El script instala Apache, habilita `ldap`, `authnz_ldap` e `include`, publica el sitio en `/var/www/restaurante`,
instala `restaurante.conf`, valida con `apache2ctl configtest` y habilita el servicio al arranque.
Al final verifica `/` (200) y `/privado/` (401). Puede ejecutarse de nuevo después de modificar el sitio o la configuración.

### 3. IP fija

Desde la **consola de VirtualBox** (el SSH se corta al cambiar la IP):

```bash
sudo bash web/red/cambiar-ip.sh <subred>
# ejemplo: sudo bash web/red/cambiar-ip.sh 192.168.1
```

Asigna `<subred>.12`, usa `<subred>.10` como DNS y fija el hostname `www`.
Si ns1 aún no existe, se puede usar el router como DNS provisional:
`sudo bash web/red/cambiar-ip.sh 192.168.1 192.168.1.1 192.168.1.1`.

### 4. Verificar dependencias

```bash
dig www.restaurante.redes.test +short        # debe devolver <subred>.12
dig ldap.restaurante.redes.test +short       # debe devolver <subred>.11
ldapsearch -x -LLL -H ldap://ldap.restaurante.redes.test \
  -b ou=People,dc=restaurante,dc=redes,dc=test uid          # debe listar los 6 usuarios
```

La VM debe estar en la misma subred que ns1 (BIND solo responde a `localhost` y `localnets`).
Las contraseñas de los usuarios LDAP se piden al grupo; no están en el repositorio.

### 5. Pruebas

Desde un cliente que use ns1 como DNS:

```bash
chmod +x web/pruebas/pruebas_web.sh
./web/pruebas/pruebas_web.sh dflores '<password>'
# si el equipo aún no usa ns1 como DNS:
./web/pruebas/pruebas_web.sh dflores '<password>' 192.168.1.10
```

Repetir con **cada integrante** para demostrar que cualquier usuario LDAP puede entrar.

| ID | Qué verifica | Resultado esperado |
|---|---|---|
| WEB-01 | `dig www.restaurante.redes.test` | IP terminada en `.12` |
| WEB-02 | `curl` a la página principal | HTTP 200 |
| WEB-03 | `/privado/` sin credenciales y con usuario válido | 401 y 200 |
| WEB-04 | Contraseña incorrecta y usuario inexistente | 401 en ambos |
| WEB-05 | Con slapd detenido | No se concede acceso y el error queda en el log |

### 6. WEB-05 (con el equipo del LDAP)

1. En el servidor LDAP: `sudo systemctl stop slapd`.
2. Desde el cliente: `./web/pruebas/pruebas_web.sh dflores '<password>' --ldap-detenido`.
   Con LDAP caído, Apache suele responder 500 (no puede consultar el directorio) o 401; lo importante es que no da 200.
3. En el servidor web: `sudo tail -n 20 /var/log/apache2/restaurante_error.log` y captura de pantalla.
4. En el servidor LDAP: `sudo systemctl start slapd`.

Mientras slapd esté detenido, el correo tampoco autentica: avisar al equipo de correo.

### 7. Pruebas en el servidor web (INT-02, INT-03, INT-04)

```bash
sudo ./web/pruebas/pruebas_web.sh dflores '<password>'
```

Al correrlo con `sudo` en el servidor web agrega `configtest`, `systemctl status`, `ss -lntup` (puerto 80) y los logs.
Para INT-02, reiniciar con `sudo reboot` y volver a correr el script: si todo pasa, la configuración persiste.

### 8. Capturas de pantalla

Guardar en `evidencias/web/` con el formato `<ID-PRUEBA>_<descripcion>.png`:

| Archivo | Qué mostrar |
|---|---|
| `WEB-02_pagina_principal.png` | `http://www.restaurante.redes.test` en el navegador |
| `WEB-03_acceso_valido.png` | `/privado/` con la sesión iniciada (se ve el usuario) |
| `WEB-04_rechazo.png` | Ventana de login rechazada o error 401 |
| `WEB-05_ldap_detenido.png` | Intento de login con slapd detenido |

Después:

```bash
git pull
git add web evidencias/web
git commit -m "feat: web"
git push
```

## Lista de verificación

- [ ] `setup.sh` ejecutado sin errores
- [ ] IP `<subred>.12` asignada y `dig www.restaurante.redes.test` correcto
- [ ] WEB-01 a WEB-04 correctas, con al menos 2 usuarios distintos
- [ ] WEB-05 con slapd detenido y log de Apache guardado
- [ ] Reinicio realizado y pruebas repetidas (INT-02)
- [ ] `evidencias/web/` con `.txt` y capturas `.png`
- [ ] Sección del informe completa (`informe/seccion-web.md`)

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `/privado/` siempre da 401 con la contraseña correcta | Revisar `restaurante_error.log`. Causas: `ldap.restaurante.redes.test` no resuelve desde el servidor web, slapd caído o contraseña con caracteres especiales sin comillas simples |
| `Invalid command 'AuthLDAPURL'` | Faltan módulos: `sudo a2enmod ldap authnz_ldap && sudo systemctl restart apache2` |
| `Invalid command 'LDAPSharedCacheSize'` | Falta `mod_ldap`: mismo comando anterior |
| La página privada muestra la sesión vacía | Falta `mod_include`: `sudo a2enmod include && sudo systemctl restart apache2` |
| `dig` no devuelve nada | La VM no usa ns1 como DNS o está en otra subred (`resolvectl status`) |
| Funciona por IP pero no por nombre | Falta el registro `www` en la zona o apunta a otra IP |
| `bash: $'\r': command not found` | Finales de línea CRLF: `find web -name '*.sh' -exec sed -i 's/\r$//' {} +` |
| `apt` falla después de cambiar la IP | ns1 no resuelve nombres externos: instalar antes de asignar la IP del laboratorio |
