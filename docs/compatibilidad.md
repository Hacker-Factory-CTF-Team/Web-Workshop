# Matriz de compatibilidad

Solo se marca como **probado** lo que se ha ejecutado de verdad, y se indica cómo.

## Plataformas

| Anfitrión | Hipervisor | Estado | Fecha | Cómo se probó |
|---|---|---|---|---|
| CachyOS (Arch), kernel 7.3 | KVM/QEMU (libvirt 12.9, `qemu-desktop`) | **Probado** | 2026-11-23 | VM de Kali real con dos NIC (laboratorio + NAT `default`), `kali-probe.sh --full-scan` con rutas temporales y LAN emulada con `linux-netns.sh test` |
| CachyOS (Arch), kernel 7.3 | Host-only emulada (veth + netns) | **Probado** | 2026-11-22 | `linux-validation-session.sh`: 211/211 |
| Arch Linux, Kernel 7.3 | VirtualBox | **Probado** | 2026-11-28 | En 2 sistemas Arch Linux distintos. Mediante configuración automática del instalador. Tan solo es necesario descarga y descompresión manuales de archivo 7z para la Kali, el resto es automático. Se generan 2 interfaces de red dentro de Kali (Host-Only y NAT) con aislamiento que consigue superar todas las pruebas (nivel 1-5). |
| Debian / Ubuntu | KVM o VirtualBox | No probado | | El instalador reconoce la familia de distribución |
| Fedora | KVM o VirtualBox | No probado | | Ídem |
| openSUSE | KVM o VirtualBox | No probado | | Ídem |
| Windows 11 | VirtualBox + Docker Desktop | No probado | | Instalador, gestor y PoC de red disponibles: [windows.md](installation/windows.md). Sin ejecutar nunca en Windows; analizados con PSScriptAnalyzer y con pruebas unitarias de las reglas del firewall |

## Componentes del anfitrión probado

| Componente | Versión |
|---|---|
| Docker Engine | 29.10.0 (backend `iptables` sobre nf_tables) |
| Docker Compose | 5.8.0 |
| SO | CachyOS, kernel 7.3.5 |
| Python | 3.14.10 (gestor) y 3.10.22 (pruebas unitarias en contenedor) |
| iptables | 1.8.13 (nf_tables) |
| libvirt | 12.9.0 (demonios modulares) |
| `pentestlab-fw` | 1.1.0 |
| ufw y Tailscale | ufw 0.36.2 y Tailscale, activos durante todas las pruebas |
| Kali | Imagen oficial para QEMU, con dos adaptadores |
| Conjunto de versiones | `2026.11.2` ([imágenes](management/actualizaciones.md#3-imágenes-y-digest-actuales)) |

## Validación final (2026-11-23)

| Prueba | Resultado |
|---|---|
| Pruebas unitarias y de política (`unittest`) | 80 correctas |
| ShellCheck (todos los `.sh`) y PSScriptAnalyzer (los `.ps1`, severidad *Warning*) | Sin avisos |
| CI en GitHub Actions: lint, unit (3.10, 3.12 y 3.13) e integración con red emulada | Todo en verde |
| Ciclo de vida del gestor con KVM: persistencia, `restart`, `stop` + `start`, `reset-data` (con y sin confirmación), modo efímero, conflicto de puertos, validación de configuración, `logs`, `diagnose` sin secretos, `update --check` y `network-check` | 28/28 |
| `network-check` con los 4 laboratorios y busybox 1.38.0 en las sondas | 73 comprobaciones, sin fallos |
| Desde la VM de Kali: `kali-probe.sh --full-scan` (rutas temporales, NAT) y kit `--check --full` | Sin fallos |
| LAN emulada contra `virbr-plab` (`linux-netns.sh test`) | Sin fallos |
| Windows 11 | **No probado** (solo análisis estático y pruebas unitarias) |

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

Puedes hacerlo con un Pull Request que modifique este documento o, si no quieres editarlo, con una Issue que incluya esos datos y la salida de las pruebas ([CONTRIBUTING](../CONTRIBUTING.md#1-tipos-de-contribución)). Si alguna prueba falla, abre además un *Informe de error*; si el fallo rompe el aislamiento, sigue la [política de seguridad](../SECURITY.md).
