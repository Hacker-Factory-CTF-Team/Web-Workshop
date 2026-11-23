# Web-Workshop: laboratorio local de pentesting web

Laboratorio local y aislado para practicar pruebas de seguridad web. Despliega cuatro aplicaciones vulnerables a propósito en Docker. Se atacan desde una máquina virtual de Kali Linux conectada a una red privada entre el anfitrión y la VM:

| Aplicación | Tecnología | Puerto por defecto |
|---|---|---:|
| [DVWA](https://github.com/digininja/DVWA) | PHP + MariaDB | 4280 |
| [OWASP Juice Shop](https://github.com/juice-shop/juice-shop) | Node.js + Angular + SQLite | 3000 |
| [OWASP WebGoat](https://github.com/WebGoat/WebGoat) + WebWolf | Java / Spring Boot | 8080 / 9090 |
| [OWASP Mutillidae II](https://github.com/webpwnized/mutillidae-docker) | PHP + MariaDB + OpenLDAP | 8081 (HTTP) / 8443 (HTTPS) |

> [!WARNING]
> **Estas aplicaciones son vulnerables de forma intencionada.** Úsalas solo en este laboratorio local.
> - No las expongas a Internet ni a tu red local.
> - No modifiques la configuración de red para "hacerlas accesibles" desde otros equipos.
> - Ataca únicamente las aplicaciones de este laboratorio.
>
> El gestor bloquea el despliegue si detecta que el aislamiento no se cumple (*fail-closed*).

Esta documentación es solo técnica. No incluye soluciones ni guías para explotar las aplicaciones: la idea es que cada participante las investigue por su cuenta.

## Contenido

1. [Cómo funciona](#1-cómo-funciona)
2. [Requisitos](#2-requisitos)
3. [Instalación en Linux](#3-instalación-en-linux)
4. [Primer uso](#4-primer-uso)
5. [Uso diario del gestor](#5-uso-diario-del-gestor)
6. [Desactivar y desinstalar](#6-desactivar-y-desinstalar)
7. [Dónde va cada cosa](#7-dónde-va-cada-cosa)
8. [Pruebas](#8-pruebas)
9. [Compatibilidad](#9-compatibilidad)
10. [Más documentación y licencia](#10-más-documentación-y-licencia)

## 1. Cómo funciona

```text
   Kali (VM) ──red de laboratorio (Host-only / libvirt)──► IP de laboratorio del anfitrión (p. ej. 192.168.57.1)
                                                             │  solo los puertos de los labs
                                                             ▼
                                             proxy nginx L4 (uno por laboratorio)
                                                             │  red Docker interna (sin salida)
                                                             ▼
                                                aplicación + base de datos/LDAP
```

- Cada aplicación vive en redes Docker **internas**: no tiene salida a Internet ni acceso a otros laboratorios.
- El único contenedor que publica puertos es un **proxy nginx L4** por laboratorio. Solo los publica en `127.0.0.1` y en la IP de laboratorio, nunca en `0.0.0.0`.
- En Linux, el firewall del laboratorio (`pentestlab-fw`) se encarga de:
  - cortar la salida del proxy;
  - impedir que los contenedores lleguen a servicios del anfitrión;
  - impedir que la VM de Kali llegue a algo distinto de los puertos del laboratorio.
- Antes de exponer nada, `./manager start` comprueba:
  - la configuración estática;
  - las conexiones reales desde cada red (salida, DNS, anfitrión y otros labs);
  - las reglas del firewall.

  Si algo falla, no arranca.

## 2. Requisitos

| Requisito | Detalle |
|---|---|
| Sistema operativo | Linux x86-64 con systemd. Probado en Arch/CachyOS. El instalador reconoce también Debian/Ubuntu, Fedora y openSUSE (sin probar) |
| Docker Engine | **≥ 28**, rootful (el normal). No sirven Docker rootless ni Docker Desktop para Linux |
| Docker Compose | Plugin v2, **≥ 2.24** (`docker compose version`) |
| Backend de firewall de Docker | `iptables` (el valor por defecto; también con iptables-nft). Con el backend `nftables` el despliegue se bloquea |
| Python | **≥ 3.10**, solo la biblioteca estándar |
| Utilidades | `ip`/`ss` (iproute2), `iptables`, `curl`, `sudo` |
| Hipervisor | VirtualBox **o** KVM/QEMU con libvirt, para la VM de Kali |
| Usuario | En el grupo `docker` y con permiso de `sudo` |
| Disco | ~5 GB para las imágenes, más la VM de Kali |
| RAM | Los 4 labs usan ~1 GiB en reposo (medido) y como máximo ~4,8 GiB (límites configurados). Con Kali, **8 GiB mínimo y 16 GiB recomendados** |
| CPU | 4 núcleos recomendados. Límites por defecto: DVWA 1,75, Juice Shop 1,25, WebGoat 2,25 y Mutillidae 2 CPU |
| Internet | Solo en el anfitrión y solo durante la instalación (descarga de imágenes). Los labs funcionan sin conexión |

`./manager list` muestra los límites de CPU y RAM de cada laboratorio. Puedes cambiarlos (sección 5).

## 3. Instalación en Linux

> [!IMPORTANT]
> Ejecuta el instalador **como tu usuario, sin `sudo`**. Pide la contraseña solo en los pasos que la necesitan. Si lo lanzas con `sudo`, se niega a continuar.

### 3.1 Antes de empezar

1. Instala Docker Engine y el plugin Compose de tu distribución. En Arch/CachyOS:

   ```bash
   sudo pacman -S --needed docker docker-compose
   sudo systemctl enable --now docker
   sudo usermod -aG docker "$USER"     # cierra sesión y vuelve a entrar
   ```

   En Debian/Ubuntu y Fedora, sigue la [guía oficial de Docker](https://docs.docker.com/engine/install/). La fase `deps` del instalador muestra el comando adecuado para tu sistema.
2. Instala un hipervisor: VirtualBox o KVM/libvirt (`qemu-full libvirt virt-manager dnsmasq` en Arch).
3. Descarga o clona este repositorio en una carpeta de tu usuario y entra en ella.

### 3.2 Instalador guiado

```bash
scripts/linux/install.sh
```

Primero ejecuta la detección (solo lectura). Después pregunta por cada fase:

| Fase | Qué hace | ¿Cambia el sistema? |
|---|---|---|
| `detect` | Distribución, Docker, Compose, backend de firewall, hipervisores, redes existentes y espacio libre | No |
| `deps` | Comprueba python3, iproute2, iptables y curl y ofrece instalar los que falten. **No instala Docker**: solo indica cómo hacerlo | Solo si aceptas |
| `network` | Crea o reutiliza la red de laboratorio: Host-only con DHCP en VirtualBox, o la red libvirt `pentestlab` en KVM. Guarda la IP en `config/local.json` | Sí (con confirmación) |
| `firewall` | Instala `/usr/local/sbin/pentestlab-fw` y aplica sus reglas. Opcionalmente, una regla de sudoers acotada para no pedir contraseña en cada `start` | Sí (con sudo) |
| `images` | `./manager install`: descarga las imágenes fijadas por digest y los recursos verificados por SHA-256 | Solo Docker |
| `validate` | `./manager diagnose` | No |

También puedes ejecutar una fase suelta:

```bash
scripts/linux/install.sh --phase detect
scripts/linux/install.sh --phase network --hypervisor kvm             # IP por defecto 192.168.157.1
scripts/linux/install.sh --phase network --hypervisor virtualbox --ip 192.168.58.1
scripts/linux/install.sh --phase firewall
```

Opciones: `--phase FASE`, `--hypervisor virtualbox|kvm`, `--ip IP`, `--prefix N` (por defecto 24) y `--yes` (acepta las confirmaciones).

Subredes por defecto:

| Hipervisor | Red | IP del anfitrión | DHCP para Kali |
|---|---|---|---|
| VirtualBox | Host-only nueva `vboxnetN` (no reutiliza `vboxnet0`) | `192.168.57.1/24` | `.100`–`.199` |
| KVM | Red libvirt `pentestlab`, bridge `virbr-plab`, sin NAT | `192.168.157.1/24` | `.100`–`.199` |

Si la subred se solapa con una interfaz existente, el instalador se detiene y te pide otra con `--ip`.

### 3.3 Conectar Kali

Kali tiene **dos adaptadores**:

| | VirtualBox | KVM |
|---|---|---|
| 1: laboratorio | *Adaptador solo-anfitrión* → la `vboxnetN` que indicó el instalador | Red `pentestlab` |
| 2: Internet | *NAT* | Red `default` de libvirt (el instalador la prepara y `pentestlab-fw` la gestiona) |

- Por el adaptador 1, Kali recibe una IP por DHCP **sin pasarela**. Desde él solo se alcanzan los puertos de los laboratorios en la IP del anfitrión.
- Por el adaptador 2 tiene Internet para actualizarse e instalar herramientas.
- En KVM, ese NAT funciona mientras las reglas del laboratorio están aplicadas, es decir, tras `./manager start`.

> Guía detallada para KVM, incluida la VM de Kali: [docs/installation/kvm.md](docs/installation/kvm.md). Ajustes dentro de Kali: [docs/kali/preparacion.md](docs/kali/preparacion.md).
>
> Herramientas: dentro de Kali, `kali/install.sh` (menú) o `kali/install.sh --install all`, y después `kali/install.sh --check` ([kit de Kali](docs/kali/preparacion.md#3-kit-de-herramientas-kaliinstallsh)). La instalación estándar de Kali ya trae lo básico para empezar (nmap, Burp Suite, curl...).

## 4. Primer uso

```bash
./manager install        # si no ejecutaste la fase 'images'
./manager start          # todos los laboratorios (o: ./manager start dvwa juice-shop)
```

`start` comprueba el firewall con `sudo pentestlab-fw verify`. Si no instalaste la regla de sudoers, pedirá la contraseña. Si las reglas no están aplicadas (por ejemplo, tras reiniciar el equipo), ofrece aplicarlas.

Al terminar muestra una tabla con las URL. Con la configuración por defecto de VirtualBox:

| Servicio | Desde Kali | Desde el anfitrión |
|---|---|---|
| DVWA | `http://192.168.57.1:4280/` | `http://127.0.0.1:4280/` |
| Juice Shop | `http://192.168.57.1:3000/` | `http://127.0.0.1:3000/` |
| WebGoat | `http://192.168.57.1:8080/WebGoat/` | igual que desde Kali (\*) |
| WebWolf | `http://192.168.57.1:9090/WebWolf/` | igual que desde Kali (\*) |
| Mutillidae (HTTP) | `http://192.168.57.1:8081/` | `http://127.0.0.1:8081/` |
| Mutillidae (HTTPS) | `https://192.168.57.1:8443/` | `https://127.0.0.1:8443/` |

(\*) WebGoat genera los enlaces a WebWolf con la IP de laboratorio. Usa esa IP también desde el anfitrión.

Con KVM, sustituye la IP por `192.168.157.1`. El certificado HTTPS de Mutillidae es autofirmado.

**Acceso inicial:**

| Aplicación | Cómo entrar |
|---|---|
| DVWA | `admin` / `password` (cuenta por defecto del proyecto). La base de datos se crea sola en el primer arranque |
| Juice Shop | Registra una cuenta desde la propia aplicación |
| WebGoat / WebWolf | Registra un usuario en la pantalla de inicio de WebGoat y úsalo también en WebWolf |
| Mutillidae | No hace falta iniciar sesión para empezar. La base de datos y el LDAP se inicializan solos |

## 5. Uso diario del gestor

Sin argumentos, `./manager` abre un menú interactivo. Todos los comandos:

| Comando | Para qué |
|---|---|
| `./manager list` | Laboratorios, puertos, persistencia y límites |
| `./manager status [LAB...]` | Estado, salud, URL y consumo |
| `./manager start [LAB...]` | Arranca tras las comprobaciones de aislamiento |
| `./manager stop [LAB...]` | Detiene sin borrar datos |
| `./manager restart [LAB...]` | Reinicia conservando los datos |
| `./manager logs LAB [SERVICIO] [-f] [-n N]` | Registros (servicios: p. ej. `db`, `edge`) |
| `./manager reset-data [LAB...]` | **Destructivo.** Vuelve a dejar los datos en su estado inicial y arranca |
| `./manager reset [LAB...]` | **Destructivo.** Borra datos y estado generado, reinstala y arranca |
| `./manager network-check [LAB...]` | Pruebas de aislamiento sobre los labs en marcha |
| `./manager update --check` | Consulta si hay versiones nuevas (no cambia nada) |
| `./manager update [LAB...]` | Aplica el conjunto de versiones probado de `config/versions.json` |
| `./manager diagnose` | Informe del entorno para resolver problemas (sin secretos) |
| `./manager config show` | Configuración efectiva |
| `./manager config set-port LAB ENDPOINT PUERTO` | p. ej. `set-port dvwa http 4281` o `set-port webgoat webwolf 9091` |
| `./manager config set-persistence LAB persistent\|ephemeral` | Modo efímero: cada `stop` + `start` vuelve al estado inicial (Juice Shop siempre es efímero) |
| `./manager config set-resources LAB SERVICIO [--cpus N] [--memory 512m]` | Límites por contenedor |
| `./manager config set-timezone ZONA` | Zona horaria IANA, o `auto` |

`LAB` es `dvwa`, `juice-shop`, `webgoat`, `mutillidae` o `all`. Si no indicas ninguno, se aplica a todos.

Opciones globales:
- `--yes` responde "sí" a las confirmaciones, pero nunca se salta una comprobación de seguridad;
- `--accept-port-suggestions` (en `start`, `restart`, `reset-data` y `reset`) acepta el puerto alternativo que se propone si el tuyo está ocupado.

Si un puerto está ocupado, el gestor dice qué proceso lo usa y propone otro. **Nunca lo cambia sin tu permiso.**

Códigos de salida:
- `0`: correcto;
- `1`: error;
- `2`: uso incorrecto;
- `3`: bloqueo de seguridad;
- `4`: falta una dependencia;
- `5`: cancelado por el usuario.

## 6. Desactivar y desinstalar

**Pausar el laboratorio** (los datos se conservan):

```bash
./manager stop all
```

Ningún contenedor arranca solo al reiniciar el equipo (`restart: "no"`), y las reglas de `pentestlab-fw` desaparecen al reiniciar. Tras un reinicio, el laboratorio está apagado hasta el siguiente `./manager start`.

**Quitar las reglas del firewall sin desinstalar:**

```bash
sudo pentestlab-fw remove      # solo borra las cadenas PLAB-*; no toca otras reglas
```

`./manager start` volverá a ofrecer aplicarlas.

**Desinstalar todo lo que creó el instalador:**

```bash
scripts/linux/install.sh --phase uninstall
```

Detiene los labs y elimina solo lo que registró en `state/installer.json`:
- `pentestlab-fw` y sus cadenas;
- la regla de sudoers;
- la red libvirt `pentestlab`, o la interfaz Host-only y su DHCP.

No borra los datos ni las imágenes. Para eso:

```bash
# Contenedores y redes de los labs
for p in dvwa juice-shop webgoat mutillidae; do docker compose -p "plab-$p" down --remove-orphans; done

# Volúmenes de datos (irreversible): revisa la lista antes de borrar
docker volume ls --filter label=org.pentestlab.data=true
docker volume rm $(docker volume ls -q --filter label=org.pentestlab.data=true)

# Imágenes (consulta antes cuáles son: las lista config/versions.json)
docker image ls
docker image rm <imagen>...                # o: docker image prune -a para borrar todas las no usadas

# Configuración y estado locales
rm -rf state/ config/local.json
```

Por último, borra la carpeta del repositorio.

> `./manager reset` **no** sirve para desinstalar: borra los datos, pero vuelve a instalar y arrancar el laboratorio.

## 7. Dónde va cada cosa

### En el repositorio

```text
manager                      punto de entrada (lanza el gestor Python)
config/defaults.json         valores por defecto (no editar)
config/versions.json         versiones probadas: imagen + tag + digest, recursos con SHA-256
config/local.json            tu configuración (generado; no se versiona)
labs/_common/edge/           proxy nginx L4 común y endurecido
labs/<lab>/                  compose.yaml, plantilla del proxy y lab.json (puertos, límites, ganchos)
src/pentestlab/              gestor (Python, solo biblioteca estándar)
scripts/linux/install.sh     instalador por fases
scripts/linux/pentestlab-fw.sh   reglas del firewall (fuente de /usr/local/sbin/pentestlab-fw)
scripts/common/lib.sh        utilidades Bash compartidas
kali/                        kit de herramientas para la VM de Kali (install.sh + modules/*.conf)
tests/                       pruebas unitarias, de política y de red
docs/                        documentación técnica
state/                       generado (no se versiona): <lab>.env, LDIF de Mutillidae, registros, installer.json
```

### Fuera del repositorio

| Elemento | Lo crea | Lo quita |
|---|---|---|
| `/usr/local/sbin/pentestlab-fw` | fase `firewall` | `--phase uninstall` |
| `/etc/sudoers.d/pentestlab-fw` (opcional, solo `verify`/`apply`) | fase `firewall` | `--phase uninstall` |
| Cadenas iptables `PLAB-FWD`, `PLAB-IN`, `PLAB-IN6` (solo en memoria) | `pentestlab-fw apply` | `pentestlab-fw remove`, reinicio o `--phase uninstall` |
| Red libvirt `pentestlab` (bridge `virbr-plab`) | fase `network` (KVM) | `--phase uninstall` |
| Red libvirt `default` en marcha y con arranque automático (NAT de Kali) | fase `network` (KVM), si aceptas | No se quita: es de libvirt (`virsh net-autostart default --disable`) |
| Interfaz `vboxnetN` y su DHCP | fase `network` (VirtualBox) | `--phase uninstall` |
| Proyectos Compose `plab-<lab>` | `./manager start` | `docker compose -p plab-<lab> down` |
| Volúmenes `plab-<lab>_*` (datos de DVWA, WebGoat y Mutillidae) | `./manager start` | `reset-data`, `reset` o `docker volume rm` |
| Bridges `plabe-*` (proxy) y `plabi-*` (redes internas) | Docker, al crear las redes | `docker compose ... down` |
| Imágenes Docker fijadas | `./manager install` | `docker image rm` |

El prefijo `plab` está **reservado**: el firewall filtra todo lo que entra por interfaces `plab+`. La interfaz de laboratorio no puede llamarse así, y el gestor lo rechaza.

## 8. Pruebas

```bash
python3 -m unittest discover -s tests -t .
```

- Son pruebas unitarias y de política. No necesitan red ni root y no escriben en el repositorio.
- `tests/security` usa `docker compose config`, así que se omite si no está Compose.
- Las pruebas de red reales necesitan root. Emulan la VM de Kali y una máquina de la LAN con *network namespaces*:

  ```bash
  sudo tests/network/linux-netns.sh test              # LAN emulada contra la interfaz real (labs arrancados)
  bash tests/network/linux-validation-session.sh      # validación completa sin VM; registro en state/
  sudo tests/network/linux-netns.sh cleanup           # quita la red emulada al terminar
  ```

  `linux-validation-session.sh` cambia `config/local.json` a la red emulada: después hay que restaurar la configuración real ([pruebas](docs/testing/pruebas.md#5-validación-completa-sin-vm)).
- Desde la VM de Kali: `tests/network/kali-probe.sh` comprueba que solo se alcanzan los puertos del laboratorio.

Detalle de todos los niveles de prueba: [docs/testing/pruebas.md](docs/testing/pruebas.md).

## 9. Compatibilidad

Solo se marca como probado lo que se ha probado de verdad.

| Entorno | Estado |
|---|---|
| CachyOS (Arch), Docker Engine 29.10, Compose 5.8, iptables-nft, con Kali y LAN emuladas | **Probado** (211/211 comprobaciones de red) |
| CachyOS + KVM/libvirt 12.9 con una VM de Kali real (laboratorio + NAT) | **Probado** (aislamiento verificado desde Kali y desde una LAN emulada) |
| Linux + VirtualBox con una VM real | No probado |
| Debian/Ubuntu, Fedora, openSUSE | No probado (el instalador los reconoce) |
| Windows 11 + Docker Desktop + VirtualBox | No probado. El instalador de Windows aún no está disponible |

## 10. Más documentación y licencia

- [`docs/`](docs/README.md): documentación técnica ampliada. Incluye:
  - [instalación](docs/installation/README.md) ([KVM y Kali](docs/installation/kvm.md), [VirtualBox](docs/installation/virtualbox.md));
  - [red](docs/networking/README.md) y [firewall](docs/networking/firewall-linux.md);
  - [preparación de Kali](docs/kali/preparacion.md);
  - [uso del gestor](docs/management/gestor.md), [recursos](docs/management/recursos.md), [restauración](docs/management/restauracion.md) y [actualizaciones](docs/management/actualizaciones.md);
  - fichas de las aplicaciones ([DVWA](docs/labs/dvwa.md), [Juice Shop](docs/labs/juice-shop.md), [WebGoat](docs/labs/webgoat.md), [Mutillidae](docs/labs/mutillidae.md));
  - [pruebas](docs/testing/pruebas.md), [resolución de problemas](docs/troubleshooting/README.md), [compatibilidad](docs/compatibilidad.md) y [decisiones de diseño (ADR)](docs/README.md).

Código bajo [licencia MIT](LICENSE). Las aplicaciones vulnerables y sus imágenes pertenecen a sus proyectos y mantienen sus propias licencias. El LDIF de Mutillidae (GPL-3.0) no se redistribuye: se descarga durante la instalación y se verifica su SHA-256.
