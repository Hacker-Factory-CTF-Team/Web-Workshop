# Instalación

## Orden recomendado

1. **Sistema anfitrión** (Docker y utilidades): [Linux por distribución](linux.md).
2. **Hipervisor y red de laboratorio**: elige uno.
   - [KVM/QEMU](kvm.md). **Probado**, recomendado en Linux.
   - [VirtualBox](virtualbox.md). Sin probar con una VM real.
   - En Windows 11: [windows.md](windows.md), que sustituye a los pasos 1–3. Sin probar.
3. **Firewall e imágenes**: `scripts/linux/install.sh --phase firewall` y `--phase images` (ver [linux.md](linux.md#4-firewall-e-imágenes)).
4. **VM de Kali** conectada a la red de laboratorio: está explicado en la guía de cada hipervisor; los ajustes dentro de Kali, en [preparación de Kali](../kali/preparacion.md).
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
| `images` | Ejecuta `./manager install` | Solo Docker |
| `validate` | Ejecuta `./manager diagnose` | No |
| `uninstall` | Deshace lo registrado en `state/installer.json` | Sí |

Opciones: `--phase FASE`, `--hypervisor virtualbox|kvm`, `--ip IP`, `--prefix N` y `--yes`.

Sin `--phase`, ejecuta `detect` y después pregunta por cada fase en orden. Cómo interactúa cada fase con libvirt, el gestor y el firewall: [diagrama de la instalación](../architecture/README.md#instalación-guiada-linux-con-kvm).

Todo lo que crea queda anotado en `state/installer.json`, y `--phase uninstall` solo elimina lo anotado ahí. No borra datos de los laboratorios ni imágenes; para eso, ver la [guía de desinstalación](../management/desinstalacion.md#4-borrar-datos-imágenes-y-configuración).
