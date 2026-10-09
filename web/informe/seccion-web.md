# Servidor web con autenticación LDAP (Ejercicio 3)

## Descripción

El servidor `www.restaurante.redes.test` (IP `[COMPLETAR]`) ejecuta Apache HTTP Server 2.4 sobre Ubuntu Server 24.04.
Publica una página principal que identifica al grupo y una sección protegida (`/privado/`) cuyo acceso se valida
contra el servidor OpenLDAP `ldap.restaurante.redes.test` mediante `mod_authnz_ldap`.

## Cómo se comunican Apache y LDAP

1. El navegador solicita `/privado/`. Apache responde `401 Unauthorized` y pide credenciales (autenticación Basic).
2. El usuario envía su `uid` y su contraseña.
3. Apache se conecta a `ldap://ldap.restaurante.redes.test` (puerto 389) y busca la entrada con `uid=<usuario>` bajo
   `ou=People,dc=restaurante,dc=redes,dc=test`. La búsqueda es anónima, porque el directorio la permite.
4. Si la entrada existe, Apache realiza un *bind* con ese DN y la contraseña recibida. El servidor LDAP acepta o rechaza el bind.
5. Si el bind es exitoso (`Require valid-user`), Apache entrega la página; si no, responde `401`.
6. Si no hay conexión con LDAP, la autenticación no puede completarse y el error queda registrado en `restaurante_error.log`.

Apache nunca lee `userPassword`: las contraseñas se validan con el bind. Se usa el nombre DNS del servidor LDAP, no su IP.

## Configuración relevante (`/etc/apache2/sites-available/restaurante.conf`)

```apache
LDAPSharedCacheSize 0

<VirtualHost *:80>
    ServerName www.restaurante.redes.test
    DocumentRoot /var/www/restaurante

    <Directory /var/www/restaurante/privado>
        AuthType Basic
        AuthName "Area protegida - Restaurante (usuario LDAP)"
        AuthBasicProvider ldap
        AuthLDAPURL "ldap://ldap.restaurante.redes.test/ou=People,dc=restaurante,dc=redes,dc=test?uid?sub"
        Require valid-user
    </Directory>

    LogLevel warn authnz_ldap:info ldap:info
    ErrorLog ${APACHE_LOG_DIR}/restaurante_error.log
    CustomLog ${APACHE_LOG_DIR}/restaurante_access.log combined
</VirtualHost>
```

Módulos habilitados: `ldap`, `authnz_ldap`, `include`. El servicio `apache2` está habilitado con `systemctl enable`.

## Matriz de pruebas

| ID | Prueba | Resultado esperado | Resultado obtenido | Evidencia |
|---|---|---|---|---|
| WEB-01 | Resolver `www.restaurante.redes.test` | IP del servidor Apache | [COMPLETAR] | `WEB-01_dig_www.txt` |
| WEB-02 | Abrir `http://www.restaurante.redes.test` | Carga la página principal | [COMPLETAR] | `WEB-02_pagina_principal.png` |
| WEB-03 | Acceso a `/privado/` con usuario LDAP válido | Acceso permitido | [COMPLETAR] | `WEB-03_acceso_valido.png` |
| WEB-04 | Contraseña incorrecta o usuario inexistente | Acceso rechazado (401) | [COMPLETAR] | `WEB-04_rechazo.png` |
| WEB-05 | Detener LDAP e intentar autenticarse | No se completa y el error queda en el log | [COMPLETAR] | `WEB-05_ldap_detenido.png`, `WEB-05_log_apache_error.txt` |

Se probó el acceso con los usuarios: [COMPLETAR: lista de uids probados].

## Observaciones de seguridad

- El sitio usa HTTP sin cifrar: con autenticación Basic, el usuario y la contraseña viajan codificados en Base64,
  no cifrados. Es aceptable en la red interna del laboratorio; en producción se usaría HTTPS y `ldaps://` o STARTTLS.
- Las contraseñas usadas son exclusivas del laboratorio y no se guardan en el repositorio ni en las evidencias.
- Se desactivó la caché compartida de LDAP (`LDAPSharedCacheSize 0`) para que cada acceso consulte al directorio y
  WEB-05 demuestre la dependencia real de LDAP.

## Responsable

[COMPLETAR: nombre del integrante a cargo del servidor web]
