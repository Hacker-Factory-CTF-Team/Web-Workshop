# ADR 0001: proxy L4 por laboratorio y aplicaciones en redes internas

- **Estado:** aceptada
- **Fecha:** 2026-11-22

## Contexto

Las aplicaciones son vulnerables a propósito y se van a comprometer durante el taller. Requisitos de seguridad del taller:

- solo deben ser accesibles desde la VM de Kali y desde el propio anfitrión;
- no deben tener salida a Internet ni a la LAN;
- no deben verse entre ellas;
- no deben exponer servicios auxiliares (bases de datos, LDAP, consolas de administración);
- un fallo de configuración debe impedir el despliegue (*fail-closed*), no exponer el laboratorio.

Resultados de la Fase 0 con Docker 29.10:

1. Un contenedor que solo está en una red `internal: true` **no publica puertos**: Docker los ignora.
2. Las aplicaciones en redes internas no tienen salida TCP ni DNS.
3. Docker se niega a publicar en una IP que no existe en el anfitrión.

## Decisión

- Cada aplicación y sus servicios auxiliares van **solo en redes `internal: true`**, separadas por función (`front`, `data`, `ldap`). La base de datos no comparte red con el proxy.
- Cada laboratorio tiene **su propio proxy nginx en modo `stream` (L4, TCP)**, llamado `edge`.
  - Es el único contenedor en una red no interna y el único que publica puertos.
  - No se comparte entre laboratorios, para que no exista un punto común entre ellos.
  - Al ser L4, no reescribe HTTP y deja pasar TLS sin terminarlo (Mutillidae HTTPS).
- Los puertos se publican **solo en `127.0.0.1` y en la IP de laboratorio**, nunca en `0.0.0.0`. Si la interfaz de laboratorio no existe, Docker no publica (fail-closed natural).
- El proxy está endurecido:
  - usuario no root, sistema de archivos de solo lectura y `cap_drop: [ALL]`;
  - `no-new-privileges`, límite de PIDs y memoria;
  - `dns: [127.0.0.1]` (ver el [ADR 0002](0002-salida-del-proxy-firewall-y-dns.md)).
- Los bridges tienen **nombre fijo** (`plabe-*` para el proxy y `plabi-*` para las internas), para que el firewall del anfitrión los reconozca.
- En Mutillidae no se despliegan phpMyAdmin ni phpLDAPadmin, y MySQL y LDAP no se publican.
- `restart: "no"` en todos los servicios: tras reiniciar el anfitrión nada arranca sin pasar por las comprobaciones del gestor.

## Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| Publicar directamente desde los contenedores de la aplicación | Exige que la aplicación esté en una red no interna, con salida a Internet |
| Un único proxy compartido (por ejemplo, un reverse proxy HTTP) | Punto común entre laboratorios. Además, reescribir HTTP altera el comportamiento que se quiere estudiar, y TLS habría que terminarlo |
| `network_mode: host` o publicar en `0.0.0.0` | Expone a la LAN |
| Redes macvlan o ipvlan en la interfaz de laboratorio | Las aplicaciones quedarían directamente en la red de Kali, sin un punto único de control. Además dependen del hipervisor |

## Consecuencias

- La red no interna del proxy **sí tiene salida**, con cualquier modo de pasarela de Docker. Ese hueco lo cierra el [ADR 0002](0002-salida-del-proxy-firewall-y-dns.md).
- Desde cualquier red de Docker se alcanzan los servicios del anfitrión a través de la IP de pasarela. También lo cierra el firewall del anfitrión.
- Cada laboratorio añade un contenedor de ~2 MiB.
- La política del gestor exige esta estructura en cada `start`: solo `edge` publica, las demás redes son internas, los nombres de bridge son los fijados...
