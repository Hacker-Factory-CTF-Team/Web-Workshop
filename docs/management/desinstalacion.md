# Desactivar, desinstalar y dónde va cada cosa

## 1. Pausar el laboratorio

```bash
./manager stop all          # Windows: .\manager.ps1 stop all
```

Los datos se conservan. Ningún contenedor arranca solo al reiniciar el equipo (`restart: "no"`): tras un reinicio, el laboratorio está apagado hasta el siguiente `start`.

En Linux, además, las reglas de `pentestlab-fw` desaparecen al reiniciar; `start` las vuelve a aplicar. En Windows, las reglas del grupo `PentestLab` son persistentes.

## 2. Quitar solo el firewall

Linux, solo borra las cadenas `PLAB-*` y no toca otras reglas:

```bash
sudo pentestlab-fw remove
```

`./manager start` volverá a ofrecer aplicarlas.

Windows (como administrador):

```powershell
Get-NetFirewallRule -Group PentestLab | Remove-NetFirewallRule
```

`start` se bloqueará hasta que vuelvas a crear las reglas con la fase `Firewall`.

## 3. Desinstalar lo que creó el instalador

El instalador separa limpiamente los componentes del anfitrión de la máquina virtual de Kali.

### 3.1. Desinstalar componentes del anfitrión (red, firewall y sudoers)

```bash
scripts/linux/install.sh --phase uninstall
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1 -Phase Uninstall   # como administrador
```

El instalador detiene los laboratorios y elimina **solo** lo registrado en `state/installer.json`:
- **Linux:** `pentestlab-fw` y sus cadenas, la regla de sudoers, la red libvirt `pentestlab`, y la interfaz Host-only con su servidor DHCP;
- **Windows:** las reglas del grupo `PentestLab`, y la interfaz Host-only con su DHCP.

No borra los datos ni las imágenes de los laboratorios.

> `./manager reset` **no** sirve para desinstalar: borra los datos, pero vuelve a instalar y arrancar el laboratorio.

### 3.2. Desregistrar la VM de Kali en VirtualBox

Si utilizas VirtualBox en Linux y creaste la máquina mediante el instalador (o `./manager install`), puedes desregistrarla sin tocar el disco base:

```bash
scripts/linux/install.sh --phase kali-vm --remove
```

Este comando:
1. Verifica que la máquina virtual esté apagada (si está encendida, se niega a actuar para evitar corrupciones).
2. Solicita confirmación al usuario.
3. Desregistra la VM de VirtualBox mediante `VBoxManage unregistervm`.
4. Elimina el archivo de estado `state/kali-vm.json`.
5. **Conserva intacto el archivo `.vdi` descargado**, evitando tener que volver a descargarlo si deseas recrear el entorno.
6. Muestra la ruta de la carpeta de configuración de la VM (por ejemplo `~/VirtualBox VMs/kali-plab`), indicando el comando para eliminarla si deseas borrarla por completo:
   ```bash
   rm -rf "$HOME/VirtualBox VMs/<nombre-vm>"
   ```

## 4. Borrar datos, imágenes y configuración

Para realizar una limpieza exhaustiva del laboratorio:

```bash
# 1. Contenedores y redes de los labs
for p in dvwa juice-shop webgoat mutillidae; do docker compose -p "plab-$p" down --remove-orphans; done

# 2. Volúmenes de datos (irreversible): revisa la lista antes de borrar
docker volume ls --filter label=org.pentestlab.data=true
docker volume rm $(docker volume ls -q --filter label=org.pentestlab.data=true)

# 3. Imágenes Docker (las lista config/versions.json)
docker image ls
docker image rm <imagen>...                # o: docker image prune -a para borrar todas las no usadas

# 4. Configuración y estado locales
rm -rf state/ config/local.json

# 5. Disco de Kali descargado (opcional, para liberar ~12-15 GB en disco)
rm -f *.vdi *.vbox
```

Por último, si no vas a utilizar más el laboratorio, borra la carpeta del repositorio y la VM del hipervisor ([KVM](../installation/kvm.md#4-desinstalar), [VirtualBox](../installation/virtualbox.md#6-desinstalación-y-limpieza)).

## 5. Dónde va cada cosa

### En el repositorio

Lo que se genera en tu copia del repositorio y no se versiona:

```text
config/local.json              tu configuración: red, puertos, persistencia, límites y zona horaria
state/<lab>.env                variables para Compose (se regeneran en cada operación)
state/mutillidae/              LDIF de Mutillidae descargado y verificado
state/installer.json           lo que ha creado el instalador (para --phase uninstall)
state/kali-vm.json             metadatos de la VM de Kali en VirtualBox (para --phase kali-vm --remove)
state/*.log                    registros de las pruebas de red
```

El mapa completo del repositorio está en la [guía de desarrollo](../development/README.md#2-mapa-del-repositorio).

### Fuera del repositorio

| Elemento | Plataforma | Lo crea | Lo quita |
|---|---|---|---|
| `/usr/local/sbin/pentestlab-fw` | Linux | fase `firewall` | fase `uninstall` |
| `/etc/sudoers.d/pentestlab-fw` (opcional, solo `verify`/`apply`) | Linux | fase `firewall` | fase `uninstall` |
| Cadenas iptables `PLAB-FWD`, `PLAB-IN`, `PLAB-IN6` (solo en memoria) | Linux | `pentestlab-fw apply` | `pentestlab-fw remove`, reinicio o fase `uninstall` |
| Red libvirt `pentestlab` (bridge `virbr-plab`) | Linux + KVM | fase `network` | fase `uninstall` |
| Red libvirt `default` en marcha y con arranque automático (NAT de Kali) | Linux + KVM | fase `network`, si aceptas | No se quita: es de libvirt (`virsh net-autostart default --disable`) |
| Interfaz Host-only (`vboxnetN` / `VirtualBox Host-Only Ethernet Adapter #N`) y su DHCP | VirtualBox | fase `network` | fase `uninstall` |
| VM de Kali registrada en VirtualBox (`kali-plab` o nombre oficial) | VirtualBox | fase `kali-vm` (o `./manager install`) | `scripts/linux/install.sh --phase kali-vm --remove` |
| Carpeta de la máquina en VirtualBox (`~/VirtualBox VMs/<nombre>`) | VirtualBox | VirtualBox al registrarse | Manual (`rm -rf ...`) tras desregistrar |
| Reglas del grupo `PentestLab` del Firewall de Windows (persistentes) | Windows | fase `Firewall` | fase `Uninstall` |
| Proyectos Compose `plab-<lab>` | Todas | `start` | `docker compose -p plab-<lab> down` |
| Volúmenes `plab-<lab>_*` (datos de DVWA, WebGoat y Mutillidae) | Todas | `start` | `reset-data`, `reset` o `docker volume rm` |
| Bridges `plabe-*` (proxy) y `plabi-*` (redes internas) | Todas | Docker, al crear las redes | `docker compose ... down` |
| Imágenes Docker fijadas | Todas | `install` | `docker image rm` |

El prefijo `plab` está **reservado**: en Linux, el firewall filtra todo lo que entra por interfaces `plab+`. La interfaz de laboratorio no puede llamarse así, y el gestor lo rechaza.
