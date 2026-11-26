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

```bash
scripts/linux/install.sh --phase uninstall
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1 -Phase Uninstall   # como administrador
```

El instalador detiene los laboratorios y elimina **solo** lo registrado en `state/installer.json`:
- **Linux:** `pentestlab-fw` y sus cadenas, la regla de sudoers, la red libvirt `pentestlab`, y la interfaz Host-only con su DHCP;
- **Windows:** las reglas del grupo `PentestLab`, y la interfaz Host-only con su DHCP.

No borra los datos ni las imágenes.

> `./manager reset` **no** sirve para desinstalar: borra los datos, pero vuelve a instalar y arrancar el laboratorio.

## 4. Borrar datos, imágenes y configuración

```bash
# Contenedores y redes de los labs
for p in dvwa juice-shop webgoat mutillidae; do docker compose -p "plab-$p" down --remove-orphans; done

# Volúmenes de datos (irreversible): revisa la lista antes de borrar
docker volume ls --filter label=org.pentestlab.data=true
docker volume rm $(docker volume ls -q --filter label=org.pentestlab.data=true)

# Imágenes (las lista config/versions.json)
docker image ls
docker image rm <imagen>...                # o: docker image prune -a para borrar todas las no usadas

# Configuración y estado locales
rm -rf state/ config/local.json
```

Por último, borra la carpeta del repositorio y la VM de Kali ([KVM](../installation/kvm.md#4-desinstalar), [VirtualBox](../installation/virtualbox.md#5-desinstalar)).

## 5. Dónde va cada cosa

### En el repositorio

Lo que se genera en tu copia del repositorio y no se versiona:

```text
config/local.json              tu configuración: red, puertos, persistencia, límites y zona horaria
state/<lab>.env                variables para Compose (se regeneran en cada operación)
state/mutillidae/              LDIF de Mutillidae descargado y verificado
state/installer.json           lo que ha creado el instalador (para --phase uninstall)
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
| Reglas del grupo `PentestLab` del Firewall de Windows (persistentes) | Windows | fase `Firewall` | fase `Uninstall` |
| Proyectos Compose `plab-<lab>` | Todas | `start` | `docker compose -p plab-<lab> down` |
| Volúmenes `plab-<lab>_*` (datos de DVWA, WebGoat y Mutillidae) | Todas | `start` | `reset-data`, `reset` o `docker volume rm` |
| Bridges `plabe-*` (proxy) y `plabi-*` (redes internas) | Todas | Docker, al crear las redes | `docker compose ... down` |
| Imágenes Docker fijadas | Todas | `install` | `docker image rm` |

El prefijo `plab` está **reservado**: en Linux, el firewall filtra todo lo que entra por interfaces `plab+`. La interfaz de laboratorio no puede llamarse así, y el gestor lo rechaza.
