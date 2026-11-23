# ADR 0002: salida del proxy, firewall del anfitrión y DNS embebido de Docker

- **Estado:** aceptada (Linux). Windows: pendiente de comprobar con la PoC
- **Fecha:** 2026-11-22

## Contexto

Por el [ADR 0001](0001-arquitectura-proxy-l4-redes-internas.md), el proxy `edge` necesita una red no interna para publicar puertos.

En la Fase 0 (Docker 29.10, Linux) se comprobó con conexiones reales que:

1. **El proxy tiene salida** a Internet, a la LAN y al DNS con cualquier opción de pasarela de Docker: `gateway_mode_ipv4=isolated`, `enable_ip_masquerade=false` y `routed` sin masquerade.
2. Desde las redes internas y desde la del proxy **se alcanzan servicios del anfitrión** que escuchan en `0.0.0.0` a través de la IP de pasarela. En el equipo de desarrollo, por ejemplo, el puerto 1716 de KDE Connect.
3. Linux acepta paquetes dirigidos a cualquiera de sus IP por cualquier interfaz. Un equipo de la LAN puede añadir una ruta hacia la IP de laboratorio y llegar a los puertos publicados.
4. Docker activa el reenvío IP. Sin reglas, el anfitrión enrutaría a Kali hacia la LAN.
5. **El DNS embebido de Docker** (`127.0.0.11`), en una red no interna, reenvía las consultas externas desde el espacio de red **del anfitrión**. Así se salta cualquier regla de `FORWARD`: es un canal de salida (y de túnel DNS) desde el proxy. En redes `internal` no reenvía.

## Decisión

### Linux

**Firewall propio y verificado:** `pentestlab-fw` ([detalle regla por regla](../networking/firewall-linux.md)).

- Usa tres cadenas propias:
  - `PLAB-FWD`, como primera regla de `DOCKER-USER`;
  - `PLAB-IN` y `PLAB-IN6`, como primera regla de `INPUT`.
- No toca ninguna otra regla.
- Cierra los puntos 1 a 4:
  - nada nuevo sale de los bridges `plab+`;
  - los contenedores no alcanzan el anfitrión;
  - la IP de laboratorio solo se alcanza desde la interfaz de laboratorio;
  - Kali solo llega a los bridges de los proxies.
- `./manager start` lo verifica en cada arranque:
  - el SHA-256 del ayudante instalado frente al del repositorio;
  - la comparación exacta de las reglas;
  - la posición de los saltos;
  - `br_netfilter`.

  Si algo falla, no arranca.
- Las reglas no persisten tras reiniciar: el gestor las reaplica antes de exponer nada.

**NIC NAT de Kali con KVM** (añadido el 2026-11-23). Los requisitos del taller dan a Kali un segundo adaptador NAT. En KVM es la red libvirt `default` (`virbr0`), y en este equipo no funcionaba por dos motivos: la política DROP de `FORWARD` que pone Docker, y que ufw deniega lo entrante, incluido el DHCP. Decisión del usuario: que `pentestlab-fw` la gestione con `--nat-iface`:
- acepta DHCP/DNS;
- reenvía hacia fuera y deja volver las respuestas;
- sin acceso a los servicios del anfitrión, la red de laboratorio ni las redes Docker.

Se verifica como el resto de reglas. El coste es que Kali solo tiene Internet mientras las reglas están aplicadas. Además, la red de laboratorio deja de anunciar pasarela y DNS por DHCP, para que el tráfico de Kali hacia Internet vaya por el NAT. Alternativas descartadas: NAT de usuario con passt (expone el loopback del anfitrión por defecto y no está probado) y reglas manuales de ufw/iptables (no se verifican ni se deshacen).

**DNS:** el proxy usa `dns: ["127.0.0.1"]`. Con un servidor de loopback:
- Docker sigue resolviendo los nombres internos del laboratorio (nginx los consulta en `127.0.0.11`);
- las consultas externas se reenvían desde el espacio de red **del contenedor**, donde no escucha nada en `127.0.0.1:53`.

Resultado: nombres internos sí, externos no. Lo exige la política. La sonda de aislamiento usa el DNS real configurado en cada red, así que lo comprueba en cada `start`.

### Windows (Docker Desktop)

Docker Desktop ejecuta los contenedores en su propia VM. Desde el anfitrión no se puede filtrar el tráfico saliente de esa VM con el Firewall de Windows. Decisión:

- el proxy se mantiene endurecido (ADR 0001) y las aplicaciones siguen en redes internas, sin salida;
- la salida del proxy se acepta como **riesgo residual documentado**: el gestor la muestra como aviso, no como fallo;
- el acceso de la LAN se controla con reglas del grupo `PentestLab` del Firewall de Windows;
- Windows se entrega marcado *no probado*. La PoC `scripts/windows/poc-network.ps1` debe comprobar también el comportamiento del DNS embebido con `dns: 127.0.0.1` en Docker Desktop.

## Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| Opciones de pasarela de Docker (`isolated`, sin masquerade, `routed`) | Probadas: el proxy sigue teniendo salida |
| Backend `nftables` de Docker | No ofrece `DOCKER-USER` de iptables. Habría que mantener dos implementaciones y sería menos maduro. El gestor lo bloquea |
| Reglas persistentes (iptables-persistent, ufw) | Dependen de la distribución, sobreviven a la desinstalación y no se verifican antes de cada arranque |
| Contenedor `dns` propio que solo resuelva nombres internos | Más componentes. `127.0.0.1` consigue lo mismo |
| Quitar el resolver del proxy y fijar IP | Las IP de los contenedores cambian al recrearlos. nginx necesita resolver nombres internos |

## Consecuencias

- En Linux hacen falta `sudo` (o la regla de sudoers acotada a `verify`/`apply`) y el backend `iptables` de Docker.
- El prefijo de interfaz `plab` queda reservado.
- Si otro software reordena el firewall, `start` se bloquea hasta reaplicar. Es preferible a desplegar sin garantías.
- En Windows, el aislamiento del proxy es más débil que en Linux, y está documentado así.
- Validado en Linux con paquetes reales: red emulada (211/211) y KVM con Kali real ([compatibilidad](../compatibilidad.md)).
