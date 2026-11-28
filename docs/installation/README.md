# Instalación

## Orden recomendado

1. **Sistema anfitrión** (Docker y utilidades): [Linux por distribución](linux.md).
2. **Hipervisor y red de laboratorio**: elige uno.
   - [KVM/QEMU](kvm.md). **Probado**, recomendado en Linux.
   - [VirtualBox](virtualbox.md). **Probado en Arch Linux**, con automatización completa de la VM de Kali.
   - En Windows 11: [windows.md](windows.md), que sustituye a los pasos 1–3. Sin probar.
3. **Firewall e imágenes**: `scripts/linux/install.sh --phase firewall` y `--phase images` (ver [linux.md](linux.md#4-firewall-e-imágenes)).
4. **VM de Kali** conectada a la red de laboratorio:
   - En VirtualBox (Linux), se automatiza con `scripts/linux/install.sh --phase kali-vm` (o de forma guiada al ejecutar `./manager install`).
   - En KVM, sigue las instrucciones de [KVM](kvm.md).
   - Los ajustes de herramientas y red dentro de Kali: ver [preparación de Kali](../kali/preparacion.md).
5. **Primer arranque y verificación**: `./manager start` y las [pruebas de aislamiento](../testing/pruebas.md).

**Windows 11**: guía propia en [windows.md](windows.md) (Docker Desktop + VirtualBox), marcada *no probado*.

## Qué hace el instalador de Linux

`scripts/linux/install.sh` se ejecuta **como tu usuario, nunca con `sudo`**. Pide la contraseña solo en los pasos que la necesitan y se niega a ejecutarse bajo `sudo`.

| Fase | Qué hace | Cambia el sistema |
|---|---|---|
| `detect` | Detecta la distribución, Docker, Compose, el backend de firewall, los hipervisores, las redes existentes y el espacio libre | No |
| `deps` | Comprueba python3, iproute2, iptables y curl y ofrece instalarlos. Docker no lo instala: solo indica cómo | Solo si aceptas |
| `network` | Crea o reutiliza la red de laboratorio y guarda la IP y la interfaz en `config/local.json` | Sí |
| `firewall` | Instala `/usr/local/sbin/pentestlab-fw`, aplica sus reglas y, opcionalmente, añade una regla de sudoers acotada | Sí (sudo) |
| `images` | Ejecuta `./manager install` (que a su vez incluye el paso de la VM de Kali si la plataforma es VirtualBox) | Solo Docker / VirtualBox |
| `kali-vm` | Registra, dimensiona, configura adaptadores y aísla la VM oficial de Kali Linux en VirtualBox | Sí (VirtualBox) |
| `validate` | Ejecuta `./manager diagnose` | No |
| `uninstall` | Deshace lo registrado en `state/installer.json` (red, firewall y sudoers) | Sí |

Opciones: `--phase FASE`, `--hypervisor virtualbox|kvm`, `--ip IP`, `--prefix N` y `--yes`.

Fases disponibles: `detect`, `deps`, `network`, `firewall`, `images`, `kali-vm`, `validate`, `uninstall`.

Sin `--phase`, ejecuta `detect` y después pregunta por cada fase en orden. Cómo interactúa cada fase con libvirt, el gestor y el firewall: [diagrama de la instalación](../architecture/README.md#instalación-guiada-linux-con-kvm).

Todo lo que crea queda anotado en `state/installer.json`, y `--phase uninstall` solo elimina lo anotado ahí. No borra datos de los laboratorios ni imágenes; para eso, ver la [guía de desinstalación](../management/desinstalacion.md#4-borrar-datos-imágenes-y-configuración).
