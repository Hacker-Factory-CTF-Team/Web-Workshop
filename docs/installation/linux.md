# Instalación en Linux

| Distribución | Estado | Hipervisores probados |
|---|---|---|
| Arch Linux / CachyOS | **Probado** (Docker Engine 29.10, Compose 5.8) | **KVM/QEMU** y **VirtualBox 7.x** (automatizado) |
| Debian / Ubuntu | No probado. El instalador reconoce la familia y muestra los comandos | KVM / VirtualBox |
| Fedora | No probado. Ídem | KVM / VirtualBox |
| openSUSE | No probado. Ídem | KVM / VirtualBox |

---

## 1. Requisitos del sistema anfitrión

El gestor (`./manager`) y el instalador (`scripts/linux/install.sh`) aplican comprobaciones estrictas antes de desplegar:

- **Usuario normal (sin `sudo`):** El instalador se niega a ejecutarse bajo `sudo` directo. Pide privilegios únicamente en los pasos puntuales que los requieren (instalación del script de firewall o paquetes del sistema). Tanto Docker (mediante el grupo `docker`) como VirtualBox operan en el perfil de tu usuario.
- **Docker Engine ≥ 28** en modo nativo (*rootful*). Versiones anteriores presentaban problemas de fuga de puertos desde la LAN hacia `127.0.0.1`.
- **Docker Compose ≥ 2.24** (plugin v2: `docker compose`).
- **Backend de firewall `iptables`:** Docker debe usar el driver `iptables` (incluso si corre sobre `iptables-nft`). Se rechaza el backend experimental `nftables` nativo de Docker:
  ```bash
  docker info --format '{{.FirewallBackend.Driver}}'     # debe responder iptables
  ```
- **Sin Docker rootless ni Docker Desktop:** Docker Desktop corre dentro de su propia máquina virtual aislada, lo que elude el firewall del anfitrión.
- **Python ≥ 3.10** (emplea exclusivamente la biblioteca estándar).
- **Fuera de WSL:** Requiere un kernel Linux nativo con soporte de namespaces y filtrado de red.
- **Requisitos si se utiliza VirtualBox:** VirtualBox ≥ 7.0.2 con módulos del kernel cargados (`vboxdrv`, `vboxnetflt`, `vboxnetadp`) y usuario perteneciente al grupo `vboxusers`.

---

## 2. Preparación por distribución

### Arch Linux / CachyOS (probado)

Instala Docker, las dependencias del sistema y, opcionalmente, VirtualBox si eliges este hipervisor:

```bash
# Dependencias base y Docker
sudo pacman -S --needed docker docker-compose python iproute2 iptables curl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

# Si vas a usar VirtualBox en lugar de KVM:
sudo pacman -S --needed virtualbox virtualbox-host-modules-arch
# (O 'virtualbox-host-dkms' si usas un kernel alternativo)
sudo usermod -aG vboxusers "$USER"
sudo modprobe vboxdrv vboxnetflt vboxnetadp
```

> Cierra la sesión y vuelve a iniciarla para que los grupos `docker` y `vboxusers` surtan efecto.

### Debian / Ubuntu (no probado)

Los paquetes de `docker.io` de las distribuciones suelen ser versiones desactualizadas. Instala los paquetes oficiales desde [docs.docker.com/engine/install/](https://docs.docker.com/engine/install/):

```bash
sudo apt-get install -y python3 iproute2 iptables curl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
docker version --format '{{.Server.Version}}'      # debe ser >= 28
```

### Fedora (no probado)

Utiliza el repositorio oficial `docker-ce` ([docs.docker.com/engine/install/fedora/](https://docs.docker.com/engine/install/fedora/)):

```bash
sudo dnf install -y python3 iproute iptables curl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

---

## 3. Hipervisor y red de laboratorio

El proyecto requiere comunicar la máquina atacante Kali Linux con los contenedores vulnerables a través de una red aislada. Elige uno de los dos hipervisores soportados en Linux:

- **[KVM/QEMU](kvm.md)** (probado): Utiliza la red libvirt `pentestlab` (bridge `virbr-plab`).
- **[VirtualBox](virtualbox.md)** (probado y automatizado en Arch Linux): Utiliza una red Host-only (`vboxnet0` o `vboxnetN`) con DHCP acotado y aislamiento de loopback en NAT.

Ambas opciones generan la configuración de red en `config/local.json` (`platform`, `ip`, `iface`).

> [!TIP]
> Si utilizas VirtualBox y ejecutas directamente `./manager install`, el gestor detectará la ausencia de red y configurará automáticamente la interfaz Host-only por ti.

---

## 4. Fases del instalador (`scripts/linux/install.sh`)

En Linux, el instalador por fases se encarga de aprovisionar y validar cada capa del laboratorio:

```bash
scripts/linux/install.sh --phase <fase> [opciones]
```

| Fase | Función en Linux |
|---|---|
| `detect` | Identifica la distro, versión de Docker/Compose, backend de firewall, hipervisores presentes (KVM/VirtualBox) y espacio libre en disco. |
| `deps` | Verifica e instala dependencias del anfitrión (`python3`, `iproute2`, `iptables`, `curl`). |
| `network` | Configura la red aislada en KVM (`--hypervisor kvm`) o VirtualBox (`--hypervisor virtualbox`) y registra la IP en `config/local.json`. |
| `firewall` | Instala `/usr/local/sbin/pentestlab-fw`, aplica sus cadenas iptables y configura una regla acotada en `sudoers`. |
| `images` | Invoca `./manager install` para descargar las imágenes fijadas por digest, verificar recursos SHA-256 e iniciar el asistente de Kali VM en VirtualBox. |
| `kali-vm` | Automatiza el registro, dimensionamiento (vCPU, RAM, VRAM), adaptadores y aislamiento de localhost para la VM de Kali en VirtualBox. |
| `validate` | Ejecuta las comprobaciones de entorno de `./manager diagnose`. |
| `uninstall` | Elimina del anfitrión todo lo anotado en `state/installer.json` (reglas iptables, regla sudoers y red del hipervisor). |

---

## 5. Firewall del laboratorio (`pentestlab-fw`)

La fase `firewall` asegura que el tráfico entre el laboratorio, Kali y el anfitrión permanezca estrictamente controlado:

```bash
scripts/linux/install.sh --phase firewall
```

1. **Instalación del script:** Copia `scripts/linux/pentestlab-fw.sh` a `/usr/local/sbin/pentestlab-fw` (propiedad de `root:root`, permisos `0755`).
2. **Regla de sudoers acotada:** Ofrece crear `/etc/sudoers.d/pentestlab-fw` para permitir que tu usuario ejecute **únicamente** `pentestlab-fw verify` y `pentestlab-fw apply` sin introducir la contraseña de `sudo` en cada arranque. Si deseas responder desatendido: `PLAB_SUDOERS=yes` o `PLAB_SUDOERS=no`.
3. **Aislamiento de la interfaz:** Aplica las reglas en las cadenas iptables (`PLAB-IN`, `PLAB-FWD`, `PLAB-IN6`). El firewall filtra el tráfico de la interfaz del laboratorio (sea `virbr-plab` en KVM o `vboxnetN` en VirtualBox), permitiendo a Kali acceder exclusivamente a los puertos publicados de los laboratorios y bloqueando cualquier intento de alcanzar la LAN o los servicios internos del anfitrión.

Para más detalles sobre las reglas de filtrado, consulta [firewall-linux.md](../networking/firewall-linux.md).

> Si actualizas el repositorio y cambia `pentestlab-fw.sh`, el hash SHA-256 no coincidirá y `./manager start` se bloqueará por seguridad hasta que vuelvas a ejecutar `scripts/linux/install.sh --phase firewall`.

---

## 6. Verificación y pruebas de aislamiento

Tras completar la instalación, valida el laboratorio con las herramientas integradas:

```bash
# Diagnóstico general del gestor y entorno
scripts/linux/install.sh --phase validate        # o: ./manager diagnose

# Si usas VirtualBox, diagnóstico de requisitos de la VM
scripts/linux/install.sh --phase kali-vm --check

# Iniciar laboratorios y verificar conectividad interna
./manager start
./manager network-check
```

Por último, arranca la máquina virtual de Kali y ejecuta la suite de pruebas desde la propia máquina atacante siguiendo la [guía de verificación desde Kali](../testing/pruebas.md#3-desde-la-vm-de-kali) para confirmar que el anfitrión es completamente inalcanzable por la red NAT.
