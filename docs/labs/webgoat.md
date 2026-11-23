# OWASP WebGoat + WebWolf

| | |
|---|---|
| **Descripción** | Plataforma de lecciones interactivas sobre seguridad web. WebWolf es su aplicación auxiliar: hace de servidor del atacante (recepción de peticiones, buzón de correo, alojamiento de archivos) |
| **Tecnologías** | Java, Spring Boot. Una sola imagen ejecuta las dos aplicaciones |
| **Versión fijada** | `webgoat/webgoat:v2026.5` |
| **Identificador** | `webgoat` (proyecto Compose `plab-webgoat`) |
| **Persistencia** | `persistent` por defecto; admite `ephemeral` |
| **Documentación oficial** | https://owasp.org/www-project-webgoat/ y https://github.com/WebGoat/WebGoat |
| **Licencia** | GPL-2.0 (proyecto WebGoat) |

## Acceso

| Aplicación | URL (por defecto), desde Kali **y** desde el anfitrión |
|---|---|
| WebGoat | `http://<IP de laboratorio>:8080/WebGoat/` |
| WebWolf | `http://<IP de laboratorio>:9090/WebWolf/` |

Usa la **IP de laboratorio también desde el anfitrión**. WebGoat construye los enlaces absolutos a sí mismo y a WebWolf con `WEBGOAT_HOST` y `WEBWOLF_HOST`, que el gestor fija a esa IP. Si entras por `127.0.0.1`, los enlaces entre las dos aplicaciones no funcionarán.

**Credenciales iniciales:** ninguna. Registra un usuario en la pantalla de inicio de WebGoat y úsalo también para entrar en WebWolf.

## Servicios

| Servicio | Imagen | Función | Puertos internos | Redes |
|---|---|---|---|---|
| `edge` | nginx 1.30 (alpine) | Proxy L4, único publicado | 8080, 9090 | `edge`, `front` |
| `webgoat` | WebGoat | WebGoat y WebWolf (volumen `webgoat-data` en `/data`) | Los mismos que los publicados (8080, 9090) | `front` |
| `data-init` | busybox 1.37 | Ejecución única: asigna el volumen al usuario 1001 de WebGoat | Ninguno (`network_mode: none`) | Ninguna |

El contenedor escucha en los mismos números de puerto que usa el navegador. Por eso, si cambias un puerto con `set-port`, cambian a la vez el proxy y la aplicación.

## Requisitos

- Límites por defecto: 2,25 CPU y 1600 MiB en total. Es el laboratorio más pesado.
- Consumo medido en reposo: ~390 MiB.
- El primer arranque tarda más: el healthcheck espera hasta 60 s de margen inicial y luego hasta 18 intentos.
- No necesita Internet.

## Configuración específica

- **Zona horaria**: se pasa como `TZ` (`./manager config set-timezone`; `auto` = la del anfitrión).
- **Healthcheck**: comprueba con `bash /dev/tcp` que los puertos de WebGoat y WebWolf aceptan conexiones, porque la imagen no incluye `curl`.

## Limitaciones

- Hay que acceder por la IP de laboratorio (ver arriba).
- Las lecciones que dependen de servicios de Internet no funcionarán sin conexión.
