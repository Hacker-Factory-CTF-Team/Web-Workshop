# OWASP Mutillidae II

| | |
|---|---|
| **Descripción** | Aplicación PHP vulnerable a propósito, con un gran número de páginas organizadas por categoría (OWASP Top 10 y otras), niveles de seguridad y ayudas configurables |
| **Tecnologías** | PHP + Apache, MariaDB, OpenLDAP. HTTP y HTTPS |
| **Versión fijada** | `webpwnized/mutillidae:www-2.12.7`, `database-2.12.7` y `ldap-2.12.7` |
| **Identificador** | `mutillidae` (proyecto Compose `plab-mutillidae`) |
| **Persistencia** | `persistent` por defecto; admite `ephemeral` |
| **Documentación oficial** | https://github.com/webpwnized/mutillidae y https://github.com/webpwnized/mutillidae-docker |
| **Licencia** | GPL-3.0 (proyecto Mutillidae) |

## Acceso

| Desde | URL (por defecto) |
|---|---|
| Kali | `http://<IP de laboratorio>:8081/` y `https://<IP de laboratorio>:8443/` |
| Anfitrión | `http://127.0.0.1:8081/` y `https://127.0.0.1:8443/` |

El certificado HTTPS es **autofirmado** (viene en la imagen oficial): el navegador mostrará un aviso. El proxy reenvía TLS sin terminarlo.

**Credenciales iniciales:** no hace falta iniciar sesión para empezar. La base de datos y el directorio LDAP traen las cuentas de ejemplo del proyecto.

## Servicios

| Servicio | Imagen | Función | Puertos internos | Redes |
|---|---|---|---|---|
| `edge` | nginx 1.30 (alpine) | Proxy L4, único publicado | 8081, 8443 | `edge`, `front` |
| `www` | Mutillidae www | Aplicación | 80, 443 | `front`, `data`, `ldap` |
| `database` | Mutillidae database (MariaDB) | Base de datos (volumen `db-data`) | 3306 | `data` |
| `directory` | Mutillidae ldap (OpenLDAP) | Directorio (volúmenes `ldap-data` y `ldap-config`) | 389 | `ldap` |

Los nombres `database` y `directory` son obligatorios: la imagen `www` los tiene fijados.

**No se despliegan** las consolas de administración del proyecto original (phpMyAdmin y phpLDAPadmin), y ni MySQL ni LDAP se publican. Ver el [ADR 0001](../adr/0001-arquitectura-proxy-l4-redes-internas.md).

## Requisitos

- Límites por defecto: 2,0 CPU y 1344 MiB en total.
- Consumo medido en reposo: ~170 MiB.
- Internet solo durante `./manager install`, para descargar el LDIF.

## Inicialización

Dos ganchos `post_start`:

1. **Base de datos**: si no existe la tabla `accounts`, el gestor llama a `/set-up-database.php`, el mecanismo oficial del proyecto.
2. **Directorio LDAP**: carga el LDIF oficial con `ldapadd -c`. Es idempotente: las entradas que ya existen se ignoran.

El LDIF tiene licencia GPL-3.0 y **no se redistribuye** en este repositorio:
- `./manager install mutillidae` lo descarga de un commit fijado de `mutillidae-docker`;
- verifica su SHA-256;
- lo guarda en `state/mutillidae/mutillidae.ldif`;
- se monta en solo lectura en el contenedor `directory`.

## Limitaciones

- Sin phpMyAdmin ni phpLDAPadmin. Es intencionado: amplían la superficie de ataque al anfitrión sin aportar nada al taller.
- Las funciones que dependen de servicios de Internet no funcionarán sin conexión.
