# VirtualBox en Linux

**Estado: probado y automatizado en Arch Linux** (VirtualBox 7.x con VM oficial de Kali Linux).

Este documento detalla la instalación, configuración de red, aprovisionamiento automatizado y manual de la máquina atacante Kali Linux, y las medidas de seguridad críticas aplicadas para aislar el laboratorio del anfitrión.

---

## 1. Instalar VirtualBox en Linux

Instala VirtualBox desde los repositorios de tu distribución o desde la [web oficial de VirtualBox](https://www.virtualbox.org/wiki/Linux_Downloads). Se requiere **VirtualBox ≥ 7.0.2** para disponer del control de aislamiento de localhost en adaptadores NAT (`--nat-localhostreachable<N>`).

### En Arch Linux / CachyOS (probado)

```bash
sudo pacman -S --needed virtualbox virtualbox-host-modules-arch
# O si usas un kernel personalizado (ej. linux-zen, linux-lts):
# sudo pacman -S virtualbox-host-dkms
sudo usermod -aG vboxusers "$USER"
```

Carga los módulos del kernel de VirtualBox o reinicia el sistema:

```bash
sudo modprobe vboxdrv vboxnetflt vboxnetadp
```

Verifica la versión instalada y que los módulos estén activos:

```bash
VBoxManage --version          # debe ser >= 7.0.2
lsmod | grep vboxdrv
```

> [!IMPORTANT]
> VirtualBox almacena su configuración y registro de máquinas virtuales **por perfil de usuario**. Todas las operaciones con `VBoxManage` y los scripts del instalador deben ejecutarse **con tu usuario normal, nunca con `sudo`**.

---

## 2. Red de laboratorio (Host-only)

Los laboratorios vulnerables se exponen en una red privada de tipo *Host-only* (solo anfitrión) administrada por VirtualBox:

```bash
scripts/linux/install.sh --phase network --hypervisor virtualbox
# con subred personalizada: --ip 192.168.58.1
```

> [!TIP]
> Si ejecutas directamente `./manager install`, el gestor comprueba si la plataforma está configurada y, de no estarlo, invoca automáticamente esta fase de red sin que tengas que lanzarla a mano.

El instalador realiza las siguientes acciones:
1. **Reutiliza** una interfaz Host-only si ya tiene asignada la IP del laboratorio (`192.168.57.1/24` o `192.168.56.1/24`). Nunca modifica interfaces en uso por otras máquinas.
2. Si no existe, comprueba que la subred no se solapa y **crea una nueva interfaz** (`VBoxManage hostonlyif create`).
3. **Activa el servidor DHCP** de VirtualBox en esa interfaz: pasarela `.1`, IP de servidor `.2`, y rango dinámico `.100`–`.199` para que Kali reciba su IP automáticamente, suprimiendo el anuncio de pasarela predeterminada y DNS (`--suppress-opt=3 --suppress-opt=6`).
4. Guarda en `config/local.json` la plataforma `linux-virtualbox`, la IP y el nombre de la interfaz (`vboxnetN`).

### Rango permitido por VirtualBox

Desde VirtualBox 6.1.28, en Linux las redes Host-only están restringidas por omisión al bloque `192.168.56.0/21` (de `192.168.56.0` a `192.168.63.255`). La IP por defecto del proyecto (`192.168.57.1`) entra en este rango.

Si deseas utilizar otro rango privado (por ejemplo `10.57.0.0/24`), debes añadirlo previamente como `root` en `/etc/vbox/networks.conf`:

```text
* 10.57.0.0/24
```

---

## 3. Aprovisionamiento de la VM de Kali

Dispones de dos métodos para incorporar la máquina atacante Kali Linux: el método automatizado (recomendado e integrado en el instalador) y el método manual paso a paso.

### Método A: Automatizado con `install.sh --phase kali-vm` (Recomendado)

El instalador incorpora la fase `kali-vm`, probada y verificada en Arch Linux, que se encarga del registro, dimensionamiento de hardware, doble interfaz de red y endurecimiento de seguridad:

```bash
# 1. Comprobación previa (no modifica nada)
scripts/linux/install.sh --phase kali-vm --check

# 2. Descarga la imagen oficial de VirtualBox (formato .7z) desde:
#    https://www.kali.org/get-kali/#kali-virtual-machines
#    Descomprímela en la raíz del repositorio:
7z x kali-linux-*-virtualbox-amd64.7z

# 3. Ejecuta el asistente interactivo (o usa --ready si ya descomprimiste el .vdi)
scripts/linux/install.sh --phase kali-vm
```

#### Opciones avanzadas de `kali-vm`

| Opción | Descripción |
|---|---|
| `--check` | Diagnóstico de solo lectura. Comprueba la versión de VirtualBox, estado de la red Host-only, servidor DHCP, disco `.vdi` y aislamiento de NAT sin aplicar cambios. |
| `--ready` | Salta la confirmación interactiva de descarga y pasa directamente al registro. |
| `--adopt` | Adopta y reconfigura una VM preexistente en VirtualBox siempre que utilice el mismo archivo `.vdi`. |
| `--remove` | Desregistra la VM de VirtualBox y limpia `state/kali-vm.json`. **Conserva intacto el disco `.vdi`**. |
| `--vdi RUTA` | Ruta explícita al `.vdi`. Por defecto, el script busca archivos `.vdi` en el repositorio (hasta 3 niveles). |
| `--vbox RUTA` | Ruta explícita al archivo `.vbox` oficial a importar. |
| `--name NOMBRE` | Nombre que recibirá la VM en VirtualBox (por defecto el del `.vbox` o `kali-plab`). |
| `--iface NOMBRE` | Nombre de la interfaz Host-only (por defecto la indicada en `config/local.json`, ej. `vboxnet0`). |
| `--memory MB` | RAM asignada en MiB (por defecto `4096`, mínimo `1024`). |
| `--cpus N` | Número de vCPUs asignadas (por defecto `4`, mínimo `1`). |
| `--vram MB` | Memoria de vídeo en MiB (por defecto `128`). |

#### Qué configura automáticamente el script:
1. **Disco y controladora:** Si existe el `.vbox` oficial, lo importa. Si no, crea una máquina `Debian_64` con controladora SATA (`IntelAhci`) y conecta el `.vdi`.
2. **Hardware:** Asigna 4 vCPUs, 4 GiB de RAM, 128 MiB de VRAM con controlador gráfico `VMSVGA`, y activa el portapapeles y la función arrastrar y soltar bidireccionales.
3. **Red dual:**
   - **Adaptador 1 (Host-only):** Conectado a la interfaz del laboratorio (`vboxnet0`) para alcanzar los contenedores vulnerables. Kali recibe IP `.100-.199` por DHCP.
   - **Adaptador 2 (NAT):** Proporciona salida a Internet para actualizar herramientas y paquetes dentro de Kali.
4. **Aislamiento estricto de Localhost (Solución al fallo de NAT):** Neutraliza la fuga hacia el loopback del anfitrión aplicando el parche directo en el archivo `.vbox` (ver detalle más abajo).
5. **Persistencia:** Registra los datos de la VM (`uuid`, `name`, `vdi`, etc.) en `state/kali-vm.json`.

---

### Método B: Configuración manual paso a paso

Si prefieres registrar la máquina manualmente desde la interfaz gráfica de VirtualBox o por comandos directos:

1. Descarga la imagen **VirtualBox** desde [kali.org](https://www.kali.org/get-kali/#kali-virtual-machines) y verifica su SHA-256.
2. Descomprímela con `7z x` e impórtala: *Máquina → Añadir…* y selecciona el archivo `.vbox`.
3. En *Configuración → Red*:
   - **Adaptador 1**: *Conectado a: Adaptador solo-anfitrión* y *Nombre:* la interfaz del laboratorio (ej. `vboxnet0`).
   - **Adaptador 2**: *Conectado a: NAT* (da salida a Internet a Kali).
4. **Endurecimiento imprescindible:** Con la VM apagada, ejecuta:
   ```bash
   VBoxManage modifyvm "<nombre de la VM>" --nat-localhostreachable2 off
   ```
   Y para asegurar que el cambio persista tras reiniciar la máquina (ver sección 4), aplica el parche en el `.vbox`:
   ```bash
   sed -i -E 's/localhost-reachable="true"/localhost-reachable="false"/g' ~/"VirtualBox VMs/<nombre>/<nombre>.vbox"
   sed -i -E 's|<NAT ?/>|<NAT localhost-reachable="false"/>|g' ~/"VirtualBox VMs/<nombre>/<nombre>.vbox"
   ```
5. Arranca la VM. Las credenciales por defecto de la imagen oficial son `kali` / `kali`.

---

## 4. Seguridad: El riesgo de NAT y el parche de `localhost-reachable`

### El problema de seguridad en VirtualBox NAT
En el modo NAT de VirtualBox, la dirección de pasarela (`10.0.2.2` o `10.0.3.2` según el adaptador) no es una entidad aislada: representa el **loopback (`127.0.0.1`) del equipo anfitrión**. 

Desde Kali, un atacante o una herramienta ejecutada dentro de la VM podría alcanzar cualquier puerto que escuche en el anfitrión en `127.0.0.1` (servidores de desarrollo locales, bases de datos internas, agentes administrativos, puertos de depuración, etc.). Dado que el proceso de VirtualBox efectúa estas conexiones directamente en el espacio de usuario del anfitrión, **el firewall del host (`pentestlab-fw` / iptables) no puede interceptarlas**.

### La limitación de VirtualBox 7 y por qué hace falta el parche XML
VirtualBox 7.0 introdujo la opción de apagar este comportamiento con:
```bash
VBoxManage modifyvm "<nombre>" --nat-localhostreachable2 off
```
Sin embargo, se ha demostrado que **esta opción no sobrevive de forma fiable**:
1. Al aplicar `off`, VirtualBox guarda la etiqueta en el archivo `.vbox` como `<NAT/>` (sin el atributo `localhost-reachable`).
2. Al recargar la configuración o apagar la VM, VirtualBox interpreta `<NAT/>` sin atributos con su valor implícito por defecto (`true`), reactivando la comunicación hacia el localhost del anfitrión.
3. Además, cualquier invocación posterior a `modifyvm` sobreescribe el archivo `.vbox` a partir de la memoria de VirtualBox.

### Solución implementada por el instalador
El instalador automatiza la solución definitiva en `scripts/linux/install.sh`:
- Desactiva el acceso mediante `VBoxManage modifyvm`.
- Aplica un parche `sed` directo sobre el archivo XML `.vbox` para forzar explícitamente:
  ```xml
  <NAT localhost-reachable="false"/>
  ```
- Este parche se aplica **como la última operación**, después de cualquier llamada a `VBoxManage`, asegurando que el atributo `localhost-reachable="false"` quede grabado permanentemente en el disco.
- El script de verificación de aislamiento (`kali-probe.sh`) y la opción `install.sh --phase kali-vm --check` validan activamente que el loopback sea inalcanzable.

---

## 5. Particularidades de red y verificación

- **Aparición de la interfaz en el host:** VirtualBox crea la interfaz `vboxnetN`, pero el kernel de Linux puede no mostrar su dirección IP hasta que la interfaz se active o una VM arranque. Si `./manager start` alerta de que la IP no responde, inicia la VM de Kali y vuelve a probar.
- **Rutas en Kali:** Kali recibe IP por DHCP en el Adaptador 1 (Host-only). Verifica dentro de Kali con `ip route` que la ruta por defecto (`default via 10.0.2.2` o `10.0.3.2`) apunte a la interfaz NAT (para tener Internet) y que la red `192.168.56.0/24` o `192.168.57.0/24` vaya por la interfaz Host-only. Si fuera necesario corregirlo en Kali:
  ```bash
  nmcli connection modify "<nombre-conexion-hostonly>" ipv4.never-default yes ipv4.ignore-auto-dns yes
  ```
- **Pruebas de aislamiento:** Ejecuta siempre las pruebas descritas en la [guía de verificación](../testing/pruebas.md#3-desde-la-vm-de-kali).

---

## 6. Desinstalación y limpieza

Para revertir la configuración sin perder el trabajo ni el disco descargado:

```bash
# 1. Desregistrar la máquina de VirtualBox y limpiar state/kali-vm.json
#    (El disco .vdi se conserva en el disco)
scripts/linux/install.sh --phase kali-vm --remove

# 2. Eliminar la interfaz Host-only y el servidor DHCP del laboratorio
scripts/linux/install.sh --phase uninstall
```

Si deseas eliminar definitivamente la imagen descargada y los discos para liberar espacio, borra manualmente los archivos `.vdi` y `.vbox` de la carpeta del proyecto.
