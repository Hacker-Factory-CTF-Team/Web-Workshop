# KVM/QEMU y VM de Kali

**Estado: probado** el 2026-11-23 en CachyOS con libvirt 12.9 y `qemu-desktop`, con ufw y Tailscale activos y una VM de Kali real con dos NIC (laboratorio + NAT). Resultados:
- Kali alcanza los 6 puertos del laboratorio y ningún otro servicio del anfitrión;
- tiene Internet por su NIC NAT;
- el anfitrión no enruta nada de lo que Kali envía por la red de laboratorio.

## 1. Paquetes y servicios

Comprueba primero que la CPU tiene virtualización:

```bash
grep -cE 'vmx|svm' /proc/cpuinfo     # > 0
ls -l /dev/kvm                       # debe existir
```

| Distribución | Paquetes |
|---|---|
| Arch / CachyOS (probado) | `sudo pacman -S --needed qemu-desktop libvirt virt-manager dnsmasq 7zip` |
| Debian / Ubuntu (no probado) | `sudo apt-get install -y qemu-system-x86 libvirt-daemon-system virt-manager 7zip` |
| Fedora (no probado) | `sudo dnf install -y @virtualization 7zip` |

`qemu-desktop` (Arch) es QEMU para la arquitectura del anfitrión con soporte gráfico SPICE; no hace falta `qemu-full`. `dnsmasq` es el servidor DHCP de las redes libvirt. `7zip` sirve para descomprimir la imagen de Kali.

Activa los demonios modulares de libvirt. El cliente (`virsh`, virt-manager) busca el socket de `virtqemud`, no el del antiguo `libvirtd`:

```bash
sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket virtnodedevd.socket virtlogd.socket
sudo usermod -aG libvirt "$USER"     # cierra sesión y vuelve a entrar
```

Comprobación:

```bash
virsh -c qemu:///system net-list --all
```

## 2. Redes: laboratorio y NAT

Kali tiene **dos NIC**:

| NIC | Red libvirt | Bridge en el anfitrión | Para qué |
|---|---|---|---|
| 1 | `pentestlab` (la crea el instalador) | `virbr-plab` | Acceder a los laboratorios |
| 2 | `default` (NAT, viene con libvirt) | `virbr0` | Internet para actualizar Kali e instalar herramientas |

Desde la carpeta del repositorio, **sin `sudo`**:

```bash
scripts/linux/install.sh --phase network --hypervisor kvm
# con otra subred: añade --ip 192.168.158.1
```

El instalador:
1. comprueba que la subred no se solapa con ninguna interfaz;
2. define la red `pentestlab`, si no existía, pide confirmación;
3. la inicia;
4. guarda en `config/local.json` la plataforma `linux-kvm`, la IP y la interfaz `virbr-plab`;
5. prepara la red NAT `default`: pregunta si debe iniciarla y si debe arrancar con el sistema, y guarda su bridge (`virbr0`) como `nat_interface`.

Si `pentestlab` ya existe y está al día, no la modifica.

### Definición de la red de laboratorio

```xml
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
  <name>pentestlab</name>
  <forward mode='route'/>
  <bridge name='virbr-plab' stp='on' delay='0'/>
  <dns enable='no'/>
  <ip address='192.168.157.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.157.100' end='192.168.157.199'/>
    </dhcp>
  </ip>
  <dnsmasq:options>
    <dnsmasq:option value='dhcp-option=3'/>
    <dnsmasq:option value='dhcp-option=6'/>
  </dnsmasq:options>
</network>
```

- **`forward mode='route'` y no `isolated`.** En modo `isolated`, libvirt rechaza todo el tráfico reenviado, incluido el de Kali hacia los puertos publicados por Docker: Docker los publica con DNAT y el paquete se reenvía hacia el bridge del proxy. El modo `route` no hace NAT. Lo que impide que Kali use el anfitrión como router es el firewall del laboratorio ([firewall-linux.md](../networking/firewall-linux.md)).
- **`dhcp-option=3` y `dhcp-option=6` vacías.** El DHCP no anuncia pasarela ni DNS. Sin esto, Kali enviaría su tráfico de Internet por la red de laboratorio (donde el firewall lo descarta) en lugar de por su NIC NAT.
- **El nombre `virbr-plab` no empieza por `plab`.** El prefijo `plab` está reservado a los bridges de Docker, y el firewall descarta todo lo que entra por ellos.

> Si creaste `pentestlab` con una versión anterior del instalador, la red anuncia pasarela. Al volver a ejecutar la fase `network`, el instalador lo detecta y ofrece redefinirla. **Apaga Kali antes**, porque su NIC de laboratorio se desconecta.

### Red NAT y firewall

Docker pone la política de `FORWARD` en DROP y, si tienes ufw, este deniega las conexiones entrantes. Con cualquiera de los dos, el NAT de libvirt deja de funcionar: Kali no recibe IP ni sale a Internet. Por eso `pentestlab-fw` gestiona también `virbr0` ([detalle](../networking/firewall-linux.md#plab-fwd-tráfico-reenviado)):

- acepta el DHCP y el DNS de libvirt en `virbr0`;
- reenvía hacia fuera lo que sale de `virbr0` y deja volver las respuestas;
- impide que, desde `virbr0`, se alcancen servicios del anfitrión, la red de laboratorio o los bridges de Docker.

Estas reglas, como el resto, solo existen mientras están aplicadas. **Tras reiniciar el anfitrión, Kali no tiene Internet hasta el siguiente `./manager start`**, o hasta aplicarlas a mano con `sudo pentestlab-fw apply --ip IP --iface virbr-plab --nat-iface virbr0`.

Si no existe la red `default`, el instalador avisa y Kali se queda sin Internet. Puedes crearla con virt-manager: *Editar → Detalles de la conexión → Redes virtuales*.

Comprobación:

```bash
ip -br addr show virbr-plab          # 192.168.157.1/24
virsh -c qemu:///system net-list     # pentestlab y default activas
./manager config show                # ... interfaz: virbr-plab  NAT de Kali: virbr0
```

Después instala el firewall y las imágenes, si aún no lo has hecho ([linux.md](linux.md#4-firewall-e-imágenes)).

## 3. VM de Kali

### 3.1 Imagen

1. Descarga la imagen **QEMU** de 64 bits desde https://www.kali.org/get-kali/#kali-virtual-machines.
2. Compara su SHA-256 con el publicado en esa página:

   ```bash
   sha256sum kali-linux-*-qemu-amd64.7z
   ```

3. Descomprímela y muévela al almacén de libvirt:

   ```bash
   7z x kali-linux-*-qemu-amd64.7z
   sudo mv kali-linux-*-qemu-amd64.qcow2 /var/lib/libvirt/images/kali-plab.qcow2
   ```

La imagen debe estar en `/var/lib/libvirt/images/`: la conexión `qemu:///system` ejecuta QEMU con el usuario `qemu`, que no puede leer tu carpeta personal.

### 3.2 Crear la VM

```bash
virt-install --connect qemu:///system --name kali-plab \
  --memory 4096 --vcpus 2 --import \
  --disk /var/lib/libvirt/images/kali-plab.qcow2,bus=virtio \
  --osinfo linux2022 \
  --network network=pentestlab,model=virtio \
  --network network=default,model=virtio \
  --graphics spice --video virtio --channel spicevmc \
  --noautoconsole
```

- `--import` arranca desde el disco ya instalado; no hay instalador.
- **Primera NIC**: la red de laboratorio (`eth0` en Kali). **Segunda NIC**: la red NAT (`eth1`).
- `--channel spicevmc` activa el portapapeles compartido entre el anfitrión y Kali.

Para añadir la NIC NAT a una VM que ya tenías:

```bash
virsh -c qemu:///system attach-interface kali-plab network default --model virtio --live --config
```

Después, en Kali: `sudo nmcli device connect eth1`.

La VM arranca sola. Abre su consola:

```bash
virt-manager --connect qemu:///system --show-domain-console kali-plab
```

Usuario y contraseña por defecto de las imágenes oficiales: `kali` / `kali`. Cámbiala con `passwd`.

> **virt-manager no muestra la VM.** Probablemente solo tiene configurada otra conexión, como `lxc:///`. En *Archivo → Añadir conexión…* elige *QEMU/KVM*, marca *Conectar automáticamente* y pulsa *Conectar*. La VM está en `qemu:///system`, no en `qemu:///session`.

### 3.3 Comprobar la red de Kali

En el anfitrión (con los laboratorios arrancados, para que el firewall esté aplicado):

```bash
virsh -c qemu:///system net-dhcp-leases pentestlab     # IP .100-.199, nombre "kali"
virsh -c qemu:///system net-dhcp-leases default        # IP 192.168.122.x
```

En Kali:

```bash
ip route        # "default via 192.168.122.1 dev eth1" y NINGUNA ruta por defecto por eth0
ping -c2 1.1.1.1
```

Sigue con la [verificación de aislamiento desde Kali](../testing/pruebas.md#3-desde-la-vm-de-kali).

## 4. Desinstalar

```bash
virsh -c qemu:///system destroy kali-plab                          # si está encendida
virsh -c qemu:///system undefine kali-plab --remove-all-storage    # borra la VM y su disco
scripts/linux/install.sh --phase uninstall                         # quita la red pentestlab si la creó el instalador
```

La red `default` es de libvirt y no se toca. Si quieres que deje de arrancar con el sistema: `virsh -c qemu:///system net-autostart default --disable`.

## 5. Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `virsh`: *Incorrecto al conectar zócalo a '/var/run/libvirt/virtqemud-sock'* | Los demonios modulares no están activos. Ejecuta el `systemctl enable --now` de la sección 1 |
| virt-install: *Permission denied* sobre el qcow2 | La imagen está en `$HOME`. Muévela a `/var/lib/libvirt/images/` |
| Kali no obtiene IP en `eth0` | Comprueba `virsh net-info pentestlab` (activa) y que el firewall está aplicado (`./manager network-check`) |
| `eth1` *disconnected* o sin IP | Las reglas del NAT no están aplicadas (tras reiniciar, hasta el siguiente `./manager start`) o `config show` no muestra `NAT de Kali: virbr0` (repite la fase `network` y después la fase `firewall`). Luego `sudo nmcli device connect eth1` |
| `ping 1.1.1.1`: *Network is unreachable* | Kali no tiene ruta por defecto: `eth1` sin IP (fila anterior) |
| Kali tiene `default via 192.168.157.1 dev eth0` | La red de laboratorio anuncia pasarela (versión anterior del instalador). Repite la fase `network` y acepta redefinirla, con Kali apagada |
| `./manager start`: *la IP 192.168.157.1 está en 'X' pero la configurada es 'virbr-plab'* | Otra interfaz tiene la IP. Elige otra subred con `--ip` |
| Tras reiniciar, `start` dice que falta la interfaz | La red no tiene arranque automático: `virsh -c qemu:///system net-autostart pentestlab` y `net-start pentestlab` |
