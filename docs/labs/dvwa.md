# DVWA (Damn Vulnerable Web Application)

| | |
|---|---|
| **Descripción** | Aplicación web PHP vulnerable a propósito, organizada en módulos por tipo de vulnerabilidad y con varios niveles de seguridad seleccionables |
| **Tecnologías** | PHP + Apache (imagen oficial), MariaDB 10.11 |
| **Versión fijada** | `ghcr.io/digininja/dvwa:502ac15` (el proyecto solo publica tags de commit) y `mariadb:10.11.19` |
| **Identificador** | `dvwa` (proyecto Compose `plab-dvwa`) |
| **Persistencia** | `persistent` por defecto; admite `ephemeral` |
| **Documentación oficial** | https://github.com/digininja/DVWA |
| **Licencia** | GPL-3.0 (proyecto DVWA) |

## Acceso

| Desde | URL (por defecto) |
|---|---|
| Kali | `http://<IP de laboratorio>:4280/` |
| Anfitrión | `http://127.0.0.1:4280/` |

**Credenciales iniciales:** `admin` / `password`. Es la cuenta por defecto que documenta el proyecto; la base de datos incluye además otros usuarios de ejemplo.

## Servicios

| Servicio | Imagen | Función | Puerto interno | Redes |
|---|---|---|---|---|
| `edge` | nginx 1.30 (alpine) | Proxy L4, único publicado | 4280 | `edge`, `front` |
| `dvwa` | DVWA | Aplicación | 80 | `front`, `data` |
| `db` | MariaDB 10.11 | Base de datos (volumen `db-data`) | 3306 (solo en la red `data`) | `data` |

La base de datos no se publica y el proxy no la alcanza.

## Requisitos

- Límites por defecto: 1,75 CPU y 1088 MiB en total ([recursos](../management/recursos.md)).
- Consumo medido en reposo: ~130 MiB.
- No necesita Internet.

## Inicialización

DVWA no crea su base de datos al arrancar: hay que pasar por `setup.php`. El gestor lo hace automáticamente con un gancho `post_start`, que solo se ejecuta si falta la tabla `users`:
1. obtiene el token CSRF de `setup.php`;
2. envía el formulario de creación desde dentro del contenedor.

Tras un `reset-data`, la base de datos vuelve a crearse con los usuarios por defecto.

La propia aplicación tiene en *Setup / Reset DB* el mismo botón de restauración y una lista con el estado de los requisitos de cada módulo.

## Limitaciones

- No hay salida a Internet. Los módulos que dependen de servicios externos no funcionarán. Por ejemplo, el de CAPTCHA requiere claves de reCAPTCHA y acceso a Google (no verificado en este laboratorio).
- El nivel de seguridad se elige desde la propia aplicación (*DVWA Security*) y se guarda en la sesión.
