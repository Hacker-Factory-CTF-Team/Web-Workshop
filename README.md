# Web-Workshop: laboratorio local de pentesting web

[![CI](https://github.com/Hacker-Factory-CTF-Team/Web-Workshop/actions/workflows/ci.yml/badge.svg)](https://github.com/Hacker-Factory-CTF-Team/Web-Workshop/actions/workflows/ci.yml)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE)

Laboratorio **local y aislado** para practicar pruebas de seguridad web. Cada participante lo ejecuta en su propio equipo: cuatro aplicaciones vulnerables a propósito corren en Docker y se atacan desde una máquina virtual de **Kali Linux** conectada al anfitrión por una red privada.

| Aplicación | Tecnología | Puertos | Ficha técnica |
|---|---|---|---|
| [DVWA](https://github.com/digininja/DVWA) | PHP + MariaDB | 4280 | [dvwa.md](docs/labs/dvwa.md) |
| [OWASP Juice Shop](https://github.com/juice-shop/juice-shop) | Node.js + Angular + SQLite | 3000 | [juice-shop.md](docs/labs/juice-shop.md) |
| [OWASP WebGoat](https://github.com/WebGoat/WebGoat) + WebWolf | Java / Spring Boot | 8080 / 9090 | [webgoat.md](docs/labs/webgoat.md) |
| [OWASP Mutillidae II](https://github.com/webpwnized/mutillidae-docker) | PHP + MariaDB + OpenLDAP | 8081 / 8443 (HTTPS) | [mutillidae.md](docs/labs/mutillidae.md) |

> [!WARNING]
> **Estas aplicaciones son vulnerables de forma intencionada.** Úsalas solo en este laboratorio.
> - No las expongas a Internet ni a tu red local.
> - No cambies la configuración de red para "hacerlas accesibles" desde otros equipos.
> - Ataca únicamente las aplicaciones del laboratorio.
>
> El gestor **bloquea el despliegue** si detecta que no se cumple el aislamiento (*fail-closed*).

La documentación es solo técnica: no incluye soluciones ni pistas. La idea es que cada participante investigue las aplicaciones por su cuenta.

**Contenido:** [Cómo funciona](#cómo-funciona) · [Inicio rápido](#inicio-rápido) · [Acceso a las aplicaciones](#acceso-a-las-aplicaciones) · [Guías](#guías) · [Requisitos](#requisitos) · [El gestor en 1 minuto](#el-gestor-en-1-minuto) · [Compatibilidad](#compatibilidad) · [Estructura del repositorio](#estructura-del-repositorio) · [Licencia](#licencia)

## Cómo funciona

```text
  Kali (VM) ── adaptador 1: red de laboratorio ──► IP de laboratorio del anfitrión (192.168.157.1 / 192.168.57.1)
      │                                                   │  solo los puertos de los laboratorios
      └── adaptador 2: NAT (Internet para Kali)           ▼
                                               proxy nginx L4 (uno por laboratorio)
                                                          │  redes Docker internas, sin salida
                                                          ▼
                                             aplicación + base de datos / LDAP
```

- **Aplicaciones aisladas.** Viven en redes Docker internas: sin Internet, sin acceso a otros laboratorios y sin puertos publicados.
- **Un único punto de entrada.** Un proxy nginx L4 por laboratorio publica los puertos, solo en `127.0.0.1` y en la IP de laboratorio, nunca en `0.0.0.0`.
- **Firewall del anfitrión.** Hay un firewall propio del laboratorio: [`pentestlab-fw`](docs/networking/firewall-linux.md) en Linux y [reglas `PentestLab`](docs/installation/windows.md#5-reglas-del-firewall-de-windows) en Windows. Garantiza que:
  - la LAN no llega a los laboratorios;
  - Kali solo alcanza sus puertos;
  - en Linux, además, el proxy no tiene salida.
- **Comprobaciones en cada arranque.** Antes y después de cada `start`, el gestor comprueba:
  - la configuración que Docker va a desplegar;
  - conexiones reales desde cada red;
  - las reglas del firewall.

  Si algo falla, no arranca.

Más detalle: [configuración de red](docs/networking/README.md) y las decisiones de diseño ([ADR](docs/README.md)).

## Inicio rápido

### Linux con KVM (probado)

```bash
# 1. Docker Engine >= 28 y KVM/libvirt instalados (ver guías), y este repositorio clonado
# 2. Instalador guiado: ejecútalo como tu usuario, NUNCA con sudo
scripts/linux/install.sh --hypervisor kvm

# 3. Crea la VM de Kali con dos adaptadores (red 'pentestlab' + red 'default')
#    -> docs/installation/kvm.md#3-vm-de-kali

# 4. Arranca los laboratorios (comprueba el aislamiento antes de exponer nada)
./manager start

# 5. Dentro de Kali: herramientas y comprobación de conectividad
kali/install.sh --install all
kali/install.sh --check --full
```

Paso a paso: [Linux por distribución](docs/installation/linux.md) → [KVM y VM de Kali](docs/installation/kvm.md) → [Preparación de Kali](docs/kali/preparacion.md).

Con **VirtualBox** en Linux es igual, con `--hypervisor virtualbox` ([guía](docs/installation/virtualbox.md), *no probado*).

### Windows 11 (no probado)

```powershell
# PowerShell como administrador, desde la carpeta del repositorio
powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1
powershell -ExecutionPolicy Bypass -File scripts\windows\poc-network.ps1   # prueba de red: antes del primer uso
powershell -ExecutionPolicy Bypass -File .\manager.ps1 start
```

Lee antes la [guía de Windows](docs/installation/windows.md): explica los requisitos (Docker Desktop, Python, VirtualBox) y en qué es más débil el aislamiento que en Linux.

## Acceso a las aplicaciones

`./manager status` muestra las URL. Con la configuración por defecto (usa `192.168.57.1` en lugar de `192.168.157.1` con VirtualBox o Windows):

| Aplicación | Desde Kali | Desde el anfitrión | Acceso inicial |
|---|---|---|---|
| DVWA | `http://192.168.157.1:4280/` | `http://127.0.0.1:4280/` | `admin` / `password` |
| Juice Shop | `http://192.168.157.1:3000/` | `http://127.0.0.1:3000/` | Registra una cuenta |
| WebGoat | `http://192.168.157.1:8080/WebGoat/` | Igual que desde Kali (\*) | Registra un usuario |
| WebWolf | `http://192.168.157.1:9090/WebWolf/` | Igual que desde Kali (\*) | El usuario de WebGoat |
| Mutillidae | `http://192.168.157.1:8081/` · `https://…:8443/` | `http://127.0.0.1:8081/` | No hace falta |

(\*) WebGoat enlaza con WebWolf usando la IP de laboratorio, así que usa esa IP también desde el anfitrión. El certificado HTTPS de Mutillidae es autofirmado.

## Guías

| Quiero... | Guía |
|---|---|
| Preparar el anfitrión Linux (Docker, requisitos por distribución) | [installation/linux.md](docs/installation/linux.md) |
| Configurar KVM y crear la VM de Kali | [installation/kvm.md](docs/installation/kvm.md) |
| Usar VirtualBox en Linux | [installation/virtualbox.md](docs/installation/virtualbox.md) |
| Instalar en Windows 11 | [installation/windows.md](docs/installation/windows.md) |
| Preparar Kali e instalar las herramientas del taller | [kali/preparacion.md](docs/kali/preparacion.md) |
| Arrancar, parar, ver registros… (todos los comandos y el menú) | [management/gestor.md](docs/management/gestor.md) |
| Devolver un laboratorio a su estado inicial | [management/restauracion.md](docs/management/restauracion.md) |
| Ajustar CPU y memoria | [management/recursos.md](docs/management/recursos.md) |
| Cambiar puertos o la subred de laboratorio | [networking/README.md](docs/networking/README.md) |
| Entender el firewall del laboratorio | [Linux](docs/networking/firewall-linux.md) · [Windows](docs/installation/windows.md#5-reglas-del-firewall-de-windows) |
| Actualizar las aplicaciones | [management/actualizaciones.md](docs/management/actualizaciones.md) |
| Comprobar que el aislamiento funciona | [testing/pruebas.md](docs/testing/pruebas.md) |
| Resolver un problema | [troubleshooting/README.md](docs/troubleshooting/README.md) |
| Desactivarlo, desinstalarlo o saber qué instala y dónde | [management/desinstalacion.md](docs/management/desinstalacion.md) |
| Conocer las decisiones de diseño | [ADR 0001](docs/adr/0001-arquitectura-proxy-l4-redes-internas.md) · [0002](docs/adr/0002-salida-del-proxy-firewall-y-dns.md) · [0003](docs/adr/0003-gestor-python-biblioteca-estandar.md) · [0004](docs/adr/0004-fijado-de-versiones.md) |

Índice completo: [docs/README.md](docs/README.md).

## Requisitos

| | Linux | Windows 11 |
|---|---|---|
| Contenedores | Docker Engine **≥ 28** (rootful) y Compose **≥ 2.24**, backend de firewall `iptables` | Docker Desktop con WSL2 (Engine ≥ 28) |
| Hipervisor | KVM/libvirt (recomendado) o VirtualBox | VirtualBox 7 |
| Python | ≥ 3.10, solo la biblioteca estándar | ≥ 3.10 |
| Otros | `iproute2`, `iptables`, `curl`; usuario en el grupo `docker` y con `sudo` | PowerShell 5.1 o 7, administrador para algunas fases |
| RAM | Los 4 laboratorios: ~1 GiB en reposo y ~4,8 GiB como máximo. Con Kali, **8 GiB mínimo y 16 GiB recomendados** | 16 GiB recomendados |
| Disco | ~5 GB de imágenes, más la VM de Kali | Ídem |
| Internet | Solo en el anfitrión y durante la instalación. Los laboratorios funcionan sin conexión | Ídem |

Detalle: [Linux](docs/installation/linux.md#1-requisitos-que-comprueba-el-gestor) · [Windows](docs/installation/windows.md#2-requisitos) · [recursos y límites](docs/management/recursos.md).

## El gestor en 1 minuto

`./manager` (en Windows, `.\manager.ps1`) maneja todo. Sin argumentos, abre un menú.

```bash
./manager status                     # estado, URL y consumo
./manager start [dvwa juice-shop…]   # arranca (todos si no indicas ninguno)
./manager stop all                   # detiene sin borrar datos
./manager logs webgoat -f            # registros
./manager reset-data dvwa            # vuelve al estado inicial (pide confirmación)
./manager network-check              # pruebas de aislamiento
./manager config set-port dvwa http 4281
./manager diagnose                   # informe para pedir ayuda
```

Si un puerto está ocupado, el gestor dice qué proceso lo usa y propone otro; nunca lo cambia sin tu permiso. Referencia completa: [management/gestor.md](docs/management/gestor.md).

## Compatibilidad

Solo se marca como **probado** lo que se ha ejecutado de verdad.

| Entorno | Estado |
|---|---|
| CachyOS (Arch) + Docker Engine 29.10 + KVM/libvirt 12.9, con una VM de Kali real | **Probado**: aislamiento desde Kali y desde una LAN emulada, kit de Kali y ciclo de vida del gestor |
| Ubuntu (runner de GitHub Actions) con red de laboratorio y Kali emuladas | **Probado en el CI** en cada cambio |
| Linux + VirtualBox | No probado |
| Debian/Ubuntu, Fedora y openSUSE como anfitrión | No probado (el instalador los reconoce) |
| Windows 11 + Docker Desktop + VirtualBox | **No probado**: instalador, gestor y prueba de red disponibles |

Matriz detallada, con versiones: [docs/compatibilidad.md](docs/compatibilidad.md).

## Estructura del repositorio

```text
manager, manager.ps1    gestor (Linux / Windows)
config/                 valores por defecto, versiones fijadas (tag + digest) y tu config/local.json
labs/                   un proyecto Docker Compose por aplicación + proxy común
src/pentestlab/         código del gestor (Python, biblioteca estándar)
scripts/                instaladores de Linux y Windows y firewall de Linux
kali/                   kit de herramientas para la VM de Kali
tests/                  pruebas unitarias, de política y de red
docs/                   documentación técnica
```

Qué instala fuera del repositorio y cómo quitarlo: [management/desinstalacion.md](docs/management/desinstalacion.md#5-dónde-va-cada-cosa). Para ejecutar las pruebas: `python3 -m unittest discover -s tests -t .` ([todos los niveles](docs/testing/pruebas.md)).

## Licencia

Código bajo [licencia MIT](LICENSE). Las aplicaciones vulnerables y sus imágenes pertenecen a sus proyectos y mantienen sus propias licencias. El LDIF de Mutillidae (GPL-3.0) no se redistribuye: se descarga durante la instalación y se verifica su SHA-256.
