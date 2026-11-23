# Matriz de compatibilidad

Solo se marca como **probado** lo que se ha ejecutado de verdad, y se indica cómo.

## Plataformas

| Anfitrión | Hipervisor | Estado | Fecha | Cómo se probó |
|---|---|---|---|---|
| CachyOS (Arch), kernel 7.3 | KVM/QEMU (libvirt 12.9, `qemu-desktop`) | **Probado** | 2026-11-23 | VM de Kali real con dos NIC (laboratorio + NAT `default`), `kali-probe.sh --full-scan` con rutas temporales y LAN emulada con `linux-netns.sh test` |
| CachyOS (Arch), kernel 7.3 | Host-only emulada (veth + netns) | **Probado** | 2026-11-22 | `linux-validation-session.sh`: 211/211 |
| Linux | VirtualBox | No probado | | El instalador lo implementa ([virtualbox.md](installation/virtualbox.md)) |
| Debian / Ubuntu | KVM o VirtualBox | No probado | | El instalador reconoce la familia de distribución |
| Fedora | KVM o VirtualBox | No probado | | Ídem |
| openSUSE | KVM o VirtualBox | No probado | | Ídem |
| Windows 11 | VirtualBox + Docker Desktop | No probado | | El instalador de Windows aún no está disponible |

## Componentes del anfitrión probado

| Componente | Versión |
|---|---|
| Docker Engine | 29.10.0 (backend `iptables` sobre nf_tables) |
| Docker Compose | 5.8.0 |
| Python | 3.10.22 (pruebas unitarias) y la del sistema (gestor) |
| libvirt | 12.9.0 (demonios modulares) |
| ufw y Tailscale | Activos durante todas las pruebas |
| Kali | Imagen oficial para QEMU |

## Requisitos mínimos (los aplica el gestor)

| Componente | Mínimo | Motivo |
|---|---|---|
| Docker Engine | 28 | En versiones anteriores, los puertos publicados en `127.0.0.1` son accesibles desde la LAN |
| Docker Compose | 2.24 | |
| Python | 3.10 | |
| Backend de firewall de Docker | `iptables` | `pentestlab-fw` usa `DOCKER-USER` |

## No soportado

- Docker rootless.
- Docker Desktop para Linux.
- El backend `nftables` de Docker.
- Ejecutar el gestor dentro de WSL.
- Interfaces de laboratorio cuyo nombre empiece por `plab`.

## Cómo contribuir un resultado

Ejecuta los niveles 2 a 4 de las [pruebas](testing/pruebas.md) en tu plataforma y añade una fila con:
- la distribución y versión;
- el hipervisor;
- las versiones de Docker y Compose;
- la fecha;
- el resultado de cada prueba.
